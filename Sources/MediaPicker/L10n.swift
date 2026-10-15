import Foundation

/// 화면에 보이는 문자열. 키는 영어 원문이고, 번역은 Resources/<언어>.lproj/Localizable.strings에 있다.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// 형식 문자열(%@, %d …)을 번역한 뒤 값을 채운다.
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: args)
}
