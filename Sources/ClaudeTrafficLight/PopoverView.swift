import SwiftUI

struct PopoverView: View {
    @ObservedObject var monitor: SessionMonitor
    var onShowFloating: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
            Divider().background(Color.white.opacity(0.08))
            sessionList
            detailPanel
            bottomBar
        }
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            // Mini traffic light
            let s = monitor.activeStatusSummary
            MiniTrafficLight(red: s.hasError, yellow: s.hasBlocked || s.hasThinking, green: s.hasWorking)
                .frame(width: 20, height: 48)

            Text("Claude Code")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.85))

            Spacer()

            Text("\(monitor.sessions.filter { $0.isActive }.count) active")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 0) {
            ForEach(SessionMonitor.FilterMode.allCases, id: \.self) { mode in
                Button(mode.rawValue) {
                    monitor.filterMode = mode
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: monitor.filterMode == mode ? .semibold : .regular))
                .foregroundColor(monitor.filterMode == mode ? .white : .white.opacity(0.35))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    monitor.filterMode == mode ?
                    Color.white.opacity(0.1) : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Spacer()
            Button(action: { monitor.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    // MARK: - Session list

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                let displayed = monitor.filteredSessions
                if displayed.isEmpty {
                    emptyView
                } else {
                    ForEach(displayed) { session in
                        SessionRow(
                            session: session,
                            isSelected: monitor.selectedSessionId == session.id
                        )
                        .onTapGesture {
                            monitor.selectedSessionId = session.id
                        }
                        .contextMenu {
                            Button(monitor.pinnedIds.contains(session.id) ? "Unpin" : "Pin") {
                                monitor.togglePin(session.id)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Detail panel

    @ViewBuilder
    private var detailPanel: some View {
        if let selected = monitor.sessions.first(where: { $0.id == monitor.selectedSessionId }) {
            Divider().background(Color.white.opacity(0.08))
            SessionDetailView(session: selected)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            Button("Open Window") { onShowFloating() }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Text("No sessions found")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
            Text("Run 'claude' in a terminal to begin")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
        }
        .padding(.top, 40)
    }
}

// MARK: - Mini traffic light (used in popover header)

struct MiniTrafficLight: View {
    let red: Bool
    let yellow: Bool
    let green: Bool

    var body: some View {
        VStack(spacing: 4) {
            Circle().fill(red ? Color.red : Color.red.opacity(0.2))
                .frame(width: 8, height: 8)
                .shadow(color: red ? .red.opacity(0.5) : .clear, radius: 3)
            Circle().fill(yellow ? Color.yellow : Color.yellow.opacity(0.2))
                .frame(width: 8, height: 8)
                .shadow(color: yellow ? .yellow.opacity(0.5) : .clear, radius: 3)
            Circle().fill(green ? Color.green : Color.green.opacity(0.2))
                .frame(width: 8, height: 8)
                .shadow(color: green ? .green.opacity(0.5) : .clear, radius: 3)
        }
        .padding(4)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
