import Foundation

/// Lightweight UserDefaults-backed state so the app reopens where you left off.
enum Persistence {
    private static let d = UserDefaults.standard

    static var lastFolder: URL? {
        get { d.url(forKey: "lastFolder") }
        set { d.set(newValue, forKey: "lastFolder") }
    }

    static var lastNote: URL? {
        get { d.url(forKey: "lastNote") }
        set { d.set(newValue, forKey: "lastNote") }
    }

    /// Whether the first-run Welcome folder has been seeded.
    static var didOnboard: Bool {
        get { d.bool(forKey: "didOnboard") }
        set { d.set(newValue, forKey: "didOnboard") }
    }
}
