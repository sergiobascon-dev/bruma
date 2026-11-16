import AppKit
import MetalKit
import MetalPerformanceShaders
import BrumaCore

enum BrumaError: LocalizedError {
    case graphics(String)
    var errorDescription: String? {
        if case let .graphics(message) = self { return message }
        return nil
    }
}

/// Only the latest captured frame and its Gaussian mip pyramid are retained.
/// A single GPU queue orders uploads, pyramid generation and display draws.
final class FrostRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let pyramidFilter: MPSImageGaussianPyramid
    private var cache: CVMetalTextureCache!
    private var picture: MTLTexture?
    private var frame: CVPixelBuffer?
    private var wrapped: CVMetalTexture?
    private var previousTime = CACurrentMediaTime()
    var target: Double = 0
    var amount: Double = 0
    var radius: Float = 48
    var dockProtection: Float = 0.95
    var dim: Float = 0.12
    var perspective: Float = 0
    var nextFrame: (() -> CVPixelBuffer?)?
    var didDraw: ((Double) -> Void)?
    var hasPicture: Bool { picture != nil }
    private let inFlight = DispatchSemaphore(value: 3)

    init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device, let queue = device.makeCommandQueue() else { throw BrumaError.graphics("Metal no está disponible.") }
        self.device = device
        self.queue = queue
        let shaderURL = Bundle.main.url(forResource: "Frost", withExtension: "metal") ?? Bundle.module.url(forResource: "Frost", withExtension: "metal")!
        let source = try String(contentsOf: shaderURL, encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "frostVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "frostFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        pyramidFilter = MPSImageGaussianPyramid(device: device, centerWeight: 0.375)
        super.init()
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess else { throw BrumaError.graphics("No se pudo crear la caché de Metal.") }
    }

    func clear() {
        picture = nil; frame = nil; wrapped = nil
        amount = 0; target = 0
        CVMetalTextureCacheFlush(cache, 0)
    }

    private func allocate(width: Int, height: Int) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: true)
        d.usage = [.shaderRead, .shaderWrite, .renderTarget]
        d.storageMode = .private
        guard let texture = device.makeTexture(descriptor: d) else { throw BrumaError.graphics("No hay memoria para el efecto.") }
        return texture
    }

    private func update(_ pixels: CVPixelBuffer, commands: MTLCommandBuffer) -> Bool {
        let w = CVPixelBufferGetWidth(pixels), h = CVPixelBufferGetHeight(pixels)
        var wrapper: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixels, nil, .bgra8Unorm_srgb, w, h, 0, &wrapper) == kCVReturnSuccess,
              let wrapper, let source = CVMetalTextureGetTexture(wrapper) else { return false }
        if picture?.width != w || picture?.height != h { picture = try? allocate(width: w, height: h) }
        guard var texture = picture, let blit = commands.makeBlitCommandEncoder() else { return false }
        blit.copy(from: source, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(x: 0,y: 0,z: 0), sourceSize: .init(width: w,height: h,depth: 1), to: texture, destinationSlice: 0,destinationLevel: 0,destinationOrigin: .init(x: 0,y: 0,z: 0))
        blit.endEncoding()
        pyramidFilter.encode(commandBuffer: commands, inPlaceTexture: &texture, fallbackCopyAllocator: nil)
        picture = texture
        frame = pixels; wrapped = wrapper
        // Retain IOSurface ownership until the GPU has finished the copy.
        commands.addCompletedHandler { [pixels, wrapper] _ in _ = pixels; _ = wrapper }
        return true
    }

    private func encode(commands: MTLCommandBuffer, pass: MTLRenderPassDescriptor, width: Int, height: Int, amount: Double) -> Bool {
        guard let picture, let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return false }
        var controls = [SIMD4<Float>(Float(amount), radius, dockProtection, dim), SIMD4<Float>(Float(width),Float(height),perspective,0)]
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(picture, index: 0)
        encoder.setFragmentBytes(&controls, length: MemoryLayout<SIMD4<Float>>.stride * 2, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return true
    }

    func draw(in view: MTKView) {
        guard inFlight.wait(timeout: .now()) == .success else { return }
        guard let commands = queue.makeCommandBuffer() else { inFlight.signal(); return }
        let now = CACurrentMediaTime()
        amount = EffectPolicy.smooth(current: amount, target: target, dt: now-previousTime)
        previousTime = now
        if let pixels = nextFrame?() { _ = update(pixels, commands: commands) }
        guard picture != nil, let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              encode(commands: commands, pass: pass, width: drawable.texture.width, height: drawable.texture.height, amount: amount) else {
            commands.addCompletedHandler { [inFlight] _ in inFlight.signal() }
            commands.commit()
            return
        }
        commands.present(drawable)
        commands.addCompletedHandler { [inFlight] _ in inFlight.signal() }
        commands.commit()
        didDraw?(amount)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    /// Synthetic diagnostics only. No desktop content is ever saved by the app.
    func renderTest(pixels: [UInt8], width: Int, height: Int, amount: Double) throws -> [UInt8] {
        guard let commands = queue.makeCommandBuffer(), let upload = device.makeBuffer(bytes: pixels, length: pixels.count), let readback = device.makeBuffer(length: pixels.count) else { throw BrumaError.graphics("No se pudo preparar la prueba GPU.") }
        var texture = try allocate(width: width, height: height)
        guard let blit = commands.makeBlitCommandEncoder() else { throw BrumaError.graphics("No se pudo copiar la imagen.") }
        blit.copy(from: upload, sourceOffset: 0, sourceBytesPerRow: width*4, sourceBytesPerImage: pixels.count, sourceSize: .init(width: width,height: height,depth: 1),to: texture,destinationSlice: 0,destinationLevel: 0,destinationOrigin: .init(x: 0,y: 0,z: 0))
        blit.endEncoding()
        pyramidFilter.encode(commandBuffer: commands, inPlaceTexture: &texture, fallbackCopyAllocator: nil)
        picture = texture
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget]; d.storageMode = .private
        guard let output = device.makeTexture(descriptor: d) else { throw BrumaError.graphics("No se pudo crear el destino.") }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard encode(commands: commands, pass: pass, width: width, height: height, amount: amount), let download = commands.makeBlitCommandEncoder() else { throw BrumaError.graphics("No se pudo renderizar la prueba.") }
        download.copy(from: output,sourceSlice: 0,sourceLevel: 0,sourceOrigin: .init(x: 0,y: 0,z: 0),sourceSize: .init(width: width,height: height,depth: 1),to: readback,destinationOffset: 0,destinationBytesPerRow: width*4,destinationBytesPerImage: pixels.count)
        download.endEncoding()
        commands.commit(); commands.waitUntilCompleted()
        if let error = commands.error { throw error }
        return Array(UnsafeBufferPointer(start: readback.contents().assumingMemoryBound(to: UInt8.self), count: pixels.count))
    }
}
