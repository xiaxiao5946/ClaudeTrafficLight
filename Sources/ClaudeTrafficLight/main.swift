import SwiftUI
import AppKit

// ═══════════════════════════════════════════════════════════════════════
//  ClaudeTrafficLight — Monitor + Alert
// ═══════════════════════════════════════════════════════════════════════

let sharedMonitor = SessionMonitor()
var gAutoExpandEnabled = true  // toggle in popover

extension Notification.Name {
    static let CTLExpandWindow = Notification.Name("CTLExpandWindow")
    static let CTLSnapCollapse = Notification.Name("CTLSnapCollapse")
}

// ═══════════════════════════════════════════════════════════════════════
//  AppDelegate
// ═══════════════════════════════════════════════════════════════════════

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
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
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 360),
            styleMask: [.closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Claude Traffic Light"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.level = .floating  // default to floating
        window.center()
        window.setFrameAutosaveName("CTLFloating")
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.delegate = self
        floatingWindow = window
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard let win = notification.object as? NSWindow,
              win == floatingWindow else { return }
        windowLastMoveTime = Date()

        // Drag collapsed → auto-expand
        if win.frame.width < 60 && !gSnapInProgress {
            NSLog("[CTL] drag-expand triggered")
            gSnapInProgress = true
            NotificationCenter.default.post(name: .CTLExpandWindow, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { gSnapInProgress = false }
        }
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
        // Traffic light icon in notification
        note.contentImage = TrafficLightIcon.drawNotificationIcon(state: .init(
            redOn: sharedMonitor.activeStatusSummary.hasError,
            yellowOn: sharedMonitor.activeStatusSummary.hasBlocked || sharedMonitor.activeStatusSummary.hasThinking,
            greenOn: sharedMonitor.activeStatusSummary.hasWorking,
            flashMask: 0
        ))
        NSUserNotificationCenter.default.deliver(note)
        NSLog("[CTL] notified: \(title)")
    }

    // MARK: - Session change handler

    private func handleSessionChanges(_ changes: [(SessionInfo, SessionStatus)]) {
        var shouldExpand = false

        for (session, oldStatus) in changes {
            let isBusy = { (s: SessionStatus) in s == .thinking || s == .working || s == .blocked }
            let newIsBusy = isBusy(session.status)
            let oldIsBusy = isBusy(oldStatus)

            NSLog("[CTL] change: 「\(session.displayTitle)」 \(oldStatus.displayLabel) → \(session.status.displayLabel) active=\(session.isActive)")

            switch session.status {
            case .stopped where oldStatus != .stopped:
                startFlash(4, rounds: 2)
                notify("Claude → 会话结束", body: "「\(session.displayTitle)」已退出", sound: true)
                shouldExpand = true

            case .blocked where session.isActive:
                startFlash(2, rounds: 4)
                notify("Claude → 等待确认", body: "「\(session.displayTitle)」需要你的操作")
                shouldExpand = true

            case .error where session.isActive:
                startFlash(1, rounds: 5)
                notify("Claude → 出错", body: "「\(session.displayTitle)」")
                shouldExpand = true

            case .idle where oldIsBusy && session.isActive:
                startFlash(4, rounds: 3)
                notify("Claude → 完成", body: "「\(session.displayTitle)」", sound: true)
                shouldExpand = true

            case .thinking, .working:
                guard session.isActive else { continue }
                if !oldIsBusy {
                    startFlash(2, rounds: 2)
                    notify("Claude → 执行中", body: "「\(session.displayTitle)」\(session.currentTask)", sound: false)
                }

            default: break
            }
        }

        // Auto-expand on important events (if enabled)
        if shouldExpand && gAutoExpandEnabled {
            NotificationCenter.default.post(name: .CTLExpandWindow, object: nil,
                                            userInfo: ["sessionId": changes.last?.0.id ?? ""])
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
//  Floating Window View (separate struct for proper @State management)
// ═══════════════════════════════════════════════════════════════════════

struct FloatingWindowView: View {
    @ObservedObject var monitor: SessionMonitor
    var onMenuBarOnly: () -> Void
    @State private var alwaysOnTop = true
    @State private var contentHeight: CGFloat = 120
    @State private var isCollapsed = false
    @State private var showTooltip = false

    private let lightColumnWidth: CGFloat = 42   // exact width of traffic light column in card
    private let expandedWidth: CGFloat = 260

    var body: some View {
        mainContent
            .background(
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .overlay(Color.black.opacity(0.08))
            )
            .clipShape(RoundedRectangle(cornerRadius: isCollapsed ? 8 : 14))
            .overlay(
                RoundedRectangle(cornerRadius: isCollapsed ? 8 : 14)
                    .stroke(Color.white.opacity(isCollapsed ? 0.06 : 0.1), lineWidth: 0.5)
            )
            .padding(4)
            .onAppear { syncWindowLevel(); startSnapMonitor() }
            .onChange(of: alwaysOnTop) { _ in syncWindowLevel() }
            .onReceive(NotificationCenter.default.publisher(for: .CTLExpandWindow)) { n in
                if isCollapsed { expand() }
                // Auto-expand the specific session that triggered the event
                if gAutoExpandEnabled, let sid = n.userInfo?["sessionId"] as? String, !sid.isEmpty {
                    monitor.expandSession(sid)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .CTLSnapCollapse)) { _ in
                isCollapsed = true
                monitor.expandedSessionIds.removeAll()
                monitor.objectWillChange.send()
            }
            .onHover { handleHover($0) }
    }

    private var mainContent: some View {
        Group {
            if isCollapsed { collapsedView } else { expandedView }
        }
    }

    private func handleHover(_ inside: Bool) {
        gHoverInside = inside
        guard !inside, !isCollapsed else { return }
        gHoverLeaveTime = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard !gHoverInside,
                  Date().timeIntervalSince(gHoverLeaveTime) >= 1.4,
                  let win = NSApp.windows.first(where: { $0.title == "Claude Traffic Light" }),
                  let screen = win.screen else { return }
            let sf = screen.visibleFrame
            let leftDist = win.frame.minX - sf.minX
            let rightDist = sf.maxX - win.frame.maxX
            if leftDist < 100 { snapWindow(to: .leading, win: win, screen: sf) }
            else if rightDist < 100 { snapWindow(to: .trailing, win: win, screen: sf) }
        }
    }

    // MARK: - Expanded view

    private var expandedView: some View {
        VStack(spacing: 0) {
            if monitor.filteredSessions.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "circle.dotted").font(.system(size: 20)).foregroundColor(.secondary.opacity(0.4))
                    Text("No active sessions").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary.opacity(0.6))
                    Text("Pin a session to always see it here").font(.system(size: 9)).foregroundColor(.secondary.opacity(0.4))
                }.frame(height: 80)
            } else {
                let list = monitor.filteredSessions
                if list.count <= 4 {
                    VStack(spacing: 6) {
                        ForEach(list) { session in GlassSessionCard(session: session) }
                    }.padding(.horizontal, 6).padding(.top, 4).padding(.bottom, 4)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(list) { session in GlassSessionCard(session: session) }
                        }.padding(.horizontal, 6).padding(.top, 4).padding(.bottom, 4)
                    }.frame(maxHeight: 320)
                }
            }
            HStack(spacing: 6) {
                Button(action: { monitor.refresh() }) { Image(systemName: "arrow.clockwise").font(.system(size: 10)) }
                    .buttonStyle(.plain).foregroundColor(.secondary.opacity(0.6))
                Button(action: { alwaysOnTop.toggle() }) { Image(systemName: alwaysOnTop ? "pin.fill" : "pin").font(.system(size: 10)) }
                    .buttonStyle(.plain).foregroundColor(alwaysOnTop ? .orange : .secondary.opacity(0.5))
                Spacer()
                Button(action: { onMenuBarOnly() }) { Image(systemName: "minus").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain).foregroundColor(.secondary.opacity(0.4))
            }.padding(.horizontal, 8).padding(.bottom, 6)
        }
        .frame(width: expandedWidth).fixedSize(horizontal: true, vertical: true)
        .background(GeometryReader { geo in
            Color.clear.onAppear {
                let h = geo.size.height
                if abs(h - contentHeight) > 4 { contentHeight = h; resizeWindow(to: h, width: expandedWidth) }
            }
        })
        .onChange(of: monitor.filteredSessions.count) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { contentHeight = 0 }
        }
    }

    // MARK: - Collapsed view (per-session lights)

    private var collapsedView: some View {
        VStack(spacing: 14) {
            if monitor.filteredSessions.isEmpty {
                CollapsedLight(red: false, yellow: false, green: false, dot: 18)
            } else {
                ForEach(monitor.filteredSessions) { session in
                    CollapsedLight(
                        red: session.status == .error,
                        yellow: session.status == .thinking || session.status == .blocked,
                        green: session.status == .working,
                        dot: 18
                    )
                }
            }
            Button(action: { expand() }) {
                Image(systemName: "arrowtriangle.forward.fill").font(.system(size: 5)).foregroundColor(.secondary.opacity(0.3))
            }.buttonStyle(.plain)
        }
        .padding(.vertical, 6).padding(.horizontal, 6)
        .frame(width: lightColumnWidth)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .overlay(Color.black.opacity(0.08))
        )
        .onHover { inside in
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            showTooltip = inside
        }
        .contentShape(Rectangle()).onTapGesture(count: 2) { expand() }
    }

    // MARK: - Snap monitor

    private func startSnapMonitor() {
        if windowSnapTimer == nil {
            windowSnapTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
                DispatchQueue.main.async {
                    guard Date().timeIntervalSince(windowLastMoveTime) > 1.0 else { return }
                    checkSnapGlobal()
                }
            }
        }
    }

    // MARK: - Expand / resize

    private func expand() {
        guard let win = NSApp.windows.first(where: { $0.title == "Claude Traffic Light" }),
              let screen = win.screen else { return }
        // Expand sessions BEFORE window, so cards render expanded
        for s in monitor.filteredSessions {
            monitor.expandedSessionIds.insert(s.id)
        }
        isCollapsed = false
        resizeWindow(to: contentHeight, width: expandedWidth)
        var frame = win.frame; let sf = screen.visibleFrame
        if frame.minX < sf.midX { frame.origin.x = sf.minX }
        else { frame.origin.x = sf.maxX - expandedWidth }
        win.setFrame(frame, display: true, animate: true)
        windowLastMoveTime = Date()
    }

    private func resizeWindow(to height: CGFloat, width: CGFloat) {
        guard let win = NSApp.windows.first(where: { $0.title == "Claude Traffic Light" }) else { return }
        let targetH = max(60, min(500, height + 8))
        var frame = win.frame
        frame.origin.y += frame.height - targetH
        frame.size = NSSize(width: width, height: targetH)
        win.setFrame(frame, display: true, animate: !isCollapsed)
    }

    private func syncWindowLevel() {
        guard let win = NSApp.windows.first(where: { $0.title == "Claude Traffic Light" }) else { return }
        win.level = alwaysOnTop ? .floating : .normal
    }
}

