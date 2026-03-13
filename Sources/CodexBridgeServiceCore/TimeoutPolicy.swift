import Foundation

public struct TimeoutPolicy: Sendable {
    public let startup: TimeInterval
    public let prompt: TimeInterval
    public let toolExecution: TimeInterval
    public let approval: TimeInterval
    public let childSilence: TimeInterval
    public let idleTeardown: TimeInterval

    public init(
        startup: TimeInterval = 5,
        prompt: TimeInterval = 60,
        toolExecution: TimeInterval = 30,
        approval: TimeInterval = 60,
        childSilence: TimeInterval = 60,
        idleTeardown: TimeInterval = 90
    ) {
        self.startup = startup
        self.prompt = prompt
        self.toolExecution = toolExecution
        self.approval = approval
        self.childSilence = childSilence
        self.idleTeardown = idleTeardown
    }
}
