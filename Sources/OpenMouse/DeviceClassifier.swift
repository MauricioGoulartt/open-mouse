import Foundation
import CoreGraphics
import IOKit
import IOKit.hid
import Darwin

/// Associates high-resolution wheel events with enumerated physical mice.
/// Unknown continuous sources remain untouched, preserving trackpads.
final class DeviceClassifier {
    private typealias CopyHIDEvent = @convention(c) (CGEvent) -> Unmanaged<CFTypeRef>?
    private typealias SenderID = @convention(c) (CFTypeRef) -> UInt64
    private var manager: IOHIDManager?
    private var mice = Set<UInt64>()
    private let copyHIDEvent: CopyHIDEvent?
    private let senderID: SenderID?

    init() {
        let symbols = UnsafeMutableRawPointer(bitPattern: -2)
        copyHIDEvent = dlsym(symbols, "CGEventCopyIOHIDEvent").map { unsafeBitCast($0, to: CopyHIDEvent.self) }
        senderID = dlsym(symbols, "IOHIDEventGetSenderID").map { unsafeBitCast($0, to: SenderID.self) }
    }
    func start() {
        guard manager == nil else { return }
        let value = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(0))
        manager = value
        IOHIDManagerSetDeviceMatching(value, ["DeviceUsagePage": 1, "DeviceUsage": 2] as CFDictionary)
        let callback: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            Unmanaged<DeviceClassifier>.fromOpaque(context).takeUnretainedValue().refresh()
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(value, callback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(value, callback, context)
        IOHIDManagerScheduleWithRunLoop(value, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        refresh()
    }
    func stop() {
        if let manager { IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) }
        manager = nil; mice.removeAll()
    }
    func isPhysicalMouse(_ event: CGEvent) -> Bool {
        if event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 { return true }
        guard let copyHIDEvent, let senderID, let reference = copyHIDEvent(event) else { return false }
        return mice.contains(senderID(reference.takeRetainedValue()))
    }
    private func refresh() {
        guard let manager else { return }
        var ids = Set<UInt64>()
        for device in (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []) {
            let name = (IOHIDDeviceGetProperty(device, "Product" as CFString) as? String ?? "").lowercased()
            if name.contains("trackpad") || name.contains("touchpad") || name.contains("magic mouse") || name.contains("wireless mouse") && name.contains("apple") { continue }
            let service = IOHIDDeviceGetService(device)
            guard service != 0 else { continue }
            var id: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS { ids.insert(id) }
        }
        mice = ids
    }
    deinit { stop() }
}
