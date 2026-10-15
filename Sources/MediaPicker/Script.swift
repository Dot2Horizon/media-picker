import Foundation

struct ScriptError: Error {
    let message: String
    let code: Int

    /// 사용자에게 보여줄 해결 방법
    func hint(app: String) -> String {
        if code == -1743 {
            return L("%@: Automation permission required (System Settings › Privacy & Security › Automation)", app)
        }
        if message.localizedCaseInsensitiveContains("JavaScript") || message.contains("자바스크립트") {
            return L("%@: Install the MediaPicker browser extension (menu bar › Install Browser Extension…)", app)
        }
        return "\(app): \(message)"
    }
}

enum Script {
    /// NSAppleScript는 이 큐에서만 실행한다.
    static let queue = DispatchQueue(label: "mediapicker.applescript")

    @discardableResult
    static func run(_ source: String) -> Result<String, ScriptError> {
        guard let script = NSAppleScript(source: source) else {
            return .failure(ScriptError(message: "could not create script", code: 0))
        }
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
        if let error {
            return .failure(ScriptError(
                message: error[NSAppleScript.errorMessage] as? String ?? "unknown error",
                code: error[NSAppleScript.errorNumber] as? Int ?? 0
            ))
        }
        return .success(output.stringValue ?? "")
    }

    /// AppleScript 문자열 리터럴로 감싼다.
    static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