// MARK: - Collapsed per-session light strip

struct CollapsedLight: View {
    let red: Bool, yellow: Bool, green: Bool
    var dot: CGFloat = 8
    var body: some View {
        VStack(spacing: 4) {
            BreathingDot(color: .red, active: red, size: dot)
            BreathingDot(color: .yellow, active: yellow, size: dot)
            BreathingDot(color: .green, active: green, size: dot)
        }
    }
}

// MARK: - Breathing dot

struct BreathingDot: View {
    let color: Color
    let active: Bool
    var size: CGFloat = 18
    @State private var breathe = false

    var body: some View {
        Circle()
            .fill(active ? color : color.opacity(0.12))
            .frame(width: size, height: size)
            .shadow(color: active ? color.opacity(0.6) : .clear, radius: size < 12 ? 4 : 8)
            .scaleEffect(active && breathe ? 1.12 : 1.0)
            .onAppear { if active { breathe = true } }
            .onChange(of: active) { if $0 { breathe = true } else { breathe = false } }
            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: breathe)
    }
}


// Global snap state (survives view re-renders)
private var windowLastMoveTime: Date = .distantPast
private var windowSnapTimer: Timer?
private var gHoverInside = false
private var gHoverLeaveTime: Date = .distantFuture
private var gSnapInProgress = false

