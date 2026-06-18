import AppKit

// Entry point. Programmatic — no nib, no storyboard. Keeps cold-launch minimal.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
