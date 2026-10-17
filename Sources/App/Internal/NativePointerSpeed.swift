import Cocoa
import IOKit
import Darwin

/// Adjust the native acceleration parameter on identified HID services only.
/// No mouse-move event tap, cursor warping, or replacement acceleration curve.
final class NativePointerSpeed: ObservableObject {
    static let shared = NativePointerSpeed()
    @Published private(set) var mouseStatus = "1× uses the original tracking speed"
    @Published private(set) var trackpadStatus = "1× uses the original tracking speed"
    private typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias Services = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias SetProperty = @convention(c) (CFTypeRef, CFString, CFTypeRef) -> Bool
    private typealias RegistryID = @convention(c) (CFTypeRef) -> UInt64
    private let create: Create?
    private let services: Services?
    private let copyProperty: CopyProperty?
    private let setProperty: SetProperty?
    private let registryID: RegistryID?
    private var client: CFTypeRef?
    private let savedKey = "nativePointerOriginalValues"
    private var originals: [String: [String: Any]]
    private init() {
        let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        create = dlsym(h, "IOHIDEventSystemClientCreateSimpleClient").map { unsafeBitCast($0, to: Create.self) }
        services = dlsym(h, "IOHIDEventSystemClientCopyServices").map { unsafeBitCast($0, to: Services.self) }
        copyProperty = dlsym(h, "IOHIDServiceClientCopyProperty").map { unsafeBitCast($0, to: CopyProperty.self) }
        setProperty = dlsym(h, "IOHIDServiceClientSetProperty").map { unsafeBitCast($0, to: SetProperty.self) }
        registryID = dlsym(h, "IOHIDServiceClientGetRegistryID").map { unsafeBitCast($0, to: RegistryID.self) }
        originals = UserDefaults.standard.dictionary(forKey: savedKey) as? [String: [String: Any]] ?? [:]
    }
    static func acceleration(original: Double, multiplier: Double) -> Double {
        multiplier == 1 ? original : max(0, min(20 * 65536, original + log2(multiplier) * 65536))
    }
    func apply(restoring: Bool = false) {
        let tuning = Settings.shared.deviceTuning
        let mouseFactor = restoring ? 1 : tuning.mousePointerSpeed
        let trackpadFactor = restoring ? 1 : tuning.trackpadPointerSpeed
        guard mouseFactor != 1 || trackpadFactor != 1 || !originals.isEmpty else { return }
        guard let create, let services, let copyProperty, let setProperty, let registryID else {
            mouseStatus = "Native tracking controls unavailable on this macOS version"
            trackpadStatus = mouseStatus; return
        }
        if client == nil { client = create(kCFAllocatorDefault)?.takeRetainedValue() }
        guard let client, let list = services(client)?.takeRetainedValue() else { return }
        var found: Set<GestureDevice> = []
        for index in 0..<CFArrayGetCount(list) {
            let service = unsafeBitCast(CFArrayGetValueAtIndex(list, index), to: CFTypeRef.self)
            func property(_ key: String) -> CFTypeRef? { copyProperty(service, key as CFString)?.takeRetainedValue() }
            let product = (property("Product") as? String ?? "").lowercased()
            let vendor = (property("VendorID") as? NSNumber)?.intValue ?? 0
            let productID = (property("ProductID") as? NSNumber)?.intValue ?? 0
            let device: GestureDevice
            if product.contains("trackpad") { device = .trackpad }
            else if (vendor == 0x05ac || vendor == 0x004c) && [0x030d, 0x0269, 0x0323].contains(productID) { device = .magicMouse }
            else { continue }
            let factor = device == .magicMouse ? mouseFactor : trackpadFactor
            let id = String(registryID(service))
            guard id != "0" else { continue }
            var key = originals[id]?["key"] as? String ?? property("HIDPointerAccelerationType") as? String ?? "HIDPointerAcceleration"
            var current = property(key) as? NSNumber
            if current == nil && originals[id] == nil { key = "HIDPointerAcceleration"; current = property(key) as? NSNumber }
            guard let current else { continue }
            found.insert(device)
            let original = originals[id]?["value"] as? NSNumber ?? current
            if factor != 1 && original.doubleValue < 0 {
                setStatus("Native acceleration is disabled; original tracking preserved", device: device); continue
            }
            if factor != 1 && originals[id] == nil {
                originals[id] = ["key": key, "value": original]
                UserDefaults.standard.set(originals, forKey: savedKey)
            }
            let target = factor == 1 ? original : NSNumber(value: Int32(Self.acceleration(original: original.doubleValue, multiplier: factor).rounded()))
            let accepted = current.doubleValue == target.doubleValue || setProperty(service, key as CFString, target)
            let readback = property(key) as? NSNumber
            let success = accepted && readback?.doubleValue == target.doubleValue
            if success {
                if factor == 1 { originals.removeValue(forKey: id) }
                setStatus(factor == 1 ? "Original tracking speed restored" : "Native tracking adjusted; effect varies with movement speed", device: device)
            } else { setStatus("macOS did not accept this tracking adjustment", device: device) }
        }
        UserDefaults.standard.set(originals, forKey: savedKey)
        if mouseFactor != 1 && !found.contains(.magicMouse) { setStatus("Connect Magic Mouse to apply pointer speed", device: .magicMouse) }
        if trackpadFactor != 1 && !found.contains(.trackpad) { setStatus("No supported trackpad tracking service found", device: .trackpad) }
    }
    private func setStatus(_ message: String, device: GestureDevice) {
        if device == .magicMouse { if mouseStatus != message { mouseStatus = message } }
        else if trackpadStatus != message { trackpadStatus = message }
    }
}