private func checkSnapGlobal() {
    guard let win = NSApp.windows.first(where: { $0.title == "Claude Traffic Light" }),
          let screen = win.screen else { return }

    let frame = win.frame
    let screenFrame = screen.visibleFrame
    let leftDist = frame.minX - screenFrame.minX
    let rightDist = screenFrame.maxX - frame.maxX

    // Don't snap if window is already very thin (likely collapsed)
    if frame.width < 100 { return }

    if leftDist < 40 && leftDist > -20 {
        snapWindow(to: .leading, win: win, screen: screenFrame)
    } else if rightDist < 40 && rightDist > -20 {
        snapWindow(to: .trailing, win: win, screen: screenFrame)
    }
}

private func snapWindow(to edge: UnitPoint, win: NSWindow, screen: CGRect) {
    gSnapInProgress = true
    let collapsedW: CGFloat = 42
    var frame = win.frame
    if edge == .leading {
        frame.origin.x = screen.minX
    } else {
        frame.origin.x = screen.maxX - collapsedW
    }
    frame.size.width = collapsedW
    win.setFrame(frame, display: true, animate: true)
    NotificationCenter.default.post(name: .CTLSnapCollapse, object: nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { gSnapInProgress = false }
}


// MARK: - Preference key for content height

struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 120
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Visual Effect (NSVisualEffectView wrapper)

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blendingMode
    }
}

// MARK: - Glass session card (prominent lights, compact)

struct GlassSessionCard: View {
    @ObservedObject var monitor = sharedMonitor
    let session: SessionInfo

    private var isExpanded: Bool {
        monitor.expandedSessionIds.contains(session.id)
    }

    var body: some View {
        HStack(spacing: 10) {
            // ── Traffic light (always visible, same position) ──
            VStack(spacing: 4) {
                BreathingDot(color: .red, active: session.status == .error, size: 18)
                BreathingDot(color: .yellow, active: session.status == .thinking || session.status == .blocked, size: 18)
                BreathingDot(color: .green, active: session.status == .working || session.status == .idle, size: 18)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.06))
            )

            if isExpanded {
                // ── Session name + task ──
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayTitle)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !session.currentTask.isEmpty {
                        Text(session.currentTask)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))

                Spacer()
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
        )
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .contextMenu {
            Button(isExpanded ? "Collapse" : "Expand") {
                monitor.toggleSessionExpand(session.id)
            }
            Button("Copy Session ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.id, forType: .string)
            }
            if session.status == .idle {
                Button("Dismiss") {
                    sharedMonitor.dismissCompleted(session.id)
                }
            }
        }
        .onTapGesture {
            if session.status == .idle {
                sharedMonitor.dismissCompleted(session.id)
            } else {
                monitor.toggleSessionExpand(session.id)
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
