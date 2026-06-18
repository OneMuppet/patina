import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSToolbarDelegate {

    private var window: NSWindow!
    private var workspace: WorkspaceController!

    // MARK: Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        restoreState()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window.makeKeyAndOrderFront(nil) }
        return true
    }

    func applicationDidResignActive(_ notification: Notification) {
        workspace?.flushEditor()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        workspace?.flushEditor()
        return .terminateNow
    }

    // Open a folder or file from Finder / `open` / drag-to-dock.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if workspace == nil { buildWindow() }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue {
            workspace.setFolder(url)
        } else {
            workspace.setFolder(url.deletingLastPathComponent(), select: url)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Window

    private func buildWindow() {
        guard window == nil else { return }
        workspace = WorkspaceController()

        let win = NSWindow(contentViewController: workspace)
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.toolbarStyle = .unified
        win.setContentSize(NSSize(width: 960, height: 720))
        win.minSize = NSSize(width: 660, height: 420)
        win.title = "Patina"
        win.setFrameAutosaveName("PatinaMain")

        let toolbar = NSToolbar(identifier: "PatinaToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        win.toolbar = toolbar

        window = win
    }

    private func restoreState() {
        guard let folder = Persistence.lastFolder,
              FileManager.default.fileExists(atPath: folder.path) else { return }
        let note = Persistence.lastNote.flatMap {
            FileManager.default.fileExists(atPath: $0.path) ? $0 : nil
        }
        workspace.setFolder(folder, select: note)
    }

    // MARK: Toolbar

    private static let newNoteID = NSToolbarItem.Identifier("newNote")
    private static let previewID = NSToolbarItem.Identifier("togglePreview")

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, Self.newNoteID, .flexibleSpace, Self.previewID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.space]
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case Self.newNoteID:
            return makeItem(identifier, symbol: "square.and.pencil",
                            label: "New Note", action: #selector(WorkspaceController.newNote(_:)))
        case Self.previewID:
            return makeItem(identifier, symbol: "sidebar.right",
                            label: "Preview", action: #selector(WorkspaceController.togglePreview(_:)))
        default:
            return nil
        }
    }

    private func makeItem(_ id: NSToolbarItem.Identifier, symbol: String,
                          label: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.target = nil   // route through the responder chain to WorkspaceController
        item.action = action
        item.isBordered = true
        return item
    }

    // MARK: Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appItem = NSMenuItem(); mainMenu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Patina", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Patina", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Patina", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File menu
        let fileItem = NSMenuItem(); mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File"); fileItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "New Note", action: #selector(WorkspaceController.newNote(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Quick Open…", action: #selector(WorkspaceController.showPalette(_:)), keyEquivalent: "k")
        let openFolder = fileMenu.addItem(withTitle: "Open Notes Folder…", action: #selector(WorkspaceController.openFolder(_:)), keyEquivalent: "o")
        openFolder.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Move Note to Trash", action: #selector(WorkspaceController.deleteNote(_:)), keyEquivalent: "\u{8}") // ⌫
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        // Edit menu
        let editItem = NSMenuItem(); mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit"); editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        let findInNote = editMenu.addItem(withTitle: "Find in Note", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        findInNote.tag = 1 // NSFindPanelAction.showFindPanel
        let searchNotes = editMenu.addItem(withTitle: "Search Notes", action: #selector(WorkspaceController.searchNotes(_:)), keyEquivalent: "f")
        searchNotes.keyEquivalentModifierMask = [.command, .option]

        // Format menu
        let formatItem = NSMenuItem(); mainMenu.addItem(formatItem)
        let formatMenu = NSMenu(title: "Format"); formatItem.submenu = formatMenu
        formatMenu.addItem(withTitle: "Bold", action: #selector(EditorViewController.toggleBold(_:)), keyEquivalent: "b")
        formatMenu.addItem(withTitle: "Italic", action: #selector(EditorViewController.toggleItalic(_:)), keyEquivalent: "i")
        let code = formatMenu.addItem(withTitle: "Inline Code", action: #selector(EditorViewController.toggleInlineCode(_:)), keyEquivalent: "c")
        code.keyEquivalentModifierMask = [.command, .option]
        let link = formatMenu.addItem(withTitle: "Insert Link", action: #selector(EditorViewController.insertLink(_:)), keyEquivalent: "k")
        link.keyEquivalentModifierMask = [.command, .shift]
        formatMenu.addItem(.separator())
        let heading = formatMenu.addItem(withTitle: "Heading", action: #selector(EditorViewController.toggleHeading(_:)), keyEquivalent: "h")
        heading.keyEquivalentModifierMask = [.command, .option]
        let bullet = formatMenu.addItem(withTitle: "Bullet List", action: #selector(EditorViewController.toggleBulletList(_:)), keyEquivalent: "l")
        bullet.keyEquivalentModifierMask = [.command, .shift]

        // View menu
        let viewItem = NSMenuItem(); mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View"); viewItem.submenu = viewMenu
        let toggleSidebar = viewMenu.addItem(withTitle: "Toggle Sidebar", action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "s")
        toggleSidebar.keyEquivalentModifierMask = [.command, .control]
        let preview = viewMenu.addItem(withTitle: "Toggle Markdown Preview", action: #selector(WorkspaceController.togglePreview(_:)), keyEquivalent: "p")
        preview.keyEquivalentModifierMask = [.command, .shift]

        // Window menu
        let windowItem = NSMenuItem(); mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window"); windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }
}
