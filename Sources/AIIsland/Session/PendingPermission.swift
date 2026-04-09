public struct PendingPermission {
    public let sessionId: String
    public let toolName: String
    public let command: String?
    public let filePath: String?
    public let diff: String?

    public init(
        sessionId: String,
        toolName: String,
        command: String? = nil,
        filePath: String? = nil,
        diff: String? = nil
    ) {
        self.sessionId = sessionId
        self.toolName = toolName
        self.command = command
        self.filePath = filePath
        self.diff = diff
    }
}
