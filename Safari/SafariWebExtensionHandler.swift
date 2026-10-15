import Foundation

/// 사파리 웹 확장의 네이티브 쪽. 확장은 WebSocket으로 MediaPicker 앱과 직접 이야기하므로
/// 여기서는 할 일이 없다. 사파리가 확장을 싣으려면 이 클래스가 있어야 한다.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        context.completeRequest(returningItems: [], completionHandler: nil)
    }
}
