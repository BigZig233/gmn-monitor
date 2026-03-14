import AppKit
import Foundation

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private weak var viewModel: AppViewModel?

    func configure(viewModel: AppViewModel) {
        self.viewModel = viewModel
        setupStatusButton()
        rebuildMenu()
    }

    func rebuildMenu() {
        guard let viewModel else { return }

        updateStatusButtonTitle(using: viewModel)

        let menu = NSMenu()

        let summaryItem = NSMenuItem(title: viewModel.menuStatusSummary, action: nil, keyEquivalent: "")
        summaryItem.isEnabled = false
        menu.addItem(summaryItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "打开详细页", action: #selector(openDetailPage), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "立即刷新", action: #selector(refreshNow), keyEquivalent: "r"))

        let subscriptionsItem = NSMenuItem(title: "选择订阅", action: nil, keyEquivalent: "")
        subscriptionsItem.submenu = makeSubscriptionsMenu(using: viewModel)
        menu.addItem(subscriptionsItem)

        menu.addItem(.separator())

        let logoutItem = NSMenuItem(title: "退出登录", action: #selector(logout), keyEquivalent: "")
        logoutItem.isEnabled = viewModel.authStore.isAuthenticated
        menu.addItem(logoutItem)

        menu.addItem(NSMenuItem(title: "清除保存状态", action: #selector(clearSavedState), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出应用", action: #selector(quitApp), keyEquivalent: "q"))

        menu.delegate = self
        statusItem.menu = menu
        statusItem.menu?.items.forEach { $0.target = self }
    }

    private func setupStatusButton() {
        guard let button = statusItem.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: "GMN Usage Monitor")?.withSymbolConfiguration(config)
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(showMenu(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func updateStatusButtonTitle(using viewModel: AppViewModel) {
        statusItem.button?.title = ""
        statusItem.button?.toolTip = viewModel.menuStatusSummary
    }

    private func makeSubscriptionsMenu(using viewModel: AppViewModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        guard viewModel.authStore.isAuthenticated else {
            let item = NSMenuItem(title: "请先登录后再选择订阅", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return menu
        }

        let subscriptions = viewModel.subscriptionStore.subscriptions
        guard !subscriptions.isEmpty else {
            let item = NSMenuItem(title: "暂无可选订阅，请打开详细页刷新", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return menu
        }

        for subscription in subscriptions {
            let item = NSMenuItem(
                title: subscriptionTitle(for: subscription),
                action: #selector(selectSubscription(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = subscription.id as NSNumber
            item.state = subscription.id == viewModel.settingsStore.selectedSubscriptionID ? .on : .off
            item.isEnabled = true
            menu.addItem(item)
        }

        return menu
    }

    private func subscriptionTitle(for subscription: Subscription) -> String {
        if let percent = subscription.usage.daily?.percent {
            return "\(subscription.groupName) (\(percent.formatted(.number.precision(.fractionLength(1))))%)"
        }

        if subscription.unlimited {
            return "\(subscription.groupName) (无限额度)"
        }

        return subscription.groupName
    }

    @objc private func showMenu(_ sender: AnyObject?) {
        rebuildMenu()
        statusItem.button?.performClick(nil)
    }

    @objc private func openDetailPage() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
            return
        }

        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    @objc private func refreshNow() {
        guard let viewModel else { return }
        Task { @MainActor in
            await viewModel.refreshNow()
            self.rebuildMenu()
        }
    }

    @objc private func logout() {
        guard let viewModel else { return }
        Task { @MainActor in
            await viewModel.logout()
            self.rebuildMenu()
        }
    }

    @objc private func clearSavedState() {
        guard let viewModel else { return }
        viewModel.clearSavedState()
        rebuildMenu()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func selectSubscription(_ sender: NSMenuItem) {
        guard let viewModel,
              let selectedID = (sender.representedObject as? NSNumber)?.intValue,
              let subscription = viewModel.subscriptionStore.subscriptions.first(where: { $0.id == selectedID })
        else {
            return
        }

        viewModel.selectSubscription(subscription)
        rebuildMenu()
    }
}

extension MenuBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }
}
