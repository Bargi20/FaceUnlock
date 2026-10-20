import Foundation

public enum AppLanguage: String {
    case system
}

/// English source strings; translations live in Resources/<lang>.lproj/Localizable.strings
/// and follow the Mac's language.
enum L10n {
    private static let strings: [String: String] = [
        "failure.noEnrollment": "No face enrolled",
        "failure.accessibility": "Accessibility permission needed",
        "failure.noPassword": "No password saved",
        "failure.camera": "Camera unavailable: %@",
        "failure.giveUp": "Recognition failed after %d attempts",
        "failure.couldNotType": "Couldn't type the password: %@",
        "step.center": "Look at the screen",
        "step.left": "Turn your head left",
        "step.right": "Turn your head right",
        "step.tiltLeft": "Tilt your head left",
        "step.tiltRight": "Tilt your head right",
    ]

    static func t(_ key: String) -> String { tr(strings[key] ?? key) }
}

/// Looks up an English source string in the app's translations.
func tr(_ english: String) -> String {
    NSLocalizedString(english, bundle: .main, comment: "")
}
