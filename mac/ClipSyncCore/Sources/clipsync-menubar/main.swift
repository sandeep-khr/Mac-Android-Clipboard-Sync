import AppKit

// Menu-bar-only app: `.accessory` hides the Dock icon and main menu, the
// runtime equivalent of Info.plist `LSUIElement = YES`. No .xcodeproj needed.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
