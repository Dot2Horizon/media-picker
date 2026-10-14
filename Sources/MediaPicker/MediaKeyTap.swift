import Cocoa

/// 미디어키(F7 이전 · F8 재생/일시정지 · F9 다음)를 가로채 시스템 대신 처리한다.
/// 이벤트 탭은 메인 런루프에서 돌기 때문에 콜백도 메인 스레드에서 불린다.
final class MediaKeyTap {
    static let playKey = 16     // NX_KEYTYPE_PLAY
    static let nextKey = 17     // NX_KEYTYPE_NEXT
    static let previousKey = 18 // NX_KEYTYPE_PREVIOUS
    // 애플 키보드의 F9/F7은 FAST/REWIND로 오기도 한다.
    private static let fastKey = 19
    private static let rewindKey = 20

    enum Key { case playPause, next, previous }
    /// 우리가 직접 다시 보내는 이벤트를 표시해, 탭이 그 이벤트를 또 잡지 않게 한다.
    static let syntheticMarker: Int64 = 0x4D50_4B52

    var onDown: ((Key) -> Void)?
    var onUp: ((Key) -> Void)?

    private var tap: CFMachPort?

    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func start() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1 << 14) // NSEvent.EventType.systemDefined
        let ref = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, ref in
                let me = Unmanaged<MediaKeyTap>.fromOpaque(ref!).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: ref
        ) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == 14,
              event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker,
              let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8
        else { return Unmanaged.passUnretained(event) }

        let data1 = ns.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let flags = data1 & 0xFFFF
        let key: Key
        switch keyCode {
        case Self.playKey: key = .playPause
        case Self.nextKey, Self.fastKey: key = .next
        case Self.previousKey, Self.rewindKey: key = .previous
        default: return Unmanaged.passUnretained(event)
        }

        let isDown = ((flags & 0xFF00) >> 8) == 0xA
        let isRepeat = (flags & 0x1) == 1
        if isDown {
            if !isRepeat { onDown?(key) }
        } else {
            onUp?(key)
        }
        return nil // 시스템에는 넘기지 않는다
    }

    /// 우리가 모르는 플레이어만 있을 때, 원래 시스템 동작대로 키를 흘려보낸다.
    static func postSystemKey(_ keyCode: Int) {
        for down in [true, false] {
            let flags = down ? 0xA00 : 0xB00
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: (keyCode << 16) | flags,
                data2: -1
            )
            guard let cg = event?.cgEvent else { continue }
            cg.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            cg.post(tap: .cghidEventTap)
        }
    }
}
