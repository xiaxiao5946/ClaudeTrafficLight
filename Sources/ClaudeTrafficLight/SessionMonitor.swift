import Foundation

extension Notification.Name {
    static let CTLSessionsChanged = Notification.Name("CTLSessionsChanged")
}

class SessionMonitor: ObservableObject {
    @Published var sessions: [SessionInfo] = []
    @Published var selectedSessionId: String?
    @Published var filterMode: FilterMode = .all
    @Published var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: "CTLNotificationsEnabled")
        }
    }
    private var dismissedIds: Set<String> = []
    private var justCompletedIds: Set<String> = []  // show until user clicks

    enum FilterMode: String, CaseIterable {
        case all = "全部"
        case active = "活跃"
        case pinned = "已固定"
    }

    private var timer: Timer?
    private let claudeDir: URL
    private let configDir: URL
    private var pidCache: [Int: (alive: Bool, checkedAt: Date)] = [:]
    private let pidCacheTTL: TimeInterval = 10
    private var previousStatuses: [String: SessionStatus] = [:]

    /// Floating window: always compact — pinned, busy, or just-completed only.
    /// Never shows idle/stopped unpinned sessions.
    var floatingWindowSessions: [SessionInfo] {
        sessions.filter { s in
            if s.pinned { return true }
            if justCompletedIds.contains(s.id) { return true }
            guard s.isActive else { return false }
            return s.status == .thinking || s.status == .working || s.status == .blocked || s.status == .error
        }
    }

    /// Popover list: respects the selected filter tab.
    var filteredSessions: [SessionInfo] {
        switch filterMode {
        case .all:
            return sessions  // show everything — pinned, active, idle, stopped, all
        case .active:
            return sessions.filter { s in
                guard s.isActive else { return false }
                return s.status == .thinking || s.status == .working || s.status == .blocked || s.status == .error
            }
        case .pinned:
            // Pinned = always shown. Unpinned = only when busy OR just completed.
            return sessions.filter { s in
                if s.pinned { return true }
                if justCompletedIds.contains(s.id) { return true }
                guard s.isActive else { return false }
                return s.status == .thinking || s.status == .working || s.status == .blocked || s.status == .error
            }
        }
    }

    /// Dismiss a just-completed session (removes it from the list if not pinned)
    func dismissCompleted(_ sessionId: String) {
        justCompletedIds.remove(sessionId)
        dismissedIds.insert(sessionId)
        objectWillChange.send()
    }

    var activeStatusSummary: (hasError: Bool, hasBlocked: Bool, hasThinking: Bool, hasWorking: Bool) {
        let active = sessions.filter { $0.isActive }
        return (
            hasError: active.contains { $0.status == .error },
            hasBlocked: active.contains { $0.status == .blocked },
            hasThinking: active.contains { $0.status == .thinking },
            hasWorking: active.contains { $0.status == .working || $0.status == .idle }
        )
    }

    init() {
        claudeDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude")
        configDir = claudeDir.appendingPathComponent("trafficlight")
        // Load notification preference (default: enabled)
        if UserDefaults.standard.object(forKey: "CTLNotificationsEnabled") != nil {
            notificationsEnabled = UserDefaults.standard.bool(forKey: "CTLNotificationsEnabled")
        } else {
            notificationsEnabled = true
        }
        ensureConfigDir()
        loadPinned()
        startPolling()
    }

    deinit { timer?.invalidate() }

    // MARK: - Polling

    func startPolling() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let oldStatuses = self.previousStatuses
            let updated = self.loadSessions()
            DispatchQueue.main.async {
                // Detect status changes for notifications
                var changes: [(SessionInfo, SessionStatus)] = []
                for s in updated {
                    let old = oldStatuses[s.id] ?? .stopped
                    if s.status != old && s.isActive {
                        changes.append((s, old))
                    }
                    // Track just-completed: busy → idle
                    let oldBusy = old == .thinking || old == .working || old == .blocked
                    if s.status == .idle && oldBusy && s.isActive && !self.justCompletedIds.contains(s.id) {
                        self.justCompletedIds.insert(s.id)
                    }
                    self.previousStatuses[s.id] = s.status
                }
                self.sessions = updated
                // Don't auto-select — user clicks to see details
                NotificationCenter.default.post(
                    name: .CTLSessionsChanged,
                    object: nil,
                    userInfo: ["changes": changes]
                )
            }
        }
    }

    // MARK: - Pin management

    func togglePin(_ sessionId: String) {
        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[idx].pinned.toggle()
            savePinned()
            objectWillChange.send()
        }
    }

    var pinnedIds: Set<String> {
        Set(sessions.filter(\.pinned).map(\.id))
    }

    private func loadPinned() {
        let file = configDir.appendingPathComponent("pinned.json")
        guard let data = try? Data(contentsOf: file),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return }
        pinnedIdsFromDisk = Set(ids)
    }

    private var pinnedIdsFromDisk: Set<String> = []

    private func savePinned() {
        ensureConfigDir()
        let ids = sessions.filter(\.pinned).map(\.id)
        pinnedIdsFromDisk = Set(ids)  // sync cache immediately
        let file = configDir.appendingPathComponent("pinned.json")
        guard let data = try? JSONEncoder().encode(ids) else { return }
        try? data.write(to: file)
    }

    private func ensureConfigDir() {
        try? FileManager.default.createDirectory(at: configDir,
                                                  withIntermediateDirectories: true)
    }

    // MARK: - Data Loading

    private func loadSessions() -> [SessionInfo] {
        var results: [SessionInfo] = []
        var seenIds = Set<String>()

        // 1. Scan live session JSONs
        let sessionsDir = claudeDir.appendingPathComponent("sessions")
        if let files = try? FileManager.default.contentsOfDirectory(at: sessionsDir,
                                                                     includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "json" {
                if let info = parseSessionJSON(file) {
                    results.append(info)
                    seenIds.insert(info.id)
                }
            }
        }

        // 2. Scan project JSONLs ONLY for pinned sessions or recent ones (cap 20)
        let maxTotal = 20
        let projectsDir = claudeDir.appendingPathComponent("projects")
        if results.count < maxTotal,
           let projectDirs = try? FileManager.default.contentsOfDirectory(at: projectsDir,
                                                                           includingPropertiesForKeys: nil) {
            for projDir in projectDirs {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: projDir.path, isDirectory: &isDir),
                      isDir.boolValue else { continue }
                guard let jsonlFiles = try? FileManager.default.contentsOfDirectory(at: projDir,
                                                                                      includingPropertiesForKeys: nil) else { continue }
                // Only include project sessions that are pinned or very recent
                for jsonlFile in jsonlFiles where jsonlFile.pathExtension == "jsonl" {
                    let sid = jsonlFile.deletingPathExtension().lastPathComponent
                    guard !seenIds.contains(sid) else { continue }
                    guard pinnedIdsFromDisk.contains(sid) else { continue }  // only pinned
                    if let info = parseProjectJSONL(jsonlFile, projectPath: projDir.lastPathComponent) {
                        results.append(info)
                        seenIds.insert(info.id)
                    }
                    if results.count >= maxTotal { break }
                }
                if results.count >= maxTotal { break }
            }
        }

        // 3. Apply pin state
        for i in results.indices {
            if pinnedIdsFromDisk.contains(results[i].id) {
                results[i].pinned = true
            }
        }

        // Sort: pinned first, then active, then by updatedAt
        results.sort { a, b in
            if a.pinned != b.pinned { return a.pinned }
            if a.isActive != b.isActive { return a.isActive }
            return (a.updatedAt ?? .distantPast) > (b.updatedAt ?? .distantPast)
        }

        return results
    }

    private func parseSessionJSON(_ file: URL) -> SessionInfo? {
        guard let data = try? Data(contentsOf: file),
              !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            NSLog("[CTL] skip unparseable session file: \(file.lastPathComponent)")
            return nil
        }

        let pid = json["pid"] as? Int ?? 0
        let sessionId = json["sessionId"] as? String ?? file.deletingPathExtension().lastPathComponent
        let cwd = json["cwd"] as? String ?? ""
        let statusStr = json["status"] as? String ?? "idle"
        let startedAt = json["startedAt"] as? Int64 ?? 0
        let updatedAt = json["updatedAt"] as? Int64 ?? 0

        let isAlive = pid > 0 && cachedIsProcessAlive(pid: pid)
        let projectPath = encodePath(cwd)

        // Determine status: JSONL timestamp-based analysis provides real-time state
        let (title, jsonlStatus, currentTask, toolCount) = parseJSONL(
            sessionId: sessionId, projectPath: projectPath
        )

        // Meta JSON: trust explicit status fields. Only defer to JSONL if absent.
        let hasExplicitStatus = json["status"] != nil
        let metaStatus: SessionStatus? = {
            guard hasExplicitStatus else { return nil }
            switch statusStr {
            case "busy", "running": return .working
            case "waiting", "blocked": return .blocked
            case "idle": return .idle
            default: return nil
            }
        }()

        let status: SessionStatus
        if !isAlive {
            status = .stopped
        } else if let ms = metaStatus {
            // Meta JSON has explicit status field → trust it (even idle)
            status = ms
        } else if jsonlStatus != .idle {
            // No explicit meta status → fall back to JSONL timestamp
            status = jsonlStatus
        } else {
            status = .idle
        }

        return SessionInfo(
            id: sessionId, title: title, status: status, cwd: cwd, pid: pid,
            currentTask: currentTask, toolCallCount: toolCount,
            startedAt: startedAt > 0 ? Date(ms: startedAt) : nil,
            updatedAt: updatedAt > 0 ? Date(ms: updatedAt) : nil,
            projectPath: projectPath, isActive: isAlive
        )
    }

    private func parseProjectJSONL(_ file: URL, projectPath: String) -> SessionInfo? {
        let sessionId = file.deletingPathExtension().lastPathComponent
        let (title, status, currentTask, toolCount) = parseJSONL(
            sessionId: sessionId, projectPath: projectPath, jsonlPath: file
        )
        // Decode cwd from project path
        let cwd = decodePath(projectPath)
        // Get file modification date as rough timestamp
        let modDate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

        return SessionInfo(
            id: sessionId, title: title, status: .stopped, cwd: cwd, pid: nil,
            currentTask: currentTask, toolCallCount: toolCount,
            startedAt: nil, updatedAt: modDate,
            projectPath: projectPath, isActive: false
        )
    }

    private func parseJSONL(sessionId: String, projectPath: String,
                             jsonlPath: URL? = nil) -> (title: String, status: SessionStatus, task: String, toolCount: Int) {
        let path = jsonlPath ?? claudeDir
            .appendingPathComponent("projects")
            .appendingPathComponent(projectPath)
            .appendingPathComponent(sessionId)
            .appendingPathExtension("jsonl")

        guard FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let content = String(data: data, encoding: .utf8) else {
            return ("", .idle, "", 0)
        }

        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !lines.isEmpty else { return ("", .idle, "", 0) }

        var title = ""
        var toolCount = 0
        var lastToolName = ""

        // Parse last line for real-time status
        guard let lastLineData = lines.last?.data(using: .utf8),
              let lastJson = try? JSONSerialization.jsonObject(with: lastLineData) as? [String: Any] else {
            return ("", .idle, "", 0)
        }

        let lastType = lastJson["type"] as? String ?? ""
        let lastTimestamp = lastJson["timestamp"] as? String ?? ""
        let lastStopReason = (lastJson["message"] as? [String: Any])?["stop_reason"] as? String

        // Parse ISO timestamp to check recency
        let isRecent: Bool = {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = fmt.date(from: lastTimestamp) ?? {
                // Try without fractional seconds
                let f = ISO8601DateFormatter()
                return f.date(from: lastTimestamp)
            }() else { return false }
            return Date().timeIntervalSince(date) < 30  // active within 30s
        }()

        // Determine status from last event
        let status: SessionStatus
        if lastType == "assistant" {
            if lastStopReason == "tool_use" {
                status = .working  // executing tool
            } else if isRecent {
                status = .thinking
            } else {
                status = .idle
            }
        } else if lastType == "user" {
            // Last event is user → check if it contains a tool_result (model is processing)
            let content = (lastJson["message"] as? [String: Any])?["content"] as? [[String: Any]]
            let hasToolResult = content?.contains { $0["type"] as? String == "tool_result" } ?? false
            if hasToolResult && isRecent {
                status = .working  // tool just completed, model will respond
            } else if isRecent {
                status = .thinking  // user just sent a message
            } else {
                status = .idle
            }
        } else if lastType == "system" {
            let subtype = lastJson["subtype"] as? String ?? ""
            status = subtype.contains("permission") ? .blocked : .idle
        } else {
            status = isRecent ? .idle : .idle  // idle by default
        }

        // Also scan for title (first user message) and tool counts
        let scanEnd = min(500, lines.count)
        for i in 0..<scanEnd {
            guard let lineData = lines[i].data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
            let type = json["type"] as? String ?? ""

            if type == "user" && title.isEmpty {
                title = extractUserText(json) ?? ""
            }
            if type == "assistant", let msg = json["message"] as? [String: Any],
               let contentArr = msg["content"] as? [[String: Any]] {
                for block in contentArr {
                    if block["type"] as? String == "tool_use" {
                        toolCount += 1
                        if let name = block["name"] as? String { lastToolName = name }
                    }
                }
            }
        }

        var currentTask = ""
        if (status == .thinking || status == .working) && !lastToolName.isEmpty {
            currentTask = lastToolName
        }
        return (String(title.prefix(60)), status, currentTask, toolCount)
    }

    private func extractUserText(_ json: [String: Any]) -> String? {
        guard let message = json["message"] as? [String: Any] else { return nil }
        if let text = message["content"] as? String { return text }
        if let contentArr = message["content"] as? [[String: Any]] {
            for block in contentArr {
                if block["type"] as? String == "text",
                   let text = block["text"] as? String { return text }
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func cachedIsProcessAlive(pid: Int) -> Bool {
        if let cached = pidCache[pid], Date().timeIntervalSince(cached.checkedAt) < pidCacheTTL {
            return cached.alive
        }
        let alive = kill(pid_t(pid), 0) == 0
        pidCache[pid] = (alive, Date())
        return alive
    }

    private func encodePath(_ path: String) -> String {
        path.replacingOccurrences(of: "/", with: "-")
    }

    private func decodePath(_ encoded: String) -> String {
        encoded.replacingOccurrences(of: "-", with: "/")
    }
}

private extension Date {
    init(ms: Int64) {
        self.init(timeIntervalSince1970: Double(ms) / 1000.0)
    }
}
