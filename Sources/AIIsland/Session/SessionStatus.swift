import SwiftUI

public enum SessionStatus: String, Sendable {
    case working
    case idle
    case waitingApproval
    case waitingAnswer
    case error
    case done

    var color: Color {
        switch self {
        case .working:          return .blue
        case .idle:             return .green
        case .waitingApproval:  return DesignTokens.accent
        case .waitingAnswer:    return DesignTokens.accent
        case .error:            return .red
        case .done:             return .green
        }
    }

    var label: String {
        switch self {
        case .working:          return "Working"
        case .idle:             return "Idle"
        case .waitingApproval:  return "Waiting Approval"
        case .waitingAnswer:    return "Waiting Answer"
        case .error:            return "Error"
        case .done:             return "Done"
        }
    }
}
