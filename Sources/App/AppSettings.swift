import AppKit
import Combine

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    enum Theme: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var appearance: NSAppearance? {
            switch self {
            case .system: return nil
            case .light: return NSAppearance(named: .aqua)
            case .dark: return NSAppearance(named: .darkAqua)
            }
        }
    }

    enum Language: String, CaseIterable, Identifiable {
        case system, english = "en", arabic = "ar"
        var id: String { rawValue }
        var localeIdentifier: String? { self == .system ? nil : rawValue }
    }

    @Published var theme: Theme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "preferredTheme")
            applyTheme()
        }
    }
    @Published var language: Language {
        didSet {
            guard language != oldValue else { return }
            UserDefaults.standard.set(language.rawValue, forKey: "preferredLanguage")
            if let identifier = language.localeIdentifier {
                UserDefaults.standard.set([identifier], forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }
            NotificationCenter.default.post(name: .preViewerLanguageDidChange, object: nil)
        }
    }

    private init() {
        theme = Theme(rawValue: UserDefaults.standard.string(forKey: "preferredTheme") ?? "system") ?? .system
        language = Language(rawValue: UserDefaults.standard.string(forKey: "preferredLanguage") ?? "system") ?? .system
        UserDefaults.standard.set(language.rawValue, forKey: "preferredLanguage")
    }

    func applyTheme() {
        NSApp.appearance = theme.appearance
        NSApp.windows.forEach { $0.appearance = theme.appearance }
    }
}

extension Notification.Name {
    static let preViewerLanguageDidChange = Notification.Name("PreViewerLanguageDidChange")
}
