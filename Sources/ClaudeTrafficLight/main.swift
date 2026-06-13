import SwiftUI
import AppKit

// ═══════════════════════════════════════════════════════════════════════
//  ClaudeTrafficLight — SwiftUI MenuBarExtra + Floating Window
// ═══════════════════════════════════════════════════════════════════════

@main
struct ClaudeTrafficLightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var monitor = SessionMonitor()

    var body: some Scene {
        // ── Menu Bar Icon (MenuBarExtra — Apple recommended API) ──
        MenuBarExtra("Claude Traffic Light", systemImage: "circle.fill") {
            MenuBarPopoverContent(monitor: monitor, onShowFloating: {
                appDelegate.showFloatingWindow()
            })
        }
        .menuBarExtraStyle(.window)

        // ── Floating Window ──
        Window("Claude Traffic Light", id: "floating-panel") {
            FloatingWindowContent(monitor: monitor, onToggleMode: {
                appDelegate.hideFloatingWindow()
            })
            .frame(minWidth: 320, minHeight: 400)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// ═══════════════════════════════════════════════════════════════════════
//  AppDelegate
// ═══════════════════════════════════════════════════════════════════════

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("ClaudeTrafficLight running")
        NSLog("[CTL] ✅ SwiftUI MenuBarExtra version launched")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showFloatingWindow()
        return true
    }

    func showFloatingWindow() {
        for window in NSApp.windows {
            if window.title == "Claude Traffic Light" {
                window.makeKeyAndOrderFront(nil)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideFloatingWindow() {
        for window in NSApp.windows {
            if window.title == "Claude Traffic Light" {
                window.orderOut(nil)
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
//  Menu Bar Popover Content
// ═══════════════════════════════════════════════════════════════════════

struct MenuBarPopoverContent: View {
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
