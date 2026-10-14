import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let bridge = BridgeServer()
    private lazy var controller = MediaController(bridge: bridge)
    private let tap = MediaKeyTap()
    private lazy var picker = PickerController(controller: controller)
    private var statusItem: NSStatusItem!
    private var statusLine: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var retryTimer: Timer?

    /// 이만큼 누르고 있으면 '길게 누름'으로 본다.
    private let holdThreshold: TimeInterval = 0.45
    private var holdTimer: Timer?
    private enum Press { case idle, pending, held }
    private var press = Press.idle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("launch \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?")")
        setupStatusItem()
        bridge.start()
        controller.startPolling()
        tap.onDown = { [weak self] key in
            switch key {
            case .playPause: self?.keyDown()
            case .next: self?.skip(.next)
            case .previous: self?.skip(.previous)
            }
        }
        tap.onUp = { [weak self] key in
            if key == .playPause { self?.keyUp() }
        }
        startTap()
    }

    // MARK: - F8

    /// F8 한 손 조작 (⌘Tab과 같은 감각): 길게 = 열기/실행, 짧게 = 정지·재개/이동.
    /// - 창 닫힘: 짧게 → 재생 중인 것 정지/마지막 것 재개, 길게 → 선택 창 열기
    /// - 창 열림: 짧게 → 다음 항목으로, 길게 → 강조된 항목 재생/정지하고 닫기
    private func keyDown() {
        let pickerWasOpen = picker.isOpen
        if pickerWasOpen { picker.touch() }
        press = .pending
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: holdThreshold, repeats: false) { [weak self] _ in
            guard let self, self.press == .pending else { return }
            self.press = .held
            if pickerWasOpen {
                Log.write("F8 hold in picker: confirm")
                self.picker.confirm()
            } else {
                Log.write("F8 hold: picker")
                self.picker.show()
            }
        }
    }

    private func keyUp() {
        holdTimer?.invalidate()
        holdTimer = nil
        if press == .pending {
            if picker.isOpen {
                picker.moveSelection(1)
            } else {
                controller.shortPress()
            }
        }
        press = .idle
    }

    /// F7/F9: 선택 창이 떠 있으면 강조된 항목을, 아니면 재생 중인 것을 넘긴다.
    private func skip(_ action: MediaAction) {
        if picker.isOpen {
            picker.skipSelected(action)
        } else {
            controller.skip(action)
        }
    }

    // MARK: - 권한

    private func startTap() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if tap.start() {
            Log.write("event tap ready")
            updateStatusIcon()
            return
        }
        Log.write("event tap unavailable: waiting for Accessibility permission")
        updateStatusIcon()
        // 손쉬운 사용 권한을 줄 때까지 기다린다.
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, self.tap.start() else { return }
            timer.invalidate()
            Log.write("event tap ready")
            self.updateStatusIcon()
        }
    }

    // MARK: - 메뉴바

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "F8 짧게: 재생 중인 것 정지 / 마지막 것 재개", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "F8 길게: 재생할 미디어 선택", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "F7 / F9: 재생 중인 미디어의 이전 / 다음", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "선택 창 열기", action: #selector(openPicker), keyEquivalent: "p").target = self
        menu.addItem(withTitle: "브라우저 확장 설치…", action: #selector(installExtension), keyEquivalent: "").target = self
        loginItem = menu.addItem(withTitle: "로그인 시 실행", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(.separator())
        statusLine = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "손쉬운 사용 권한 설정…", action: #selector(openAccessibility), keyEquivalent: "").target = self
        menu.addItem(withTitle: "로그 보기", action: #selector(openLog), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let browsers = bridge.connectedBrowsers.sorted()
        let parts = [
            tap.isRunning ? "F8 ✓" : "F8 ✗ 권한 필요",
            browsers.isEmpty ? "확장 연결 없음" : "확장: \(browsers.joined(separator: ", "))",
            String(format: "스캔 %.2f초", controller.lastScanSeconds),
        ]
        statusLine.title = parts.joined(separator: "  ·  ")
    }

    private func updateStatusIcon() {
        let ok = tap.isRunning
        let symbol = ok ? "playpause.fill" : "exclamationmark.triangle"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "MediaPicker")
        statusItem.button?.toolTip = ok ? "MediaPicker" : "MediaPicker: 손쉬운 사용 권한이 필요합니다"
    }

    @objc private func openPicker() {
        // 메뉴가 닫힌 뒤에 띄워야 창이 바로 닫히지 않는다.
        DispatchQueue.main.async { self.picker.show() }
    }

    /// 앱에 들어 있는 확장을 고정된 위치로 복사해 두고, 크롬 확장 페이지와 함께 연다.
    /// ('압축해제된 확장 프로그램 로드'는 폴더 경로를 기억하므로 앱을 옮겨도 안 깨지게)
    @objc private func installExtension() {
        guard let source = Bundle.main.url(forResource: "Extension", withExtension: nil) else { return }
        let target = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MediaPicker/Extension")
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        do {
            try FileManager.default.copyItem(at: source, to: target)
        } catch {
            Log.write("extension copy failed \(error)")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([target])

        let alert = NSAlert()
        alert.messageText = "브라우저 확장 설치"
        alert.informativeText = """
        1. 크롬 주소창에 chrome://extensions 입력
        2. 오른쪽 위 '개발자 모드' 켜기
        3. '압축해제된 확장 프로그램 로드' → 방금 열린 Extension 폴더 선택

        Edge·Brave·Arc도 같은 방법으로 설치할 수 있습니다.
        설치하면 'Apple Events의 JavaScript 허용'은 필요 없습니다.
        """
        alert.addButton(withTitle: "확인")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Log.write("login item failed \(error)")
        }
    }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(Log.url)
    }
}
