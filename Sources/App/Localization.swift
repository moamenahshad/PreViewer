import Foundation

enum L10n {
    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        let format = NSLocalizedString(key, bundle: .main, comment: "")
        return arguments.isEmpty ? format : String(format: format, locale: Locale.current, arguments: arguments)
    }

    static var isArabic: Bool {
        Locale.current.language.languageCode?.identifier == "ar"
    }
}
