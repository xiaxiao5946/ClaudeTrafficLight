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
        let content = VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                let s = sharedMonitor.activeStatusSummary
                VStack(spacing: 4) {
                    Circle().fill(s.hasError ? Color.red : Color.red.opacity(0.15))
                        .frame(width: 14, height: 14)
                    Circle().fill(s.hasBlocked || s.hasThinking ? Color.yellow : Color.yellow.opacity(0.15))
                        .frame(width: 14, height: 14)
                    Circle().fill(s.hasWorking ? Color.green : Color.green.opacity(0.15))
                        .frame(width: 14, height: 14)
                }
                .padding(6).background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude Traffic Light").font(.system(size: 14, weight: .bold))
                    Text("\(sharedMonitor.sessions.filter(\.isActive).count) active / \(sharedMonitor.sessions.count) total")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { sharedMonitor.refresh() }) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            Divider()

            // Session list
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(sharedMonitor.filteredSessions) { session in
                        HStack(spacing: 10) {
                            VStack(spacing: 2) {
                                Circle().fill(session.status == .error ? Color.red : Color.red.opacity(0.15)).frame(width: 8, height: 8)
                                Circle().fill((session.status == .thinking || session.status == .blocked) ? Color.yellow : Color.yellow.opacity(0.15)).frame(width: 8, height: 8)
                                Circle().fill((session.status == .working || session.status == .idle) ? Color.green : Color.green.opacity(0.15)).frame(width: 8, height: 8)
                            }.padding(4).background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.displayTitle).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Text(session.status.displayLabel).font(.system(size: 10)).foregroundColor(statusCardColor(session.status))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                if session.isActive {
                                    HStack(spacing: 2) { Circle().fill(Color.green).frame(width: 5, height: 5); Text("active").font(.system(size: 9)).foregroundColor(.green) }
                                }
                                Text(session.elapsedText).font(.system(size: 9)).foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
            }

            Divider()

            // Footer
            HStack(spacing: 12) {
                Toggle("Always on Top", isOn: Binding(get: { self.floatingWindow?.level == .floating },
                                                       set: { self.floatingWindow?.level = $0 ? .floating : .normal }))
                    .toggleStyle(.checkbox).font(.system(size: 10))
                Spacer()
                Button("Menu Bar Only") { [weak self] in self?.switchToMenuBarOnly() }
                    .buttonStyle(.plain).font(.system(size: 10))
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor))

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

            switch session.status {
            case .blocked where oldStatus != .blocked:
                startFlash(2, rounds: 3)  // yellow flash
                notify("Claude Code Blocked", body: "「\(session.displayTitle)」需要你的确认")

            case .error where oldStatus != .error:
                startFlash(1, rounds: 5)  // red flash
                notify("Claude Code Error", body: "「\(session.displayTitle)」出错")

            case .idle where (oldStatus == .thinking || oldStatus == .working):
                startFlash(4, rounds: 1)  // green flash — task done
                notify("Claude Code Complete", body: "「\(session.displayTitle)」执行完毕", sound: nil)

            case .thinking where oldStatus == .idle:
                // Started thinking — subtle yellow flash
                startFlash(2, rounds: 1)

            default: break
            }
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
