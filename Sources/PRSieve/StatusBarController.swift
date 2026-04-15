import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var eventMonitor: Any?
    private let viewModel: DashboardViewModel

    var onOpenSettings: (() -> Void)?

    init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        popover.contentSize = NSSize(width: 420, height: 580)
        popover.behavior = .transient
        popover.animates = true

        super.init()

        let content = MenuBarPRListView(viewModel: viewModel, onOpenSettings: { [weak self] in
            self?.popover.performClose(nil)
            self?.onOpenSettings?()
        })
        popover.contentViewController = NSHostingController(rootView: content)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateIcon()
    }

    private func updateIcon() {
        let hasPriority = withObservationTracking {
            viewModel.priority.contains { $0.buildStatus == .passed }
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateIcon() }
        }

        guard let button = statusItem.button else { return }

        let symbolName = hasPriority
            ? "line.3.horizontal.decrease.circle.fill"
            : "line.3.horizontal.decrease.circle"

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "PRSieve")
        if hasPriority {
            let config = NSImage.SymbolConfiguration(paletteColors: [.white, .systemOrange])
            button.image = image?.withSymbolConfiguration(config)
        } else {
            button.image = image
        }
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu(sender)
        } else {
            togglePopover(sender)
        }
    }

    private func showContextMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshAction), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(settingsAction), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit PRSieve", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Reset menu so left-click still shows the popover
        statusItem.menu = nil
    }

    @objc private func refreshAction() {
        Task { await viewModel.refresh() }
    }

    @objc private func settingsAction() {
        onOpenSettings?()
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            stopEventMonitor()
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            startEventMonitor()
        }
    }

    private func startEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.popover.performClose(nil)
            self.stopEventMonitor()
        }
    }

    private func stopEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
    }
}
