import AppKit
import CoreAudio

/// Core Audio(macOS 14.2+)로 지금 실제로 소리를 내는 앱을 찾는다. 권한이 필요 없다.
/// 브라우저·WebKit은 별도 헬퍼 프로세스가 소리를 내므로 '책임 프로세스'(본체 앱)로 묶는다.
enum AudioActivity {
    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    private static let responsiblePID: ResponsibleFn? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: ResponsibleFn.self)
    }()

    static func soundingApps() -> [NSRunningApplication] {
        var seen = Set<pid_t>()
        return processObjects().compactMap { object in
            guard property(object, kAudioProcessPropertyIsRunningOutput, UInt32(0)) == 1,
                  let pid = property(object, kAudioProcessPropertyPID, pid_t(0)) else { return nil }
            let owner = responsiblePID?(pid) ?? pid
            guard owner != getpid(), seen.insert(owner).inserted,
                  let app = NSRunningApplication(processIdentifier: owner),
                  app.activationPolicy == .regular else { return nil }
            return app
        }
    }

    private static func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    private static func property<T: BinaryInteger>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        return status == noErr ? value : nil
    }
}

/// 다른 provider가 다루지 못하는, 소리를 내고 있는 앱(IINA, Firefox 등).
/// 직접 조작할 수단이 없으므로 시스템 미디어키를 그대로 보낸다
/// (보통 소리를 내는 앱이 macOS의 '지금 재생 중' 대상이다).
struct SoundingAppProvider {
    static let idPrefix = "audio:"

    /// 통화·회의 앱은 멈추면 곤란하다.
    private static let ignored: Set<String> = [
        "us.zoom.xos", "com.hnc.Discord", "com.apple.FaceTime", "com.microsoft.teams2",
        "com.microsoft.teams", "com.tinyspeck.slackmacgap", "com.cisco.webexmeetingsapp",
        "com.skype.skype", "com.apple.Safari.WebApp",
    ]

    /// `handled`: 이미 다른 provider가 항목을 낸 앱(번들 ID)
    func scan(excluding handled: Set<String>) -> [MediaItem] {
        AudioActivity.soundingApps().compactMap { app in
            guard let bundleID = app.bundleIdentifier,
                  !handled.contains(bundleID), !Self.ignored.contains(bundleID) else { return nil }
            let name = app.localizedName ?? bundleID
            return MediaItem(
                id: Self.idPrefix + bundleID,
                bundleID: bundleID,
                title: name,
                subtitle: L("Playing sound · controlled with the system media key"),
                state: .playing,
                perform: { action in
                    let key = switch action {
                    case .play, .pause: MediaKeyTap.playKey
                    case .next: MediaKeyTap.nextKey
                    case .previous: MediaKeyTap.previousKey
                    }
                    DispatchQueue.main.async { MediaKeyTap.postSystemKey(key) }
                }
            )
        }
    }
}
