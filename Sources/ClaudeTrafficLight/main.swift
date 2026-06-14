import SwiftUI
import AppKit

// ═══════════════════════════════════════════════════════════════════════
//  ClaudeTrafficLight — Monitor + Alert
// ═══════════════════════════════════════════════════════════════════════

let sharedMonitor = SessionMonitor()

// ═══════════════════════════════════════════════════════════════════════
//  AppDelegate
// ═══════════════════════════════════════════════════════════════════════

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var floatingWindow: NSWindow?
    private var monitorObs: NSObjectProtocol?

    // Flash animation
    private var flashTimer: Timer?
    private var flashRounds: Int = 0
    private var flashMask: UInt8 = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("ClaudeTrafficLight running")

        NSApp.setActivationPolicy(.accessory)

        buildStatusItem()
        buildPopover()
        buildFloatingWindow()

        // Listen for session changes
        monitorObs = NotificationCenter.default.addObserver(
            forName: .CTLSessionsChanged, object: nil, queue: .main
        ) { [weak self] n in
            self?.handleSessionChanges(n.userInfo?["changes"] as? [(SessionInfo, SessionStatus)] ?? [])
            self?.redrawIcon()
        }

        // Delayed window show
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showFloatingWindow()
        }

        NSLog("[CTL] launched — statusItem=\(statusItem != nil ? "OK" : "FAIL")")
    }

    // MARK: - Status Item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else {
            NSLog("[CTL] ❌ button nil"); return
        }
        button.image = TrafficLightIcon.draw(state: .init(redOn: false, yellowOn: false, greenOn: false))
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(statusClicked)
        if #available(macOS 14.0, *) { statusItem.isVisible = true }
    }

    private func redrawIcon() {
        let s = sharedMonitor.activeStatusSummary
        let state = TrafficLightIcon.State(
            redOn: s.hasError,
            yellowOn: s.hasBlocked || s.hasThinking,
            greenOn: s.hasWorking,
            flashMask: flashMask
        )
        statusItem.button?.image = TrafficLightIcon.draw(state: state)
    }

    @objc private func statusClicked() {
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
        popover.contentSize = NSSize(width: 320, height: 440)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(monitor: sharedMonitor, onShowFloating: { [weak self] in
                self?.popover.close()
                self?.showFloatingWindow()
            })
        )
    }

    // MARK: - Floating Window

    private func buildFloatingWindow() {
        let content = FloatingWindowView(
            monitor: sharedMonitor,
            onMenuBarOnly: { [weak self] in self?.switchToMenuBarOnly() }
        )
        let hosting = NSHostingView(rootView: content)
        hosting.frame.size = hosting.fittingSize

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 380),
            styleMask: [.closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Claude Traffic Light"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        window.setFrameAutosaveName("CTLFloating")
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

    func switchToMenuBarOnly() {
        floatingWindow?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Flash Animation

    private func startFlash(_ mask: UInt8, rounds: Int = 3) {
        flashTimer?.invalidate()
        flashMask = mask
        flashRounds = rounds * 2  // on + off = 1 round
        redrawIcon()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.flashRounds -= 1
            if self.flashRounds <= 0 {
                t.invalidate()
                self.flashMask = 0
            } else {
                // Toggle flash: even = off, odd = on
                self.flashMask = (self.flashRounds % 2 == 0) ? 0 : mask
            }
            self.redrawIcon()
        }
    }

    // MARK: - Notifications (NSUserNotification — no permission required)

    private func notify(_ title: String, body: String, sound: Bool = true) {
        let note = NSUserNotification()
        note.title = title
        note.informativeText = body
        note.soundName = sound ? NSUserNotificationDefaultSoundName : nil
        NSUserNotificationCenter.default.deliver(note)
        NSLog("[CTL] notified: \(title)")
    }

    // MARK: - Session change handler

    private func handleSessionChanges(_ changes: [(SessionInfo, SessionStatus)]) {
        for (session, oldStatus) in changes {
            let isBusy = { (s: SessionStatus) in s == .thinking || s == .working || s == .blocked }
            let newIsBusy = isBusy(session.status)
            let oldIsBusy = isBusy(oldStatus)

            NSLog("[CTL] change: 「\(session.displayTitle)」 \(oldStatus.displayLabel) → \(session.status.displayLabel) active=\(session.isActive)")

            switch session.status {
            case .stopped where oldStatus != .stopped:
                // Session process died
                startFlash(4, rounds: 2)
                notify("Claude → 会话结束", body: "「\(session.displayTitle)」已退出", sound: true)

            case .blocked where session.isActive:
                startFlash(2, rounds: 4)
                notify("Claude → 等待确认", body: "「\(session.displayTitle)」需要你的操作")

            case .error where session.isActive:
                startFlash(1, rounds: 5)
                notify("Claude → 出错", body: "「\(session.displayTitle)」")

            case .idle where oldIsBusy && session.isActive:
                startFlash(4, rounds: 3)
                notify("Claude → 完成", body: "「\(session.displayTitle)」", sound: true)

            case .thinking, .working:
                guard session.isActive else { continue }
                if !oldIsBusy {
                    startFlash(2, rounds: 2)
                    notify("Claude → 执行中", body: "「\(session.displayTitle)」\(session.currentTask)", sound: false)
                }

            default: break
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
//  Floating Window View (separate struct for proper @State management)
// ═══════════════════════════════════════════════════════════════════════

struct FloatingWindowView: View {
    @ObservedObject var monitor: SessionMonitor
    var onMenuBarOnly: () -> Void
    @State private var alwaysOnTop = false

    var body: some View {
        VStack(spacing: 0) {
            // ── Drag handle (no title bar) ──
            HStack {
                Spacer()
                Button(action: { onMenuBarOnly() }) {
                    Image(systemName: "minus").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain).foregroundColor(.secondary.opacity(0.5))
                .help("Minimize to menu bar")
            }
            .padding(.horizontal, 8).padding(.top, 6)

            // ── Session cards ──
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(monitor.filteredSessions) { session in
                        CompactSessionCard(session: session)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }

            Divider()

            // ── Bottom bar ──
            HStack(spacing: 8) {
                Button(action: { monitor.refresh() }) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11))
                }
                .buttonStyle(.plain).foregroundColor(.secondary)
                .help("Refresh")

                Button(action: {
                    alwaysOnTop.toggle()
                }) {
                    Image(systemName: alwaysOnTop ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(alwaysOnTop ? .orange : .secondary)
                .help(alwaysOnTop ? "Unpin from top" : "Always on top")

                Spacer()

                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .frame(minWidth: 260, maxWidth: 320, minHeight: 200, maxHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { syncWindowLevel() }
        .onChange(of: alwaysOnTop) { _ in syncWindowLevel() }
    }

    private func syncWindowLevel() {
        guard let win = NSApp.windows.first(where: { $0.title == "Claude Traffic Light" }) else { return }
        win.level = alwaysOnTop ? .floating : .normal
    }
}

// MARK: - Compact session card

struct CompactSessionCard: View {
    let session: SessionInfo

    var body: some View {
        HStack(spacing: 10) {
            // ── Big traffic light ──
            VStack(spacing: 3) {
                Circle()
                    .fill(session.status == .error ? Color.red : Color.red.opacity(0.12))
                    .frame(width: 14, height: 14)
                    .shadow(color: session.status == .error ? .red.opacity(0.5) : .clear, radius: 4)
                Circle()
                    .fill((session.status == .thinking || session.status == .blocked) ? Color.yellow : Color.yellow.opacity(0.12))
                    .frame(width: 14, height: 14)
                    .shadow(color: (session.status == .thinking || session.status == .blocked) ? .yellow.opacity(0.5) : .clear, radius: 4)
                Circle()
                    .fill((session.status == .working || session.status == .idle) ? Color.green : Color.green.opacity(0.12))
                    .frame(width: 14, height: 14)
                    .shadow(color: (session.status == .working || session.status == .idle) ? .green.opacity(0.5) : .clear, radius: 4)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            // ── Info ──
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if !session.currentTask.isEmpty {
                    Text(session.currentTask)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // ── Status badge ──
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 3) {
                    Circle().fill(statusDot).frame(width: 5, height: 5)
                    Text(shortLabel)
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(statusColor)
                Text(session.elapsedText)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private var statusDot: Color {
        switch session.status {
        case .idle, .working: return .green
        case .thinking, .blocked: return .yellow
        case .error: return .red
        case .stopped: return .gray
        }
    }

    private var shortLabel: String {
        switch session.status {
        case .idle: return "idle"
        case .thinking: return "thinking"
        case .working: return "running"
        case .blocked: return "blocked"
        case .error: return "error"
        case .stopped: return "done"
        }
    }

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
}

private func statusCardColor(_ s: SessionStatus) -> Color {
    switch s {
    case .idle: return .green
    case .thinking: return .yellow
    case .working: return .green
    case .blocked: return .yellow
    case .error: return .red
    case .stopped: return .gray
    }
}

// ═══════════════════════════════════════════════════════════════════════
//  Entry Point
// ═══════════════════════════════════════════════════════════════════════

@main
struct MainApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
