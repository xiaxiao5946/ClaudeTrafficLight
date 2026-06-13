import SwiftUI

struct SessionRow: View {
    let session: SessionInfo
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            trafficLightStrip
            sessionInfo
            Spacer()
            statusMeta
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Color.white.opacity(0.06) : Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.04), lineWidth: 0.5)
        )
    }

    // MARK: - Sub-views

    private var trafficLightStrip: some View {
        VStack(spacing: 4) {
            redBulb
            yellowBulb
            greenBulb
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 5)
        .background(Color(red: 0.05, green: 0.05, blue: 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var redBulb: some View {
        let isOn = session.status == .error
        return Circle()
            .fill(isOn ? Color.red : Color.red.opacity(0.15))
            .frame(width: 16, height: 16)
            .shadow(color: isOn ? .red.opacity(0.5) : .clear, radius: 4)
    }

    private var yellowBulb: some View {
        let isOn = session.status == .thinking || session.status == .blocked
        return Circle()
            .fill(isOn ? Color.yellow : Color.yellow.opacity(0.15))
            .frame(width: 16, height: 16)
            .shadow(color: isOn ? .yellow.opacity(0.5) : .clear, radius: 4)
    }

    private var greenBulb: some View {
        let isOn = session.status == .working || session.status == .idle
        return Circle()
            .fill(isOn ? Color.green : Color.green.opacity(0.15))
            .frame(width: 16, height: 16)
            .shadow(color: isOn ? .green.opacity(0.5) : .clear, radius: 4)
    }

    private var sessionInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.displayTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)

            Text(session.currentTask.isEmpty ? "—" : session.currentTask)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
                .lineLimit(1)
        }
    }

    private var statusMeta: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(session.status.displayLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(statusColor)

            Text(session.elapsedText)
                .font(.system(size: 9))
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
