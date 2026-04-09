import AIIslandProtocol

public struct PendingPermission {
    public let sessionId: String
    public let toolName: String
    public let command: String?
    public let filePath: String?
    public let diff: String?
    /// Permission suggestions from Claude Code (e.g., "Always allow Read", "Allow for this session").
    public let suggestedUpdates: [ClaudePermissionUpdate]
    /// The raw tool input, preserved for sending back updatedInput if needed.
    public let toolInput: HookJSONValue?
    /// Claude's tool_use_id for this permission request.
    public let toolUseID: String?

    public init(
        sessionId: String,
        toolName: String,
        command: String? = nil,
        filePath: String? = nil,
        diff: String? = nil,
        suggestedUpdates: [ClaudePermissionUpdate] = [],
        toolInput: HookJSONValue? = nil,
        toolUseID: String? = nil
    ) {
        self.sessionId = sessionId
        self.toolName = toolName
        self.command = command
        self.filePath = filePath
        self.diff = diff
        self.suggestedUpdates = suggestedUpdates
        self.toolInput = toolInput
        self.toolUseID = toolUseID
    }
}
