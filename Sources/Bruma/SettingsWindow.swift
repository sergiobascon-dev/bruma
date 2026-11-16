import AppKit
import BrumaCore

@MainActor
final class SettingsWindow: NSObject {
    let window: NSWindow
    private unowned let app: BrumaApp
    private let status = NSTextField(wrappingLabelWithString: "")
    private let toggle = NSButton(title: "Activar en mi escritorio", target: nil, action: nil)
    private let preview = NSImageView()
    private let previewRenderer: FrostRenderer?
    private var values: [Int: NSTextField] = [:]
    private var previewAngle = 64.0

    init(app: BrumaApp) {
        self.app = app
        previewRenderer = try? FrostRenderer()
        window = NSWindow(contentRect: .init(x: 0,y: 0,width: 560,height: 680),styleMask: [.titled,.closable,.miniaturizable],backing: .buffered,defer: false)
        window.title = "Bruma"
        window.isReleasedWhenClosed = false
        super.init()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = .init(top: 22,left: 26,bottom: 22,right: 26)
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),stack.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor)])
        let title = NSTextField(labelWithString: "De la bruma a la claridad.")
        title.font = .systemFont(ofSize: 26,weight: .semibold)
        stack.addArrangedSubview(title)
        let subtitle = NSTextField(wrappingLabelWithString: "Abre la tapa y tu escritorio se vuelve nítido. El desenfoque crece hacia arriba y conserva el detalle junto al Dock.")
        subtitle.textColor = .secondaryLabelColor
        stack.addArrangedSubview(subtitle)
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 10
        preview.layer?.masksToBounds = true
        stack.addArrangedSubview(preview)
        preview.widthAnchor.constraint(equalToConstant: 508).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 180).isActive = true
        let note = NSTextField(labelWithString: "Patrón de prueba · sin capturar tu pantalla")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        stack.addArrangedSubview(note)
        addSlider(to: stack,title: "Apertura simulada",value: previewAngle,min: 12,max: 130,tag: 0)
        addSlider(to: stack,title: "Intensidad",value: app.intensity,min: 0,max: 85,tag: 1)
        addSlider(to: stack,title: "Conservar detalle en el Dock",value: app.dockProtection,min: 0,max: 1,tag: 2)
        addSlider(to: stack,title: "Empezar por debajo de",value: app.triggerAngle,min: 60,max: 130,tag: 3)
        addSlider(to: stack,title: "Despejar al dejar quieta la tapa",value: app.settleDelay,min: 0.4,max: 3,tag: 4)
        addSlider(to: stack,title: "Perspectiva (opcional)",value: app.perspective,min: 0,max: 1,tag: 5)
        toggle.target = self; toggle.action = #selector(toggleAction)
        toggle.bezelStyle = .rounded
        let demo = NSButton(title: "Probar escritorio · 6 s", target: app, action: #selector(BrumaApp.demo))
        demo.bezelStyle = .rounded
        let buttons = NSStackView(views: [toggle,demo])
        buttons.spacing = 12
        stack.addArrangedSubview(buttons)
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        stack.addArrangedSubview(status)
        status.widthAnchor.constraint(equalToConstant: 508).isActive = true
        let privacy = NSTextField(wrappingLabelWithString: "Todo ocurre en tu Mac. Solo se usa captura de pantalla al activar el efecto; las imágenes no se guardan ni se envían. Detener: ⌃⌥⌘B. Cerrar esta ventana deja Bruma en la barra de menús.")
        privacy.font = .systemFont(ofSize: 11)
        privacy.textColor = .secondaryLabelColor
        stack.addArrangedSubview(privacy)
        app.onStatus = { [weak self] in self?.refresh() }
        window.center()
        refresh(); renderPreview()
    }

    private func addSlider(to stack: NSStackView, title: String,value: Double,min: Double,max: Double,tag: Int) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        let number = NSTextField(labelWithString: formatted(value,tag: tag))
        number.font = .monospacedDigitSystemFont(ofSize: 11,weight: .regular)
        number.alignment = .right
        number.widthAnchor.constraint(equalToConstant: 48).isActive = true
        values[tag] = number
        let slider = NSSlider(value: value,minValue: min,maxValue: max,target: self,action: #selector(sliderChanged(_:)))
        slider.tag = tag
        slider.isContinuous = true
        slider.setAccessibilityLabel(title)
        slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        let row = NSStackView(views: [label,slider,number])
        row.distribution = .fill
        row.spacing = 10
        label.widthAnchor.constraint(equalToConstant: 260).isActive = true
        stack.addArrangedSubview(row)
    }

    private func formatted(_ value: Double,tag: Int) -> String {
        switch tag {
        case 0,3: return "\(Int(value))°"
        case 2,5: return "\(Int(value*100))%"
        case 4: return String(format: "%.1f s",value)
        default: return "\(Int(value))"
        }
    }

    @objc private func sliderChanged(_ slider: NSSlider) {
        let v = slider.doubleValue
        values[slider.tag]?.stringValue = formatted(v,tag: slider.tag)
        switch slider.tag {
        case 0: previewAngle = v
        case 1: app.intensity = v
        case 2: app.dockProtection = v
        case 3: app.triggerAngle = v
        case 4: app.settleDelay = v
        case 5: app.perspective = v
        default: break
        }
        renderPreview()
    }

    private func renderPreview() {
        guard let renderer = previewRenderer else { return }
        renderer.radius = Float(app.intensity)
        renderer.dockProtection = Float(app.dockProtection)
        renderer.perspective = Float(app.perspective)
        let width = 1024, height = 408
        guard let pixels = try? renderer.renderTest(pixels: Diagnostics.artwork(width: width,height: height),width: width,height: height,amount: EffectPolicy.amount(angle: previewAngle,trigger: app.triggerAngle)),
              let image = Diagnostics.image(pixels: pixels,width: width,height: height) else { return }
        preview.image = NSImage(cgImage: image,size: .init(width: 508,height: 202))
    }

    func refresh() {
        status.stringValue = app.message
        toggle.title = app.isEnabled ? "Pausar Bruma" : "Activar en mi escritorio"
    }

    @objc private func toggleAction() { app.toggle(); refresh() }
    func show() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
}
