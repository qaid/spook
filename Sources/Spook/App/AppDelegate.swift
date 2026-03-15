import AppKit
import SwiftUI

@MainActor
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
        detailPanel?.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
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
        Task {
            await networkMonitor?.startMonitoring()
        }
    }

    private func updateMenuBarDisplay(download: Int64, upload: Int64) {
        let downloadStr = SpeedFormatter.format(download)
        let uploadStr = SpeedFormatter.format(upload)
        statusItem?.button?.title = "\u{2193} \(downloadStr)  \u{2191} \(uploadStr)"
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

                let panelWidth: CGFloat = 400
                let panelHeight: CGFloat = 620

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
            window.styleMask = NSWindow.StyleMask([.titled, .closable, .miniaturizable])
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
    var onOpenSettings: (() -> Void)?

    init(monitor: NetworkMonitor) {
        self.monitor = monitor

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 620),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.titlebarSeparatorStyle = .none
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true

        setupContent()
    }

    private func setupContent() {
        let contentView = DetailPanelContentView(
            monitor: monitor,
            onPinnedChanged: { [weak self] pinned in
                self?.isPinned = pinned
                // Show/hide in Cmd+Tab app switcher based on pin state
                NSApp.setActivationPolicy(pinned ? .regular : .accessory)
            },
            onClose: { [weak self] in
                self?.close()
            },
            onOpenSettings: { [weak self] in
                self?.onOpenSettings?()
            }
        )

        self.contentViewController = NSHostingController(rootView: contentView)
    }
}

// MARK: - Detail Panel Content View

struct DetailPanelContentView: View {
    var monitor: NetworkMonitor
    var onPinnedChanged: (Bool) -> Void
    var onClose: () -> Void
    var onOpenSettings: () -> Void
    @State private var isPinned: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with pin/close buttons
            HStack {
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        isPinned.toggle()
                    }
                    onPinnedChanged(isPinned)
                }) {
                    PinView(isPinned: isPinned)
                }
                .buttonStyle(.plain)
                .help(isPinned ? "Unpin window" : "Pin window to keep it visible")

                Spacer()

                Menu {
                    Button(action: onOpenSettings) {
                        Label("Settings...", systemImage: "gearshape")
                    }
                    .keyboardShortcut(",", modifiers: .command)

                    Divider()

                    Button(action: { NSApp.terminate(nil) }) {
                        Label("Quit Spook", systemImage: "power")
                    }
                    .keyboardShortcut("q", modifiers: .command)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(SpookFont.iconMedium)
                        .foregroundColor(.spookTextSecondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 24, height: 24)
                .help("Menu")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(SpookFont.caption2Semibold)
                        .foregroundColor(.spookTextSecondary)
                }
                .buttonStyle(.plain)
                .circularButton()
                .help("Close")
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)

            // Main content
            DetailView(monitor: monitor)
        }
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.panel))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
    }
}

// MARK: - Pin View

struct PinView: View {
    let isPinned: Bool

    var body: some View {
        ZStack {
            // Pin shadow (only when pinned — simulates pin head elevated above surface)
            if isPinned {
                Ellipse()
                    .fill(Color.black.opacity(0.18))
                    .frame(width: 10, height: 4)
                    .offset(x: 1, y: 8)
                    .blur(radius: 1.5)
            }

            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(SpookFont.icon)
                .foregroundColor(isPinned ? .accentColor : .spookTextSecondary)
                .rotationEffect(.degrees(isPinned ? 5 : 0))
                .scaleEffect(isPinned ? 1.1 : 1.0)
                .offset(y: isPinned ? 2 : 0)
                .mask(
                    Rectangle()
                        .frame(height: isPinned ? 18 : 24)
                        .frame(width: 24)
                        .offset(y: isPinned ? -3 : 0)
                )
        }
        .frame(width: 24, height: 24)
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
