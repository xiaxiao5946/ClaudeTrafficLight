import SwiftUI
import AppKit

// ═══════════════════════════════════════════════════════════════════════
//  ClaudeTrafficLight — NSStatusItem (menu bar) + NSPopover + floating window
// ═══════════════════════════════════════════════════════════════════════

let sharedMonitor = SessionMonitor()

@main
struct ClaudeTrafficLightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

// ═══════════════════════════════════════════════════════════════════════
//  AppDelegate — owns NSStatusItem, NSPopover, and floating NSWindow
// ═══════════════════════════════════════════════════════════════════════

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var floatingWindow: NSWindow?
    private var monitorCancellable: AnyObject?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("ClaudeTrafficLight running")

        buildStatusItem()
        buildPopover()
        buildFloatingWindow()

        // Show floating window on launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.showFloatingWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showFloatingWindow()
        return true
    }

    // MARK: - Status Item (menu bar icon)

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = ""
        statusItem.button?.imagePosition = .imageOnly

        drawStatusIcon()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)

        // Observe session changes to redraw icon
        monitorCancellable = NotificationCenter.default.addObserver(
            forName: .CTLSessionsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.drawStatusIcon()
        }
    }

    private func drawStatusIcon() {
        let button = statusItem.button
        let on = sharedMonitor.sessions.filter { $0.isActive }
        let hasErr = on.contains { $0.status == .error }
        let hasThink = on.contains { $0.status == .thinking || $0.status == .blocked }
        let hasWork = on.contains { $0.status == .working || $0.status == .idle }

        let size = NSSize(width: 30, height: 18)
        let image = NSImage(size: size)
        image.isTemplate = false

        image.lockFocus()
        let dotR: CGFloat = 5
        let centers = [NSPoint(x: 6, y: 9), NSPoint(x: 15, y: 9), NSPoint(x: 24, y: 9)]

        // Use bright, saturated colors so the icon is visible on any menu bar
        let onColors: [NSColor] = [
            NSColor(red: 1.0, green: 0.15, blue: 0.15, alpha: 1.0),   // bright red
            NSColor(red: 1.0, green: 0.80, blue: 0.00, alpha: 1.0),   // amber/yellow
            NSColor(red: 0.15, green: 0.85, blue: 0.25, alpha: 1.0),  // bright green
        ]
        let offColor = NSColor.systemGray.withAlphaComponent(0.35)

        for (i, center) in centers.enumerated() {
            let path = NSBezierPath(
                ovalIn: NSRect(x: center.x - dotR / 2, y: center.y - dotR / 2,
                               width: dotR, height: dotR)
            )
            let on = (i == 0 && hasErr) || (i == 1 && hasThink) || (i == 2 && hasWork)
            (on ? onColors[i] : offColor).setFill()
            path.fill()
        }

        image.unlockFocus()
        button?.image = image
    }

    @objc private func statusItemClicked() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.close()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Popover

    private func buildPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 300, height: 360)
        popover.contentViewController = NSHostingController(
            rootView: PopoverContentView(monitor: sharedMonitor, onShowFloating: { [weak self] in
                self?.popover.close()
                self?.showFloatingWindow()
            })
        )
    }

    // MARK: - Floating window

    private func buildFloatingWindow() {
        let content = FloatingWindowContent(
            monitor: sharedMonitor,
            onToggleMode: { [weak self] in self?.switchToMenuBarOnly() }
        )
        let hosting = NSHostingView(rootView: content)
        hosting.frame.size = hosting.fittingSize

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Traffic Light"
        window.titlebarAppearsTransparent = true
        window.center()
        window.setFrameAutosaveName("ClaudeTrafficLightFloating")
        window.contentView = hosting
        window.isReleasedWhenClosed = false

        floatingWindow = window
    }

    func showFloatingWindow() {
        if NSApp.activationPolicy() == .accessory {
            NSApp.setActivationPolicy(.regular)
        }
        floatingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hideFloatingWindow() {
        floatingWindow?.orderOut(nil)
    }

    func switchToMenuBarOnly() {
        hideFloatingWindow()
        NSApp.setActivationPolicy(.accessory)
    }
}

// ═══════════════════════════════════════════════════════════════════════
//  Notification for session changes (so AppDelegate can redraw icon)
// ═══════════════════════════════════════════════════════════════════════

extension Notification.Name {
    static let CTLSessionsChanged = Notification.Name("CTLSessionsChanged")
}

// ═══════════════════════════════════════════════════════════════════════
//  Popover Content (displayed when clicking the menu bar icon)
// ═══════════════════════════════════════════════════════════════════════

