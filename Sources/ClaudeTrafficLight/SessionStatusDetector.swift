import Foundation

enum SessionStatusDetector {
    static func resolve(
        isAlive: Bool,
        hookStatus: SessionStatus?,
        hookUpdatedAt: Date? = nil,
        jsonlStatus: SessionStatus,
        jsonlUpdatedAt: Date? = nil,
        metaStatus: SessionStatus?
    ) -> SessionStatus {
        if !isAlive { return .stopped }

        if let hookStatus {
            if let hookUpdatedAt, let jsonlUpdatedAt {
                if jsonlUpdatedAt > hookUpdatedAt {
                    if jsonlStatus == .error || jsonlStatus == .blocked { return jsonlStatus }
                    return metaStatus ?? jsonlStatus
                }
                return hookStatus
            }
            if jsonlStatus == .error || jsonlStatus == .blocked { return jsonlStatus }
            return hookStatus
        }

        if jsonlStatus == .error || jsonlStatus == .blocked { return jsonlStatus }
        return metaStatus ?? jsonlStatus
    }

    static func latestEvent(in lines: [String]) -> [String: Any]? {
        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  isStatusEvent(event) else { continue }
            return event
        }
        return nil
    }

    static func status(forMetaValue value: String) -> SessionStatus? {
        switch value {
        case "busy", "running": return .working
        case "waiting", "blocked": return .blocked
        case "error", "failed": return .error
        case "idle": return .idle
        default: return nil
        }
    }

    static func status(for event: [String: Any], isRecent: Bool) -> SessionStatus {
        let type = event["type"] as? String ?? ""
        let hasErrorValue = event["error"].map { !($0 is NSNull) } ?? false

        if event["isApiErrorMessage"] as? Bool == true ||
            type == "error" || hasErrorValue {
            return .error
        }

        switch type {
        case "assistant":
            let stopReason = (event["message"] as? [String: Any])?["stop_reason"] as? String
            if stopReason == "tool_use" { return .working }
            return isRecent ? .thinking : .idle

        case "user":
            let content = (event["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            let toolResults = content.filter { $0["type"] as? String == "tool_result" }

            if let failedResult = toolResults.last(where: { $0["is_error"] as? Bool == true }) {
                return isPermissionWait(event: event, toolResult: failedResult) ? .blocked : .error
            }
            if !toolResults.isEmpty && isRecent { return .working }
            return isRecent ? .thinking : .idle

        case "system":
            let subtype = event["subtype"] as? String ?? ""
            return subtype.contains("permission") ? .blocked : .idle

        default:
            return .idle
        }
    }

    private static func isStatusEvent(_ event: [String: Any]) -> Bool {
        let type = event["type"] as? String ?? ""
        if type == "assistant" || type == "user" || type == "error" { return true }
        if event["isApiErrorMessage"] as? Bool == true { return true }
        if let error = event["error"], !(error is NSNull) { return true }

        let subtype = event["subtype"] as? String ?? ""
        return type == "system" && subtype.contains("permission")
    }

    private static func isPermissionWait(event: [String: Any], toolResult: [String: Any]) -> Bool {
        let eventResult = event["toolUseResult"] as? String ?? ""
        let resultContent = toolResult["content"] as? String ?? ""
        let text = "\(eventResult)\n\(resultContent)".lowercased()
        let markers = [
            "user rejected tool use",
            "user doesn't want to proceed",
            "permission for this action was denied",
            "requires explicit user authorization"
        ]
        return markers.contains { text.contains($0) }
    }
}
