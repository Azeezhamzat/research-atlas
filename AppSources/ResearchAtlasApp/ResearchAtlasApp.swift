import AppKit
import SwiftUI

@MainActor
private final class ResearchAtlasAppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var fallbackWindow: NSWindow?

    override init() {
        super.init()
        DispatchQueue.main.async { [weak self] in
            self?.showOrCreateMainWindow()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        bringResearchWindowsForward()

        // SwiftUI may finish constructing the WindowGroup after this delegate callback. If
        // restoration produces no main window, create the same RootView through AppKit so a
        // healthy process can never remain open with no usable interface.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showOrCreateMainWindow()
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showOrCreateMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdownManagedLocalAIEngine()
    }

    private func bringResearchWindowsForward() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func showOrCreateMainWindow() {
        if let existingWindow = NSApp.windows.first(where: { window in
            !(window is NSPanel) && window.canBecomeMain
        }) {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = RootView()
            .environmentObject(model)
            .frame(minWidth: 980, minHeight: 680)
            .task { self.model.bootstrap() }
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1320, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Research Atlas"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.center()
        fallbackWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct ResearchAtlasApp: App {
    @NSApplicationDelegateAdaptor(ResearchAtlasAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Research Atlas") {
            RootView()
                .environmentObject(appDelegate.model)
                .frame(minWidth: 980, minHeight: 680)
                .task { appDelegate.model.bootstrap() }
        }
        .defaultSize(width: 1320, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Local PDF…") { appDelegate.model.chooseAndAddPDF() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Search Research Atlas") { appDelegate.model.selectedSection = .search }
                    .keyboardShortcut("f", modifiers: [.command])
            }
            CommandGroup(replacing: .help) {
                Button("Research Atlas Learning Center") { appDelegate.model.selectedSection = .learning }
                    .keyboardShortcut("?", modifiers: [.command])
            }
        }
        Settings {
            SettingsView()
                .environmentObject(appDelegate.model)
                .frame(width: 620, height: 470)
        }
    }
}
