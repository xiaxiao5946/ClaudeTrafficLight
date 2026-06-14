import SwiftUI

struct SessionDetailView: View {
    let session: SessionInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 10, height: 10)

                Text(session.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                if session.isActive {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("live")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.3))
                } else {
                    Text("ended")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.25))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            // Current task
            VStack(alignment: .leading, spacing: 2) {
                Text("Current operation")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
                Text(session.currentTask.isEmpty ? "—" : session.currentTask)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(statusColor.opacity(0.7))
                        .frame(width: max(3, geo.size.width * progressRatio))
                }
            }
            .frame(height: 3)
            .clipShape(RoundedRectangle(cornerRadius: 1.5))
            .padding(.horizontal, 14)
            .padding(.top, 8)

            // Footer stats
            HStack {
                Text(session.elapsedText + " elapsed")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
                Spacer()
                Text("\(session.toolCallCount) tool calls")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
                Spacer()
                Text(session.projectDir)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .background(Color(red: 0.09, green: 0.09, blue: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

    private var progressRatio: CGFloat {
        switch session.status {
        case .idle: return 0.05
        case .thinking: return 0.15
        case .working: return 0.6
        case .blocked: return 0.45
        case .error: return 0.3
        case .stopped: return 1.0
        }
    }
}
