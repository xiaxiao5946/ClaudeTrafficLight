import SwiftUI

/// Traffic light icon for the macOS menu bar.
/// Menu bar status items are tight — keep total width ≤ 16px.
struct TrafficLightBarIcon: View {
    let sessions: [SessionInfo]

    private var activeSessions: [SessionInfo] {
        sessions.filter { $0.isActive }
    }

    private var hasThinking: Bool { activeSessions.contains { $0.status == .thinking } }
    private var hasWorking: Bool { activeSessions.contains { $0.status == .working || $0.status == .idle } }
    private var hasError: Bool { activeSessions.contains { $0.status == .error } }
    private var hasBlocked: Bool { activeSessions.contains { $0.status == .blocked } }
    private var hasActive: Bool { !activeSessions.isEmpty }

    var body: some View {
        HStack(spacing: 1) {
            Circle().fill(hasError ? Color.red : Color.red.opacity(0.25))
                .frame(width: 5, height: 5)
            Circle().fill(hasThinking || hasBlocked ? Color.yellow : Color.yellow.opacity(0.25))
                .frame(width: 5, height: 5)
            Circle().fill(hasWorking ? Color.green : Color.green.opacity(hasActive ? 0.25 : 0.35))
                .frame(width: 5, height: 5)
        }
    }
}
