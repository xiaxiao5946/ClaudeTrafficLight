import SwiftUI

struct PopoverView: View {
    @ObservedObject var monitor: SessionMonitor

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("C")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

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
            .padding(.bottom, 10)

            // Session list
            ScrollView {
                LazyVStack(spacing: 6) {
                    if monitor.sessions.isEmpty {
                        emptyView
                    } else {
                        ForEach(monitor.sessions) { session in
                            SessionRow(
                                session: session,
                                isSelected: monitor.selectedSessionId == session.id
                            )
                            .onTapGesture {
                                monitor.selectedSessionId = session.id
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }

            Divider().background(Color.white.opacity(0.08))

            // Detail panel
            if let selected = monitor.sessions.first(where: { $0.id == monitor.selectedSessionId }) {
                SessionDetailView(session: selected)
            }

            // Quit button
            HStack {
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
                .padding(.trailing, 16)
                .padding(.bottom, 10)
            }
        }
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Text("No sessions found")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
            Text("Start Claude Code to begin")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
        }
        .padding(.top, 40)
    }
}
