import AppKit
import MetalKit

final class EffectPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FrostOverlay {
    let panel: EffectPanel
    let view: MTKView
    let renderer: FrostRenderer
    private(set) var shown = false

    init() throws {
        renderer = try FrostRenderer()
        panel = EffectPanel(contentRect: .init(x: 0,y: 0,width: 1,height: 1),styleMask: [.borderless,.nonactivatingPanel],backing: .buffered,defer: false)
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow))+1)
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
        view = MTKView(frame: .zero, device: renderer.device)
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.preferredFramesPerSecond = 60
        view.framebufferOnly = true
        view.isPaused = true
        view.delegate = renderer
        view.layer?.isOpaque = false
        panel.contentView = view
        // An almost invisible owned window ensures ScreenCaptureKit can find
        // this process for exclusion. Never capture without excluding it.
        panel.alphaValue = 0.001
        panel.orderFrontRegardless()
    }

    func prepare(on screen: NSScreen) {
        panel.setFrame(screen.frame, display: false)
        if let layer = view.layer as? CAMetalLayer { layer.displaySyncEnabled = true; layer.isOpaque = false }
        view.isPaused = false
    }

    func reveal() {
        guard !shown else { return }
        shown = true
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    func hide() {
        shown = false
        view.isPaused = true
        panel.alphaValue = 0.001
        panel.setFrame(.init(x: 0,y: 0,width: 1,height: 1), display: false)
        renderer.clear()
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
    static var builtIn: NSScreen? {
        screens.first { guard let id = $0.displayID else { return false }; return CGDisplayIsBuiltin(id) != 0 && CGDisplayIsActive(id) != 0 }
    }
}
