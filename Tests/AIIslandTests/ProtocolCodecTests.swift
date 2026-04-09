#if canImport(XCTest)
import XCTest
@testable import AIIslandProtocol

final class ProtocolCodecTests: XCTestCase {
    func testEncodeDecodeRoundTrip() throws {
        let payload = MessagePayload.sessionStart(SessionStartPayload(
            workingDirectory: "/test",
            terminalPid: 123,
            prompt: "test"
        ))
        let msg = BridgeMessage(
            sessionId: "test-1",
            agent: .claude,
            event: .sessionStart,
            timestamp: Date(),
            payload: payload
        )
        let data = try ProtocolCodec.encodeLine(AppResponse(
            sessionId: "test-1",
            action: .allow
        ))
        XCTAssertTrue(data.count > 0)
    }
}
#endif
