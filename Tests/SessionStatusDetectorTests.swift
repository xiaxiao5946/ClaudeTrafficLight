import Foundation

@main
struct SessionStatusDetectorTests {
    private static var failureCount = 0

    static func main() {
        testAPIErrorIsRed()
        testMetaErrorIsRed()
        testTerminalToolFailureIsRed()
        testRecoverableToolFailuresStayNonRed()
        testPermissionDenialIsYellow()
        testOSPermissionFailureIsRed()
        testStructuredFailureBeatsStaleHook()
        testNewerHookClearsOldStructuredFailure()
        testNewerJSONLClearsStaleHook()
        testNormalEventsKeepExistingYellowAndGreenSemantics()
        testSuccessfulEventClearsPreviousError()
        testTrailingMetadataDoesNotHideError()
        testWordsAboutErrorsDoNotTurnRed()
        testNullErrorDoesNotTurnRed()

        precondition(failureCount == 0, "\(failureCount) status detector test(s) failed")
        print("All SessionStatusDetector tests passed")
    }

    private static func testAPIErrorIsRed() {
        let event: [String: Any] = [
            "type": "assistant",
            "isApiErrorMessage": true,
            "error": "rate_limit"
        ]

        expect(SessionStatusDetector.status(for: event, isRecent: true), .error, "API error is red")
    }

    private static func testMetaErrorIsRed() {
        expect(SessionStatusDetector.status(forMetaValue: "error"), .error, "meta error is red")
        expect(SessionStatusDetector.status(forMetaValue: "failed"), .error, "meta failure is red")
    }

    private static func testTerminalToolFailureIsRed() {
        let event = toolResultEvent(content: "bash: /root/secret: Permission denied", isError: true)

        expect(SessionStatusDetector.status(for: event, isRecent: true), .error, "terminal tool failure is red")
    }

    private static func testRecoverableToolFailuresStayNonRed() {
        let oversizedRead = toolResultEvent(
            content: "File content (51596 tokens) exceeds maximum allowed tokens (25000).",
            isError: true
        )
        let inputValidation = toolResultEvent(
            content: "<tool_use_error>InputValidationError: missing parameter</tool_use_error>",
            isError: true
        )
        let shellMiss = toolResultEvent(
            content: "Exit code 1\n(eval):1: no matches found: /tmp/*.json",
            isError: true
        )

        expect(SessionStatusDetector.status(for: oversizedRead, isRecent: true), .working, "oversized read is not red")
        expect(SessionStatusDetector.status(for: inputValidation, isRecent: true), .working, "tool validation error is not red")
        expect(SessionStatusDetector.status(for: shellMiss, isRecent: true), .working, "recoverable shell miss is not red")
    }

    private static func testPermissionDenialIsYellow() {
        var event = toolResultEvent(content: "Permission for this action was denied", isError: true)
        event["toolUseResult"] = "User rejected tool use"

        expect(SessionStatusDetector.status(for: event, isRecent: true), .blocked, "permission denial is yellow")
    }

    private static func testOSPermissionFailureIsRed() {
        let event = toolResultEvent(content: "bash: /root/secret: Permission denied", isError: true)

        expect(SessionStatusDetector.status(for: event, isRecent: true), .error, "OS permission failure is red")
    }

    private static func testStructuredFailureBeatsStaleHook() {
        let stale = Date(timeIntervalSince1970: 1)
        let current = Date(timeIntervalSince1970: 2)
        expect(
            SessionStatusDetector.resolve(
                isAlive: true,
                hookStatus: .idle,
                hookUpdatedAt: stale,
                jsonlStatus: .error,
                jsonlUpdatedAt: current,
                metaStatus: .idle
            ),
            .error,
            "structured failure beats stale hook idle"
        )
        expect(
            SessionStatusDetector.resolve(
                isAlive: true,
                hookStatus: .working,
                hookUpdatedAt: stale,
                jsonlStatus: .blocked,
                jsonlUpdatedAt: current,
                metaStatus: .idle
            ),
            .blocked,
            "permission wait beats stale hook working"
        )
        expect(
            SessionStatusDetector.resolve(
                isAlive: false,
                hookStatus: .error,
                jsonlStatus: .error,
                metaStatus: .error
            ),
            .stopped,
            "ended session is off"
        )
    }

