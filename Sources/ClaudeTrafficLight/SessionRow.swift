import SwiftUI

struct SessionRow: View {
    let session: SessionInfo
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            trafficLightStrip
            sessionInfo
            Spacer()
            pinIndicator
            statusMeta
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? Color.white.opacity(0.06) : Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.04), lineWidth: 0.5)
        )
    }

    // MARK: - Traffic light strip

    private var trafficLightStrip: some View {
        VStack(spacing: 3) {
            bulb(isOn: session.status == .error, color: .red)
            bulb(isOn: session.status == .thinking || session.status == .blocked, color: .yellow)
            bulb(isOn: session.status == .working || session.status == .idle, color: .green)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(Color(red: 0.05, green: 0.05, blue: 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func bulb(isOn: Bool, color: Color) -> some View {
        Circle()
            .fill(isOn ? color : color.opacity(0.15))
            .frame(width: 10, height: 10)
            .shadow(color: isOn ? color.opacity(0.5) : .clear, radius: 3)
    }

    // MARK: - Session info

    private var sessionInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.displayTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)

            Text(session.currentTask.isEmpty ? session.status.displayLabel : session.currentTask)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
                .lineLimit(1)
        }
    }

    // MARK: - Pin indicator

    private var pinIndicator: some View {
        Group {
            if session.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.yellow.opacity(0.7))
            }
        }
    }

    // MARK: - Status meta

    private var statusMeta: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if session.isActive {
                HStack(spacing: 2) {
                    Circle().fill(Color.green).frame(width: 4, height: 4)
                    Text("live")
                        .font(.system(size: 9))
                        .foregroundColor(.green.opacity(0.8))
                }
            } else {
                Text(session.status.displayLabel)
                    .font(.system(size: 9))
                    .foregroundColor(statusColor)
            }
            Text(session.elapsedText)
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.25))
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
