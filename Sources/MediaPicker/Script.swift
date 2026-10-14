import Foundation

struct ScriptError: Error {
    let message: String
    let code: Int

    /// 사용자에게 보여줄 해결 방법
    func hint(app: String) -> String {
        if code == -1743 {
            return "\(app): 자동화 권한이 필요합니다 (시스템 설정 › 개인정보 보호 및 보안 › 자동화)"
        }
        if message.localizedCaseInsensitiveContains("JavaScript") || message.contains("자바스크립트") {
            return "\(app): MediaPicker 브라우저 확장을 설치하세요 (메뉴바 › 브라우저 확장 설치…)"
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
            return .failure(ScriptError(message: "스크립트 생성 실패", code: 0))
        }
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
        if let error {
            return .failure(ScriptError(
                message: error[NSAppleScript.errorMessage] as? String ?? "알 수 없는 오류",
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
