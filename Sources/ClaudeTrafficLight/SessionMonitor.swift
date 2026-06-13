import Foundation
import Combine

class SessionMonitor: ObservableObject {
    @Published var sessions: [SessionInfo] = []
    @Published var selectedSessionId: String?

    private var timer: Timer?
    private let claudeDir: URL

    init() {
        claudeDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude")
        startPolling()
    }

    deinit {
        timer?.invalidate()
    }

    func startPolling() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let updated = self.loadSessions()
            DispatchQueue.main.async {
                self.sessions = updated
                if self.selectedSessionId == nil, let first = updated.first {
                    self.selectedSessionId = first.id
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadSessions() -> [SessionInfo] {
        let sessionsDir = claudeDir.appendingPathComponent("sessions")
        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: nil) else {
            NSLog("[ClaudeTrafficLight] No sessions directory found at \(sessionsDir.path)")
            return []
        }

        var results: [SessionInfo] = []

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let pid = json["pid"] as? Int ?? 0
            let sessionId = json["sessionId"] as? String ?? UUID().uuidString
            let cwd = json["cwd"] as? String ?? ""
            let statusStr = json["status"] as? String ?? "idle"
            let startedAt = json["startedAt"] as? Int64 ?? 0
            let updatedAt = json["updatedAt"] as? Int64 ?? 0
            let version = json["version"] as? String ?? ""

            let isAlive = pid > 0 && self.isProcessAlive(pid: pid)
            let projectPath = self.encodePath(cwd)

            // Parse JSONL for title and details
            let (title, jsonlStatus, currentTask, toolCount) = self.parseSessionJSONL(
                sessionId: sessionId,
                projectPath: projectPath
            )

            // Determine status: prefer JSONL parsing, fallback to meta status
            let status: SessionStatus
            if !isAlive {
                status = .stopped
            } else if jsonlStatus != .idle {
                status = jsonlStatus
            } else {
                switch statusStr {
                case "idle": status = .idle
                case "busy", "running": status = .working
                case "waiting", "blocked": status = .blocked
                default: status = .idle
                }
            }

            let info = SessionInfo(
                id: sessionId,
                title: title,
                status: status,
                cwd: cwd,
                pid: pid,
                currentTask: currentTask,
                toolCallCount: toolCount,
                startedAt: startedAt > 0 ? Date(timeIntervalSince1970: Double(startedAt) / 1000) : nil,
                updatedAt: updatedAt > 0 ? Date(timeIntervalSince1970: Double(updatedAt) / 1000) : nil,
                projectPath: projectPath,
                isActive: isAlive
            )

            results.append(info)
        }

        // Sort: active first, then by updatedAt descending
        results.sort { a, b in
            if a.isActive != b.isActive { return a.isActive }
            return (a.updatedAt ?? .distantPast) > (b.updatedAt ?? .distantPast)
        }

        return results
    }

    private func isProcessAlive(pid: Int) -> Bool {
        let result = kill(pid_t(pid), 0)
        return result == 0
    }

    private func encodePath(_ path: String) -> String {
        path.replacingOccurrences(of: "/", with: "-")
    }

    // MARK: - JSONL Parsing

    private func parseSessionJSONL(sessionId: String, projectPath: String) -> (title: String, status: SessionStatus, task: String, toolCount: Int) {
        let jsonlPath = claudeDir
            .appendingPathComponent("projects")
            .appendingPathComponent(projectPath)
            .appendingPathComponent(sessionId)
            .appendingPathExtension("jsonl")

        let fm = FileManager.default
        guard fm.fileExists(atPath: jsonlPath.path) else {
            return ("", .idle, "", 0)
        }

        guard let data = try? Data(contentsOf: jsonlPath) else {
            return ("", .idle, "", 0)
        }

        guard let content = String(data: data, encoding: .utf8) else {
            return ("", .idle, "", 0)
        }

        var title = ""
        var status: SessionStatus = .idle
        var currentTask = ""
        var toolCount = 0
        var lastToolName = ""

        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Only parse last 200 lines for performance
        let startIdx = max(0, lines.count - 200)
        for i in startIdx..<lines.count {
            let line = lines[i]
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            let type = json["type"] as? String ?? ""

            // Get title from first user message (scan from beginning)
            if type == "user" && title.isEmpty {
                if let message = json["message"] as? [String: Any] {
                    if let text = message["content"] as? String {
                        title = String(text.prefix(60))
                    } else if let contentArr = message["content"] as? [[String: Any]] {
                        for block in contentArr {
                            if block["type"] as? String == "text",
                               let text = block["text"] as? String {
                                title = String(text.prefix(60))
                                break
                            }
                        }
                    }
                }
            }

            // Track tool calls
            if type == "assistant" {
                if let message = json["message"] as? [String: Any],
                   let contentArr = message["content"] as? [[String: Any]] {
                    for block in contentArr {
                        if block["type"] as? String == "tool_use" {
                            toolCount += 1
                            if let name = block["name"] as? String {
                                lastToolName = name
                            }
                        }
                    }
                }
                status = .thinking
            }

            if type == "tool_result" || type == "tool" {
                status = .thinking
            }

            // Permission prompts
            if type == "system" {
                let subtype = json["subtype"] as? String ?? ""
                if subtype.contains("permission") {
                    status = .blocked
                }
                if subtype == "away_summary" || subtype == "turn_duration" {
                    status = .idle
                }
            }
        }

        if status == .thinking && !lastToolName.isEmpty {
            currentTask = lastToolName
        }

        return (title, status, currentTask, toolCount)
    }
}
