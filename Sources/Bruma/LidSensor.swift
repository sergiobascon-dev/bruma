import Foundation
import IOKit.hid

/// Read-only HID feature reports. This is an undocumented, model-dependent
/// sensor interface, not an Apple-supported public hinge-angle API.
final class LidSensor {
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private(set) var reportID = 1

    init() { reconnect() }
    deinit { if let manager { IOHIDManagerClose(manager, 0) } }

    func reconnect() {
        if let manager { IOHIDManagerClose(manager, 0) }
        device = nil
        let fresh = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        manager = fresh
        IOHIDManagerSetDeviceMatching(fresh, [
            kIOHIDVendorIDKey: 0x05AC,
            kIOHIDDeviceUsagePageKey: 0x20,
            kIOHIDDeviceUsageKey: 0x8A
        ] as CFDictionary)
        guard IOHIDManagerOpen(fresh, 0) == kIOReturnSuccess else { return }
        for candidate in IOHIDManagerCopyDevices(fresh) as? Set<IOHIDDevice> ?? [] {
            guard (IOHIDDeviceGetProperty(candidate, kIOHIDBuiltInKey as CFString) as? NSNumber)?.boolValue == true else { continue }
            device = candidate
            for report in [7, 1] {
                reportID = report
                if read() != nil { return }
            }
        }
        device = nil
    }

    func read() -> Double? {
        guard let device else { return nil }
        var bytes = [UInt8](repeating: 0, count: 32)
        var count = bytes.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, reportID, &bytes, &count)
        guard result == kIOReturnSuccess, count >= (reportID == 7 ? 5 : 3), bytes[0] == reportID else { return nil }
        var raw: UInt32 = 0
        for offset in 1..<(reportID == 7 ? 5 : 3) { raw |= UInt32(bytes[offset]) << ((offset - 1) * 8) }
        let degrees = Double(raw) / (reportID == 7 ? 100 : 1)
        return (0...180).contains(degrees) ? degrees : nil
    }
}
