import Foundation

enum SessionStatus: String, Codable, Equatable {
    case idle
    case thinking
    case working
    case blocked
    case error
    case stopped

    var displayLabel: String {
        switch self {
        case .idle: return "空闲"
        case .thinking: return "思考中"
        case .working: return "执行中"
        case .blocked: return "等待确认"
        case .error: return "出错"
        case .stopped: return "已结束"
        }
    }

    var emoji: String {
        switch self {
        case .idle, .working: return "🟢"
        case .thinking, .blocked: return "🟡"
        case .error: return "🔴"
        case .stopped: return "⚫"
        }
    }

    /// Priority for flash alerts (higher = more urgent)
    var alertPriority: Int {
        switch self {
        case .error: return 3
        case .blocked: return 2
        case .thinking: return 1
        default: return 0
        }
    }
}

struct SessionInfo: Identifiable, Hashable {
    let id: String          // sessionId
    var title: String       // first user message or cwd
    var status: SessionStatus
    var cwd: String
    var pid: Int?
    var currentTask: String // latest tool call or message summary
    var toolCallCount: Int
    var startedAt: Date?
    var updatedAt: Date?
    var projectPath: String // encoded project path for JSONL lookup
    var isActive: Bool      // process still alive

    // Pin state — persisted to disk
    var pinned: Bool = false

    var displayTitle: String {
        if title.isEmpty {
            let url = URL(fileURLWithPath: cwd)
            return url.lastPathComponent
        }
        return title
    }

    var elapsedText: String {
        guard let start = startedAt else { return "" }
        let interval = Date().timeIntervalSince(start)
        if interval < 60 { return "\(Int(interval))s" }
        if interval < 3600 { return "\(Int(interval / 60))m \(Int(interval.truncatingRemainder(dividingBy: 60)))s" }
        let h = Int(interval / 3600)
        let m = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        return "\(h)h \(m)m"
    }

    var projectDir: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }
}
