import AppKit
import ImageIO
import BrumaCore

enum Diagnostics {
    /// Generated resolution chart, intentionally unrelated to the user's desktop.
    static func artwork(width: Int,height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 255,count: width*height*4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y*width+x)*4
                let stripe = (x/5) % 2 == 0
                let h = Double(y)/Double(height)
                let region = x < width/3 ? 0 : (x < width*2/3 ? 1 : 2)
                let color: [Double] = region == 0 ? [0.88,0.40,0.20] : (region == 1 ? [0.28,0.68,0.88] : [0.60,0.40,0.83])
                for c in 0..<3 {
                    pixels[i+c] = UInt8(min(255,max(0,(stripe ? 1.0 : 0.20)*color[c]*255*(0.85+0.15*h))))
                }
            }
        }
        return pixels
    }

    static func image(pixels: [UInt8],width: Int,height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width,height: height,bitsPerComponent: 8,bitsPerPixel: 32,bytesPerRow: width*4,space: CGColorSpace(name: CGColorSpace.sRGB)!,bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),provider: provider,decode: nil,shouldInterpolate: false,intent: .defaultIntent)
    }

    static func save(_ pixels: [UInt8],width: Int,height: Int,to url: URL) throws {
        guard let image = image(pixels: pixels,width: width,height: height),
              let output = CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil) else { throw BrumaError.graphics("No se pudo guardar el patrón de prueba.") }
        CGImageDestinationAddImage(output,image,nil)
        guard CGImageDestinationFinalize(output) else { throw BrumaError.graphics("No se pudo finalizar el PNG.") }
    }

    static func diagnose() {
        let sensor = LidSensor()
        print("Bruma 1.0.0 · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("Sensor: \(sensor.read().map { String(format: "%.2f° (informe %d)",$0,sensor.reportID) } ?? "no disponible")")
        print("Pantalla integrada activa: \(NSScreen.builtIn != nil)")
        print("Permiso de captura: \(CGPreflightScreenCaptureAccess())")
        do { _ = try FrostRenderer(); print("Shader Metal: compilado correctamente") }
        catch { print("Metal: \(error.localizedDescription)") }
    }

    static func renderChecks(directory: String) throws {
        let url = URL(fileURLWithPath: directory,isDirectory: true)
        try FileManager.default.createDirectory(at: url,withIntermediateDirectories: true)
        let renderer = try FrostRenderer()
        renderer.dim = 0
        renderer.radius = 48
        renderer.dockProtection = 1
        let w = 768, h = 480
        let source = artwork(width: w,height: h)
        let open = try renderer.renderTest(pixels: source,width: w,height: h,amount: 0)
        let mid = try renderer.renderTest(pixels: source,width: w,height: h,amount: 0.35)
        let closed = try renderer.renderTest(pixels: source,width: w,height: h,amount: 0.85)
        func ensure(_ condition: Bool,_ message: String) throws {
            guard condition else { throw BrumaError.graphics("Prueba fallida: \(message)") }
            print("PASS \(message)")
        }
        let maximumError = zip(source,open).map { abs(Int($0)-Int($1)) }.max() ?? 255
        try ensure(maximumError <= 1,"imagen abierta idéntica al original (error máximo \(maximumError))")
        func contrast(_ pixels: [UInt8],ys: Range<Int>) -> Double {
            var sum = 0.0; var n = 0
            for y in ys {
                for x in 20..<(w/3-20) {
                    sum += abs(Double(pixels[(y*w+x)*4])-Double(pixels[(y*w+x-1)*4])); n += 1
                }
            }
            return sum/Double(n)
        }
        let sharp = contrast(open,ys: 15..<100)
        let upper = contrast(closed,ys: 15..<100)
        let lower = contrast(closed,ys: (h-14)..<(h-2))
        try ensure(upper < sharp*0.25,"desenfoque real en la parte superior")
        try ensure(lower > upper*3,"el borde junto al Dock conserva más detalle")
        // Sample the transition band: the fine stripes at the top have already
        // vanished at both strengths and cannot measure further defocus there.
        try ensure(contrast(mid,ys: (h-100)..<(h-40)) > contrast(closed,ys: (h-100)..<(h-40)),"el desenfoque aumenta de forma progresiva")
        try ensure(stride(from: 3,to: closed.count,by: 4).allSatisfy { closed[$0] == 255 },"salida opaca sin agujeros")
        renderer.radius = 0
        let off = try renderer.renderTest(pixels: source,width: w,height: h,amount: 0.85)
        try ensure(zip(source,off).allSatisfy { abs(Int($0)-Int($1)) <= 1 },"intensidad cero desactiva el desenfoque")
        renderer.radius = 48; renderer.perspective = 1
        let perspective = try renderer.renderTest(pixels: source,width: w,height: h,amount: 0.85)
        try ensure(perspective.contains { $0 > 0 },"perspectiva opcional renderizada")
        for (name,pixels) in [("open",open),("half",mid),("closed",closed),("perspective",perspective)] {
            try save(pixels,width: w,height: h,to: url.appendingPathComponent("\(name).png"))
        }
        var montage = [UInt8](repeating: 255,count: w*3*h*4)
        for (column,pixels) in [open,mid,closed].enumerated() {
            for y in 0..<h {
                let start = (y*w*3+column*w)*4
                montage.replaceSubrange(start..<(start+w*4),with: pixels[(y*w*4)..<((y+1)*w*4)])
            }
        }
        try save(montage,width: w*3,height: h,to: url.appendingPathComponent("progressive-blur.png"))
        print(String(format: "Contraste: original %.3f · arriba %.3f · Dock %.3f",sharp,upper,lower))
        renderer.clear()
    }
}
