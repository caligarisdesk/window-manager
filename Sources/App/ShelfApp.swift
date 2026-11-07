import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@main
struct ShelfMain {
    static func main() {
        if CommandLine.arguments.contains("--dump") { Dump.run(); return }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var store: DeckStore!
    private var hotKey: EventHotKeyRef?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = DeckStore()
        buildMenu()
        buildWindow()
        buildStatusItem()
        registerHotKey()
        showDashboard()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) { store.refresh() }

    // Closing the window just hides it so the hotkey can bring it back.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    @objc func showDashboard() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        store.refresh()
    }

    @objc private func toggleDashboard() {
        if NSApp.isActive && window.isVisible { NSApp.hide(nil) } else { showDashboard() }
    }

    private func buildWindow() {
        let frame = (NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1400, height: 900)).insetBy(dx: 40, dy: 30)
        window = NSWindow(contentRect: frame,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Shelf"
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 520, height: 400)
        window.delegate = self
        window.setFrameAutosaveName("ShelfMain")
        window.contentView = NSHostingView(rootView: DashboardView().environmentObject(store))
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.image = NSImage(systemSymbolName: "books.vertical.fill", accessibilityDescription: "Shelf")
            b.imagePosition = .imageLeading
            b.target = self
            b.action = #selector(toggleDashboard)
        }
        store.$sessions
            .map { $0.filter { $0.status == .needsYou }.count }
            .removeDuplicates()
            .sink { [weak self] n in self?.statusItem.button?.title = n > 0 ? " \(n)" : "" }
            .store(in: &cancellables)
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Show Dashboard  ⌥⌘T", action: #selector(showDashboard), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Shelf", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Shelf", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let winItem = NSMenuItem()
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winItem.submenu = win
        main.addItem(winItem)
        NSApp.mainMenu = main
    }

    // MARK: - Global hotkey (⌥⌘T) via Carbon; needs no Accessibility permission.

    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let me = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.showDashboard() }
            return noErr
        }, 1, &spec, selfPtr, nil)
        let id = EventHotKeyID(signature: OSType(0x54444B31), id: 1) // 'TDK1'
        RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(cmdKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }
}
