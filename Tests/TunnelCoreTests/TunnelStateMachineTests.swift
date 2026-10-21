import Foundation
import Testing
@testable import TunnelCore

private let now = Date(timeIntervalSince1970: 1_000_000)

private func reduce(_ phase: TunnelPhase, _ event: TunnelEvent) -> (TunnelStatus, [TunnelEffect]) {
    var status = TunnelStatus(phase: phase)
    let effects = TunnelStateMachine.reduce(&status, event, now: now)
    return (status, effects)
}

@Test(arguments: [TunnelPhase.stopped, .failed(.authenticationFailed)])
func startLaunches(from phase: TunnelPhase) {
    let (status, effects) = reduce(phase, .start)
    #expect(status.phase == .connecting(attempt: 0))
    #expect(effects == [.launch])
}

@Test func listeningForwardsMeanConnected() {
    let (status, effects) = reduce(.connecting(attempt: 2), .forwardsListening)
    #expect(status.phase == .connected(since: now))
    #expect(effects == [])
}

@Test func retryableFailureOnManualStartSchedulesRetryWithoutNotifying() {
    let (status, effects) = reduce(.connecting(attempt: 0), .processExited(.timedOut))
    #expect(status.phase == .reconnecting(attempt: 1, retryAt: now.addingTimeInterval(2)))
    #expect(effects == [.scheduleRetry(after: .seconds(2))])
}

@Test func firstReconnectFailureNotifies() {
    let (status, effects) = reduce(.connecting(attempt: 1), .processExited(.timedOut))
    #expect(status.phase == .reconnecting(attempt: 2, retryAt: now.addingTimeInterval(4)))
    #expect(effects == [.scheduleRetry(after: .seconds(4)), .notify(.timedOut)])
}

@Test func laterReconnectFailuresDoNotNotifyAgain() {
    let (_, effects) = reduce(.connecting(attempt: 3), .processExited(.timedOut))
    #expect(effects == [.scheduleRetry(after: .seconds(16))])
}

@Test func nonRetryableFailureOnManualStartFailsSilently() {
    let (status, effects) = reduce(.connecting(attempt: 0), .processExited(.authenticationFailed))
    #expect(status.phase == .failed(.authenticationFailed))
    #expect(effects == [])
}

@Test func nonRetryableFailureDuringReconnectNotifies() {
    let (status, effects) = reduce(.connecting(attempt: 2), .processExited(.hostKeyChanged))
    #expect(status.phase == .failed(.hostKeyChanged))
    #expect(effects == [.notify(.hostKeyChanged)])
}

@Test func droppedConnectionRelaunchesImmediately() {
    let (status, effects) = reduce(.connected(since: now), .processExited(.connectionLost))
    #expect(status.phase == .connecting(attempt: 1))
    #expect(status.reconnectCount == 1)
    #expect(status.lastDisconnect == Disconnect(at: now, reason: .connectionLost))
    #expect(effects == [.launch])
}

@Test func nonRetryableDropFailsAndNotifies() {
    let (status, effects) = reduce(.connected(since: now), .processExited(.hostKeyChanged))
    #expect(status.phase == .failed(.hostKeyChanged))
    #expect(status.reconnectCount == 1)
    #expect(status.lastDisconnect == Disconnect(at: now, reason: .hostKeyChanged))
    #expect(effects == [.notify(.hostKeyChanged)])
}

@Test func retryDueLaunches() {
    let (status, effects) = reduce(.reconnecting(attempt: 3, retryAt: now), .retryDue)
    #expect(status.phase == .connecting(attempt: 3))
    #expect(effects == [.launch])
}

@Test func networkChangeSkipsTheWait() {
    let (status, effects) = reduce(.reconnecting(attempt: 3, retryAt: now.addingTimeInterval(30)), .networkChanged)
    #expect(status.phase == .connecting(attempt: 3))
    #expect(effects == [.cancelRetry, .launch])
}

@Test(arguments: [
    TunnelPhase.connecting(attempt: 0), .connected(since: now), .reconnecting(attempt: 2, retryAt: now),
])
func stopTerminates(from phase: TunnelPhase) {
    let (status, effects) = reduce(phase, .stop)
    #expect(status.phase == .stopped)
    #expect(effects == [.terminate, .cancelRetry])
}

@Test(arguments: [TunnelEvent.processExited(.connectionLost), .retryDue, .networkChanged, .forwardsListening])
func stoppedIgnoresLateEvents(event: TunnelEvent) {
    let (status, effects) = reduce(.stopped, event)
    #expect(status.phase == .stopped)
    #expect(effects == [])
}

@Test func lastFailureTracksTheCurrentOutage() {
    var status = TunnelStatus(phase: .connecting(attempt: 1))
    _ = TunnelStateMachine.reduce(&status, .processExited(.timedOut), now: now)
    #expect(status.lastFailure == .timedOut)
    _ = TunnelStateMachine.reduce(&status, .retryDue, now: now)
    _ = TunnelStateMachine.reduce(&status, .forwardsListening, now: now)
    #expect(status.lastFailure == nil)
    _ = TunnelStateMachine.reduce(&status, .processExited(.connectionLost), now: now)
    #expect(status.lastFailure == .connectionLost)
}

@Test func reconnectDelays() {
    #expect((1...7).map(ReconnectPolicy.delay(forAttempt:)) == [2, 4, 8, 16, 30, 30, 30].map { Duration.seconds($0) })
}
