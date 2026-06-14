import SwiftUI
import AppKit
import UserNotifications

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

    // Notification center
    private let notifCenter = UNUserNotificationCenter.current()
    private var notifGranted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("ClaudeTrafficLight running")

        // Start as accessory — status item + menu bar only
        NSApp.setActivationPolicy(.accessory)

        requestNotifications()
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
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Claude Traffic Light"
        window.titlebarAppearsTransparent = true
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

    // MARK: - Notifications

    private func requestNotifications() {
        notifCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            self.notifGranted = granted
        }
    }

    private func notify(_ title: String, body: String, sound: UNNotificationSound? = .default) {
        guard notifGranted else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let s = sound { content.sound = s }
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        notifCenter.add(req)
    }

    // MARK: - Session change handler

    private func handleSessionChanges(_ changes: [(SessionInfo, SessionStatus)]) {
        for (session, oldStatus) in changes {
            guard session.isActive else { continue }

            let isBusy = { (s: SessionStatus) in s == .thinking || s == .working || s == .blocked }
            let newIsBusy = isBusy(session.status)
            let oldIsBusy = isBusy(oldStatus)
            let isNewSession = oldStatus == .stopped

            NSLog("[CTL] change: 「\(session.displayTitle)」 \(oldStatus.displayLabel) → \(session.status.displayLabel)")

            switch session.status {
            case .blocked:
                startFlash(2, rounds: 4)
                notify("Claude → 等待确认", body: "「\(session.displayTitle)」需要你的操作")

            case .error:
                startFlash(1, rounds: 5)
                notify("Claude → 出错", body: "「\(session.displayTitle)」")

            case .idle where oldIsBusy:
                startFlash(4, rounds: 1)
                notify("Claude → 完成", body: "「\(session.displayTitle)」", sound: nil)

            case .thinking, .working:
                if !oldIsBusy || isNewSession {
                    startFlash(2, rounds: isNewSession ? 2 : 1)
                    notify("Claude → 执行中", body: "「\(session.displayTitle)」开始 \(session.currentTask)", sound: nil)
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
            // ── Session cards with prominent traffic lights ──
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(monitor.filteredSessions) { session in
                        FloatingSessionCard(session: session)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }

            Divider()

            // ── Bottom bar ──
            HStack(spacing: 12) {
                Button(action: { monitor.refresh() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 10))
                        Text("Refresh").font(.system(size: 10))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Toggle("Always on Top", isOn: $alwaysOnTop)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 10))

                Spacer()

                Button("Menu Bar Only") { onMenuBarOnly() }
                    .buttonStyle(.plain).font(.system(size: 10))
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { syncWindowLevel() }
        .onChange(of: alwaysOnTop) { _ in syncWindowLevel() }
    }

    private func syncWindowLevel() {
        guard let window = NSApp.windows.first(where: { $0.title == "Claude Traffic Light" }) else { return }
        window.level = alwaysOnTop ? .floating : .normal
    }
}

// MARK: - Floating session card (prominent traffic light)

struct FloatingSessionCard: View {
    let session: SessionInfo

    var body: some View {
        HStack(spacing: 12) {
            // ── Prominent traffic light ──
            VStack(spacing: 4) {
                Circle()
                    .fill(session.status == .error ? Color.red : Color.red.opacity(0.12))
                    .frame(width: 16, height: 16)
                    .shadow(color: session.status == .error ? .red.opacity(0.6) : .clear, radius: 6)
                Circle()
                    .fill((session.status == .thinking || session.status == .blocked) ? Color.yellow : Color.yellow.opacity(0.12))
                    .frame(width: 16, height: 16)
                    .shadow(color: (session.status == .thinking || session.status == .blocked) ? .yellow.opacity(0.6) : .clear, radius: 6)
                Circle()
                    .fill((session.status == .working || session.status == .idle) ? Color.green : Color.green.opacity(0.12))
                    .frame(width: 16, height: 16)
                    .shadow(color: (session.status == .working || session.status == .idle) ? .green.opacity(0.6) : .clear, radius: 6)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            )

            // ── Session info ──
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(session.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    if session.isActive {
                        Circle().fill(Color.green)
                            .frame(width: 6, height: 6)
                    }
                }

                if !session.currentTask.isEmpty {
                    Text(session.currentTask)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text(session.status.displayLabel)
                        .font(.system(size: 10))
                        .foregroundColor(statusColor)
                }
            }

            Spacer()

            // ── Meta ──
            VStack(alignment: .trailing, spacing: 2) {
                Text(session.status.displayLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(statusColor)
                Text(session.elapsedText)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("\(session.toolCallCount) tools")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
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