    private static func testNewerHookClearsOldStructuredFailure() {
        expect(
            SessionStatusDetector.resolve(
                isAlive: true,
                hookStatus: .working,
                hookUpdatedAt: Date(timeIntervalSince1970: 2),
                jsonlStatus: .error,
                jsonlUpdatedAt: Date(timeIntervalSince1970: 1),
                metaStatus: .idle
            ),
            .working,
            "newer hook clears old structured failure"
        )
    }

    private static func testNewerJSONLClearsStaleHook() {
        expect(
            SessionStatusDetector.resolve(
                isAlive: true,
                hookStatus: .blocked,
                hookUpdatedAt: Date(timeIntervalSince1970: 1),
                jsonlStatus: .working,
                jsonlUpdatedAt: Date(timeIntervalSince1970: 2),
                metaStatus: .working
            ),
            .working,
            "newer structured event clears stale hook"
        )
    }

    private static func testNormalEventsKeepExistingYellowAndGreenSemantics() {
        let userEvent: [String: Any] = ["type": "user", "message": ["content": "Continue"]]
        let toolUseEvent: [String: Any] = [
            "type": "assistant",
            "message": ["stop_reason": "tool_use"]
        ]
        let permissionEvent: [String: Any] = ["type": "system", "subtype": "permission_request"]

        expect(SessionStatusDetector.status(for: userEvent, isRecent: true), .thinking, "recent user event is yellow")
        expect(SessionStatusDetector.status(for: toolUseEvent, isRecent: true), .working, "tool use is green")
        expect(SessionStatusDetector.status(for: permissionEvent, isRecent: true), .blocked, "permission request is yellow")
    }

    private static func testSuccessfulEventClearsPreviousError() {
        let failedEvent = toolResultEvent(content: "bash: /root/secret: Permission denied", isError: true)
        let recoveredEvent: [String: Any] = [
            "type": "assistant",
            "message": ["stop_reason": "tool_use"]
        ]

        expect(SessionStatusDetector.status(for: failedEvent, isRecent: true), .error, "failure starts red")
        expect(SessionStatusDetector.status(for: recoveredEvent, isRecent: true), .working, "success clears red")
    }

    private static func testTrailingMetadataDoesNotHideError() {
        let lines = [
            "{\"type\":\"assistant\",\"isApiErrorMessage\":true,\"error\":\"authentication_failed\"}",
            "{\"type\":\"system\",\"subtype\":\"turn_duration\",\"isMeta\":true}"
        ]

        guard let event = SessionStatusDetector.latestEvent(in: lines) else {
            failureCount += 1
            print("FAIL: trailing metadata test found no status event")
            return
        }
        expect(SessionStatusDetector.status(for: event, isRecent: true), .error, "metadata does not hide red")
    }

    private static func testWordsAboutErrorsDoNotTurnRed() {
        let event: [String: Any] = [
            "type": "user",
            "message": ["content": "Please explain error handling and HTTP 500"]
        ]

        expect(SessionStatusDetector.status(for: event, isRecent: true), .thinking, "error words are not red")
    }

    private static func testNullErrorDoesNotTurnRed() {
        let event: [String: Any] = [
            "type": "user",
            "error": NSNull(),
            "message": ["content": "Continue"]
        ]

        expect(SessionStatusDetector.status(for: event, isRecent: true), .thinking, "null error is not red")
    }

    private static func expect(_ actual: SessionStatus?, _ expected: SessionStatus, _ name: String) {
        if actual != expected {
            failureCount += 1
            print("FAIL: \(name) — expected \(expected.rawValue), got \(actual?.rawValue ?? "nil")")
        }
    }

    private static func toolResultEvent(content: String, isError: Bool) -> [String: Any] {
        [
            "type": "user",
            "message": [
                "content": [[
                    "type": "tool_result",
                    "content": content,
                    "is_error": isError
                ]]
            ]
        ]
    }
}
