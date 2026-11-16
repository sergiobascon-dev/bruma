import AppKit
import ScreenCaptureKit
import CoreMedia

final class FrameReceiver: NSObject, SCStreamOutput, SCStreamDelegate {
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private var failed = false

    func take() -> (CVPixelBuffer?, Bool) {
        lock.lock(); defer { lock.unlock() }
        let frame = latest
        latest = nil
        return (frame, failed)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sample.isValid,
              let info = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = info.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
              let pixels = sample.imageBuffer else { return }
        lock.lock(); latest = pixels; lock.unlock()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock(); failed = true; latest = nil; lock.unlock()
    }
}

@MainActor
final class DesktopCapture {
    private var stream: SCStream?
    private var task: Task<Void, Never>?
    private var generation = 0
    private(set) var receiver: FrameReceiver?
    private(set) var error: String?
    var running: Bool { stream != nil || task != nil }

    func start(displayID: CGDirectDisplayID) {
        guard !running else { return }
        error = nil
        generation += 1
        let token = generation
        task = Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard !Task.isCancelled, generation == token else { return }
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    throw NSError(domain: "Bruma", code: 1, userInfo: [NSLocalizedDescriptionKey: "No se encuentra la pantalla integrada."])
                }
                let ownApps = content.applications.filter { $0.processID == getpid() }
                // Fail closed: never capture our own overlay into itself.
                guard !ownApps.isEmpty else {
                    throw NSError(domain: "Bruma", code: 2, userInfo: [NSLocalizedDescriptionKey: "No se pudo excluir la ventana de Bruma."])
                }
                let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
                config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                config.queueDepth = 3
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.colorSpaceName = CGColorSpace.sRGB
                config.capturesAudio = false
                config.showsCursor = false
                let sink = FrameReceiver()
                let fresh = SCStream(filter: filter, configuration: config, delegate: sink)
                try fresh.addStreamOutput(sink, type: .screen, sampleHandlerQueue: DispatchQueue(label: "app.bruma.frames", qos: .userInteractive))
                try await fresh.startCapture()
                guard !Task.isCancelled, generation == token else { try? await fresh.stopCapture(); return }
                stream = fresh
                receiver = sink
                task = nil
            } catch {
                guard generation == token else { return }
                self.error = error.localizedDescription
                task = nil
            }
        }
    }

    func stop() {
        generation += 1
        task?.cancel(); task = nil
        receiver = nil
        let old = stream
        stream = nil
        if let old { Task { try? await old.stopCapture() } }
    }
}
