import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuBarController = MenuBarController()

    func configure(viewModel: AppViewModel) {
        menuBarController.configure(viewModel: viewModel)
        viewModel.onMenuStateChange = { [weak self] in
            self?.menuBarController.rebuildMenu()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = NSImage(size: NSSize(width: 512, height: 512))
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct GMNUsageMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup("GMN Usage Monitor") {
            RootView()
                .environmentObject(viewModel)
                .frame(minWidth: 720, minHeight: 560)
                .task {
                    appDelegate.configure(viewModel: viewModel)
                    await viewModel.start()
                }
        }
        .defaultSize(width: 860, height: 640)
    }
}
