import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var detailPanel: DetailPanel?
    private var networkMonitor: NetworkMonitor?
    private var eventMonitor: Any?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        startNetworkMonitoring()
        setupMenuBar()
        setupDetailPanel()
        setupClickOutsideMonitor()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.title = "\u{2193} 0 B/s  \u{2191} 0 B/s"
            button.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(handleClick)
            button.target = self
        }
    }

    private func setupDetailPanel() {
        guard let monitor = networkMonitor else { return }
        detailPanel = DetailPanel(monitor: monitor)
    }

    private func setupClickOutsideMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.detailPanel else { return }

            // Don't close if pinned
            if panel.isPinned { return }

            // Don't close if clicking on the panel itself
            if let window = event.window, window == panel {
                return
            }

            // Don't close if clicking on status item
            if let buttonWindow = self.statusItem?.button?.window,
               let eventWindow = event.window,
               eventWindow == buttonWindow {
                return
            }

            if panel.isVisible {
                panel.close()
            }
        }
    }

    private func startNetworkMonitoring() {
        networkMonitor = NetworkMonitor()
        networkMonitor?.onUpdate = { [weak self] downloadSpeed, uploadSpeed in
            self?.updateMenuBarDisplay(download: downloadSpeed, upload: uploadSpeed)
        }
        networkMonitor?.startMonitoring()
    }

    private func updateMenuBarDisplay(download: Int64, upload: Int64) {
        DispatchQueue.main.async { [weak self] in
            let downloadStr = SpeedFormatter.format(download)
            let uploadStr = SpeedFormatter.format(upload)
            self?.statusItem?.button?.title = "\u{2193} \(downloadStr)  \u{2191} \(uploadStr)"
        }
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            toggleDetailPanel()
        }
    }

    private func toggleDetailPanel() {
        guard let panel = detailPanel, let button = statusItem?.button else { return }

        if panel.isVisible {
            panel.close()
        } else {
            // Position below the menu bar item
            if let buttonWindow = button.window {
                let buttonRect = button.convert(button.bounds, to: nil)
                let screenRect = buttonWindow.convertToScreen(buttonRect)

                let panelWidth: CGFloat = 360
                let panelHeight: CGFloat = 600

                let x = screenRect.midX - panelWidth / 2
                let y = screenRect.minY - panelHeight - 4

                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }

            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "About Spook", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Spook", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = "Spook Settings"
            window.styleMask = NSWindow.StyleMask([.titled, .closable])
            window.center()

            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - Detail Panel

class DetailPanel: NSPanel {
    var isPinned: Bool = false
    private var monitor: NetworkMonitor

    init(monitor: NetworkMonitor) {
        self.monitor = monitor

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true

        setupContent()
    }

    private func setupContent() {
        let contentView = DetailPanelContentView(
            monitor: monitor,
            isPinned: Binding(
                get: { self.isPinned },
                set: { self.isPinned = $0 }
            ),
            onClose: { [weak self] in
                self?.close()
            }
        )

        self.contentViewController = NSHostingController(rootView: contentView)
    }
}

// MARK: - Detail Panel Content View

struct DetailPanelContentView: View {
    var monitor: NetworkMonitor
    @Binding var isPinned: Bool
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header with pin/close buttons
            HStack {
                Button(action: { isPinned.toggle() }) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 12))
                        .foregroundColor(isPinned ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(isPinned ? "Unpin window" : "Pin window to keep it visible")

                Spacer()

                Text("Spook")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))

            Divider()

            // Main content
            DetailView(monitor: monitor)
        }
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Visual Effect View

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
