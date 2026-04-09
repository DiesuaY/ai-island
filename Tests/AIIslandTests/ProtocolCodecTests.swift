#if canImport(XCTest)
import XCTest
@testable import AIIslandProtocol

final class ProtocolCodecTests: XCTestCase {
    func testBridgeCommandRoundTrip() throws {
        let payload = ClaudeHookPayload(
            cwd: "/test",
            hookEventName: .preToolUse,
            sessionID: "test-session-123",
            toolName: "Read"
        )
        let command = BridgeCommand.processClaudeHook(payload)
        let data = try BridgeCodec.encodeCommand(command)
        XCTAssertTrue(data.count > 0)

        // Strip trailing newline for decode
        let trimmed = data.dropLast()
        let decoded = try BridgeCodec.decodeCommand(from: Data(trimmed))
        XCTAssertEqual(decoded, command)
    }

    func testBridgeResponseRoundTrip() throws {
        let decision = ClaudePermissionRequestDecision.allow(
            updatedPermissions: [
                .addRules(
                    destination: .session,
                    rules: [ClaudePermissionRuleValue(toolName: "Read")],
                    behavior: .allow
                )
            ]
        )
        let directive = ClaudeHookDirective.permissionRequest(decision)
        let response = BridgeResponse.claudeHookDirective(directive)
        let data = try BridgeCodec.encodeResponse(response)
        XCTAssertTrue(data.count > 0)

        let trimmed = data.dropLast()
        let decoded = try BridgeCodec.decodeResponse(from: Data(trimmed))
        XCTAssertEqual(decoded, response)
    }

    func testHookOutputEncoderPermissionRequest() throws {
        let decision = ClaudePermissionRequestDecision.allow()
        let directive = ClaudeHookDirective.permissionRequest(decision)
        let output = try ClaudeHookOutputEncoder.standardOutput(for: directive)
        XCTAssertNotNil(output)

        // Verify the output contains expected fields
        let json = try JSONSerialization.jsonObject(with: output!) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["continue"] as? Bool, true)
        XCTAssertEqual(json?["suppressOutput"] as? Bool, true)
        let hookOutput = json?["hookSpecificOutput"] as? [String: Any]
        XCTAssertEqual(hookOutput?["hookEventName"] as? String, "PermissionRequest")
    }

    func testClaudeHookPayloadDecode() throws {
        let json = """
        {
            "cwd": "/Users/test/project",
            "hook_event_name": "PermissionRequest",
            "session_id": "abc-123",
            "tool_name": "Bash",
            "tool_input": {"command": "ls -la"},
            "permission_mode": "default",
            "permission_suggestions": [
                {
                    "type": "addRules",
                    "destination": "session",
                    "rules": [{"toolName": "Bash"}],
                    "behavior": "allow"
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let payload = try JSONDecoder().decode(ClaudeHookPayload.self, from: data)
        XCTAssertEqual(payload.hookEventName, .permissionRequest)
        XCTAssertEqual(payload.toolName, "Bash")
        XCTAssertEqual(payload.toolInputCommand, "ls -la")
        XCTAssertEqual(payload.permissionSuggestions?.count, 1)
    }

    func testPermissionUpdateDisplayLabel() {
        let update = ClaudePermissionUpdate.addRules(
            destination: .session,
            rules: [ClaudePermissionRuleValue(toolName: "Bash")],
            behavior: .allow
        )
        XCTAssertEqual(update.displayLabel, "Always allow Bash for this session")
    }
}
#endif
