import SwiftUI

struct TrafficLightBarIcon: View {
    let sessions: [SessionInfo]

    private var activeSessions: [SessionInfo] {
        sessions.filter { $0.isActive }
    }

    private var hasThinking: Bool { activeSessions.contains { $0.status == .thinking } }
    private var hasWorking: Bool { activeSessions.contains { $0.status == .working } }
    private var hasError: Bool { activeSessions.contains { $0.status == .error } }
    private var hasBlocked: Bool { activeSessions.contains { $0.status == .blocked } }

    private var primaryColor: Color {
        if hasError { return .red }
        if hasBlocked { return .yellow }
        if hasThinking { return .yellow }
        if hasWorking { return .green }
        if activeSessions.isEmpty { return Color(nsColor: .disabledControlTextColor) }
        return .green // idle
    }

    var body: some View {
        HStack(spacing: 2) {
            Circle().fill(hasError ? Color.red : Color.red.opacity(0.2))
                .frame(width: 6, height: 6)
            Circle().fill(hasThinking || hasBlocked ? Color.yellow : Color.yellow.opacity(0.2))
                .frame(width: 6, height: 6)
            Circle().fill(hasWorking || (!hasError && !hasThinking && !hasBlocked) ? Color.green : Color.green.opacity(0.2))
                .frame(width: 6, height: 6)
        }
        .padding(3)
        .background(Color.black.clipShape(RoundedRectangle(cornerRadius: 5)))
    }
}