struct PopoverContentView: View {
    @ObservedObject var monitor: SessionMonitor
    var onShowFloating: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            sessionContent
            Divider()
            footer
        }
        .frame(width: 300, height: 360)
    }

    private var header: some View {
        HStack(spacing: 8) {
            TrafficLightView(monitor: monitor, size: 14, spacing: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text("Claude Traffic Light")
                    .font(.system(size: 12, weight: .bold))
                let activeCount = monitor.sessions.filter { $0.isActive }.count
                Text("\(activeCount) active / \(monitor.sessions.count) total")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { monitor.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var sessionContent: some View {
        Group {
            if monitor.sessions.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("No sessions found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(monitor.sessions) { session in
                            SessionCardView(session: session)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Open Floating Window") {
                onShowFloating()
            }
            .font(.system(size: 10))

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// ═══════════════════════════════════════════════════════════════════════
//  Floating Window Content
// ═══════════════════════════════════════════════════════════════════════

struct FloatingWindowContent: View {
    @ObservedObject var monitor: SessionMonitor
    var onToggleMode: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            floatingHeader
            Divider()
            SessionListView(monitor: monitor)
            Divider()
            floatingFooter
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var floatingHeader: some View {
        HStack(spacing: 10) {
            TrafficLightView(monitor: monitor, size: 18, spacing: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Traffic Light")
                    .font(.system(size: 14, weight: .bold))
                let activeCount = monitor.sessions.filter { $0.isActive }.count
                Text("\(activeCount) active / \(monitor.sessions.count) total")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { monitor.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var floatingFooter: some View {
        HStack(spacing: 12) {
            Text("Auto-refresh 2s")
                .font(.system(size: 9))
                .foregroundColor(.secondary)

            Spacer()

            Button("Menu Bar Only") {
                onToggleMode()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// ═══════════════════════════════════════════════════════════════════════
//  Shared Components
// ═══════════════════════════════════════════════════════════════════════

struct TrafficLightView: View {
    @ObservedObject var monitor: SessionMonitor
    var size: CGFloat = 18
    var spacing: CGFloat = 4

    var body: some View {
        let active = monitor.sessions.filter { $0.isActive }
        let hasError = active.contains { $0.status == .error }
        let hasThinking = active.contains { $0.status == .thinking || $0.status == .blocked }
        let hasWorking = active.contains { $0.status == .working || $0.status == .idle }

        VStack(spacing: spacing) {
            Circle()
                .fill(hasError ? Color.red : Color.red.opacity(0.15))
                .frame(width: size, height: size)
                .shadow(color: hasError ? .red.opacity(0.6) : .clear, radius: 6)

            Circle()
                .fill(hasThinking ? Color.yellow : Color.yellow.opacity(0.15))
                .frame(width: size, height: size)
                .shadow(color: hasThinking ? .yellow.opacity(0.6) : .clear, radius: 6)

            Circle()
                .fill(hasWorking ? Color.green : Color.green.opacity(0.15))
                .frame(width: size, height: size)
                .shadow(color: hasWorking ? .green.opacity(0.6) : .clear, radius: 6)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: size * 0.65)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.65)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}

struct SessionListView: View {
    @ObservedObject var monitor: SessionMonitor

    var body: some View {
        if monitor.sessions.isEmpty {
            Spacer()
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.regular)
                Text("Loading sessions...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(monitor.sessions) { session in
                        SessionCardView(session: session)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
    }
}

struct SessionCardView: View {
    let session: SessionInfo

    private var statusColor: Color {
        switch session.status {
        case .idle: return .green
        case .thinking: return .yellow
        case .working: return .green
        case .blocked: return .yellow
        case .error: return .red
        case .stopped: return .gray
        }
    }

    private var miniLight: some View {
        VStack(spacing: 2) {
            Circle().fill(session.status == .error ? Color.red : Color.red.opacity(0.15))
                .frame(width: 8, height: 8)
            Circle().fill((session.status == .thinking || session.status == .blocked) ? Color.yellow : Color.yellow.opacity(0.15))
                .frame(width: 8, height: 8)
            Circle().fill((session.status == .working || session.status == .idle) ? Color.green : Color.green.opacity(0.15))
                .frame(width: 8, height: 8)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var sessionInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.displayTitle)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            let taskText = session.currentTask.isEmpty ? "" : " · \(session.currentTask)"
            Text(session.status.displayLabel + taskText)
                .font(.system(size: 10))
                .foregroundColor(statusColor)
                .lineLimit(1)
        }
    }

    private var sessionMeta: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if session.isActive {
                HStack(spacing: 2) {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                    Text("active")
                        .font(.system(size: 9))
                        .foregroundColor(.green)
                }
            } else {
                Text("offline")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            Text(session.elapsedText)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            miniLight
            sessionInfo
            Spacer()
            sessionMeta
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}
