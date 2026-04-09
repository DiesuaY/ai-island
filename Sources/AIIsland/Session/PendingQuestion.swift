public struct PendingQuestion {
    public let sessionId: String
    public let question: String
    public let options: [String]

    public init(sessionId: String, question: String, options: [String]) {
        self.sessionId = sessionId
        self.question = question
        self.options = options
    }
}
