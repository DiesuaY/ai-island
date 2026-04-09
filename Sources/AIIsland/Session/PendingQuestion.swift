public struct PendingQuestion {
    public let sessionId: String
    public let question: String
    public let options: [String]
    /// When true, the response should be sent as a keystroke to the terminal
    /// (for AskUserQuestion intercepted from tool_use hooks, which are fire-and-forget).
    public let respondViaKeystroke: Bool

    public init(sessionId: String, question: String, options: [String], respondViaKeystroke: Bool = false) {
        self.sessionId = sessionId
        self.question = question
        self.options = options
        self.respondViaKeystroke = respondViaKeystroke
    }
}
