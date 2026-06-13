import Foundation

enum SessionStatus: String, Codable {
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

    var lightColor: String {
        switch self {
        case .idle: return "green"
        case .thinking: return "yellow"
        case .working: return "green"
        case .blocked: return "yellow"
        case .error: return "red"
        case .stopped: return "off"
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
