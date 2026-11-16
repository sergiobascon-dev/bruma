import AppKit
import BrumaCore
import Carbon

@MainActor
final class BrumaApp: NSObject, NSApplicationDelegate {
    private let sensor = LidSensor()
    private let capture = DesktopCapture()
    private var overlay: FrostOverlay?
    private var policy = EffectPolicy()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var settings: SettingsWindow?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var enabled = false
    private var suspended = false
    private var demoStart: Double?
    private var lastTarget: Double = 0
    private var zeroSince = CACurrentMediaTime()
    private var permissionChecked = CACurrentMediaTime()
    private var permission = false
    private(set) var angle: Double?
    private(set) var message = "Activa Bruma para seguir la tapa."
    var onStatus: (() -> Void)?

    var isEnabled: Bool { enabled }
    var triggerAngle: Double {
        get { UserDefaults.standard.object(forKey: "trigger") as? Double ?? 110 }
        set { UserDefaults.standard.set(newValue, forKey: "trigger"); policy.triggerAngle = newValue }
    }
    var intensity: Double {
        get { UserDefaults.standard.object(forKey: "intensity") as? Double ?? 48 }
        set { UserDefaults.standard.set(newValue, forKey: "intensity"); overlay?.renderer.radius = Float(newValue) }
    }
    var dockProtection: Double {
        get { UserDefaults.standard.object(forKey: "dock") as? Double ?? 0.95 }
        set { UserDefaults.standard.set(newValue, forKey: "dock"); overlay?.renderer.dockProtection = Float(newValue) }
    }
    var settleDelay: Double {
        get { UserDefaults.standard.object(forKey: "settle") as? Double ?? 1.2 }
        set { UserDefaults.standard.set(newValue, forKey: "settle"); policy.settleDelay = newValue }
    }
    var perspective: Double {
        get { UserDefaults.standard.object(forKey: "perspective") as? Double ?? 0 }
        set { UserDefaults.standard.set(newValue, forKey: "perspective"); overlay?.renderer.perspective = Float(newValue) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do { overlay = try FrostOverlay() }
        catch { message = error.localizedDescription }
        overlay?.renderer.radius = Float(intensity)
        overlay?.renderer.dockProtection = Float(dockProtection)
        overlay?.renderer.perspective = Float(perspective)
        policy.triggerAngle = triggerAngle
        policy.settleDelay = settleDelay
        permission = CGPreflightScreenCaptureAccess()
        angle = sensor.read()
        makeMenu()
        overlay?.renderer.nextFrame = { [weak self] in
            guard let self, let receiver = self.capture.receiver else { return nil }
            let (pixels, failed) = receiver.take()
            if failed {
                self.message = "La captura se ha detenido. Desactiva y vuelve a activar Bruma."
                self.setEnabled(false)
                return nil
            }
            return pixels
        }
        overlay?.renderer.didDraw = { [weak self] amount in
            guard let self, let overlay = self.overlay else { return }
            if amount > 0.002, self.lastTarget > 0 { overlay.reveal() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(self, selector: #selector(suspend), name: name, object: nil)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(self, selector: #selector(resume), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(displayChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(suspend), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(resume), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        registerShortcut()
        showSettings()
    }

    private func makeMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "Bruma")
        let menu = NSMenu()
        for (title, selector, key) in [
            ("Activar / pausar Bruma", #selector(toggle), ""),
            ("Probar en mi escritorio (6 s)", #selector(demo), ""),
            ("Ajustes de Bruma…", #selector(showSettings), ","),
            ("Detener efecto · ⌃⌥⌘B", #selector(stopEffect), ""),
            ("Salir de Bruma", #selector(quit), "q")
        ] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        statusItem.menu = menu
    }

    @objc func showSettings() {
        if settings == nil { settings = SettingsWindow(app: self) }
        settings?.show()
    }

    @objc func toggle() { setEnabled(!enabled, requestPermission: true) }

    func setEnabled(_ newValue: Bool, requestPermission: Bool = false) {
        if newValue {
            guard overlay != nil else { onStatus?(); return }
            permission = CGPreflightScreenCaptureAccess()
            if !permission, requestPermission { permission = CGRequestScreenCaptureAccess() }
            guard permission else {
                message = "Activa Bruma en Ajustes del Sistema → Privacidad y seguridad → Grabación de pantalla. Después vuelve a pulsar Activar."
                onStatus?()
                return
            }
            enabled = true
            policy.reset()
            message = angle == nil ? "Sensor no disponible. Puedes usar la demo de escritorio." : "Lista. Mueve la tapa por debajo de \(Int(triggerAngle))°."
            startTimer()
        } else {
            enabled = false
            demoStart = nil
            timer?.invalidate(); timer = nil
            policy.reset()
            capture.stop(); overlay?.hide()
            lastTarget = 0
            message = "Bruma está en pausa."
        }
        statusItem.button?.appearsDisabled = !enabled
        onStatus?()
    }

    @objc func demo() {
        if !enabled { setEnabled(true, requestPermission: true) }
        guard enabled else { return }
        demoStart = CACurrentMediaTime()
        settings?.window.orderOut(nil)
        startTimer()
    }

    @objc func stopEffect() { setEnabled(false) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func suspend() {
        suspended = true
        timer?.invalidate(); timer = nil
        demoStart = nil
        policy.reset(); capture.stop(); overlay?.hide(); lastTarget = 0
    }

    @objc private func resume() {
        suspended = false
        policy.reset()
        sensor.reconnect()
        if enabled { startTimer() }
    }

    @objc private func displayChanged() {
        policy.reset(); capture.stop(); overlay?.hide(); lastTarget = 0
        zeroSince = CACurrentMediaTime()
    }

    private func startTimer() {
        guard timer == nil, !suspended else { return }
        timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = 0.008
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        guard enabled, !suspended, let screen = NSScreen.builtIn, let id = screen.displayID else {
            capture.stop(); overlay?.hide(); policy.reset(); lastTarget = 0
            return
        }
        if now - permissionChecked > 1 {
            permissionChecked = now
            permission = CGPreflightScreenCaptureAccess()
        }
        guard permission else {
            setEnabled(false)
            message = "Se ha retirado el permiso de captura. Bruma está en pausa."
            onStatus?()
            return
        }
        angle = sensor.read()
        var target = policy.update(angle: angle, time: now, eligible: true)
        if let start = demoStart {
            let t = now - start
            if t >= 6 { demoStart = nil; target = 0; policy.reset() }
            else { target = pow(sin(.pi * min(1,t/6)),2) * 0.85 }
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { overlay?.renderer.perspective = 0 }
        else { overlay?.renderer.perspective = Float(perspective) }
        if target > 0.001 {
            if lastTarget <= 0.001 { overlay?.prepare(on: screen) }
            capture.start(displayID: id)
            zeroSince = now
        }
        lastTarget = target
        overlay?.renderer.target = target
        if target <= 0.001, now-zeroSince > 0.4 {
            capture.stop(); overlay?.hide()
        }
        if let error = capture.error {
            setEnabled(false)
            message = "No se pudo capturar el escritorio: \(error)"
        } else if angle == nil, demoStart == nil {
            capture.stop(); overlay?.hide()
            message = "Sensor no disponible. La demo sigue funcionando."
        } else {
            message = demoStart != nil ? "Demo de escritorio · 6 segundos" : "Tapa: \(String(format: "%.1f",angle ?? 0))° · \(target > 0.001 ? "Efecto activo" : "Pantalla nítida")"
        }
        onStatus?()
    }

    private func registerShortcut() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let app = Unmanaged<BrumaApp>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in app.stopEffect() }
            return noErr
        },1,&spec,Unmanaged.passUnretained(self).toOpaque(),&eventHandler)
        let id = EventHotKeyID(signature: 0x42524D41, id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_B),UInt32(controlKey | optionKey | cmdKey),id,GetApplicationEventTarget(),0,&hotKey)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        capture.stop(); overlay?.hide()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
