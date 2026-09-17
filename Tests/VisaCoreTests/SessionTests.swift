import Foundation
import VisaCore

final class SessionTests {
    let now = Date(timeIntervalSince1970: 1_000)

    func testFirstLaunchRequiresAuthenticatedSetup() {
        var session = Session(snapshot: .init(), now: now)
        expectEqual(session.mode, .setup)
        session.enterParent(authenticated: false, now: now)
        session.completeSetup()
        expectEqual(session.mode, .setup)
        session.enterParent(authenticated: true, now: now)
        session.completeSetup()
        expectEqual(session.mode, .lock)
        expectTrue(session.snapshot.configured)
    }

    func testChildCannotGrantTimeOrUnlockWithoutAuthentication() {
        var session = Session(snapshot: .init(configured: true), now: now)
        session.grant(seconds: 60, now: now)
        session.enterParent(authenticated: false, now: now)
        expectEqual(session.mode, .lock)
        expectNil(session.snapshot.endsAt)
        expectFalse(session.allowsExit)
    }

    func testAbsoluteExpiryAndRelaunch() {
        var session = Session(snapshot: .init(configured: true), now: now)
        session.enterParent(authenticated: true, now: now)
        session.grant(seconds: 60, now: now)
        expectEqual(session.snapshot.endsAt, now.addingTimeInterval(60))
        expectEqual(session.mode, .play)
        let restored = Session(snapshot: session.snapshot, now: now.addingTimeInterval(25))
        expectEqual(restored.mode, .play)
        expectEqual(restored.remaining(at: now.addingTimeInterval(25)), 35)
        let expired = Session(snapshot: session.snapshot, now: now.addingTimeInterval(60))
        expectEqual(expired.mode, .lock)
        expectNil(expired.snapshot.endsAt)
        session.tick(now: now.addingTimeInterval(100))
        expectEqual(session.mode, .lock)
    }

    func testParentRoundTripPreservesVisaButNeverPersistsUnlock() {
        var session = Session(snapshot: .init(configured: true, endsAt: now.addingTimeInterval(60)), now: now)
        session.enterParent(authenticated: true, now: now)
        expectTrue(session.allowsExit)
        expectEqual(Session(snapshot: session.snapshot, now: now).mode, .play)
        session.leaveParent(now: now.addingTimeInterval(10))
        expectEqual(session.remaining(at: now.addingTimeInterval(10)), 50)
        expectFalse(session.allowsExit)
        session.enterParent(authenticated: true, now: now)
        session.tick(now: now.addingTimeInterval(60))
        expectEqual(session.mode, .parent)
        session.leaveParent(now: now.addingTimeInterval(60))
        expectEqual(session.mode, .lock)
    }

    func testInvalidGrantAndUnconfiguredVisaFailClosed() {
        var session = Session(snapshot: .init(endsAt: now.addingTimeInterval(60)), now: now)
        expectNil(session.snapshot.endsAt)
        session.enterParent(authenticated: true, now: now)
        session.grant(seconds: 60, now: now)
        expectNil(session.snapshot.endsAt)
        session.completeSetup()
        session.enterParent(authenticated: true, now: now)
        for value in [0.0, -1, Double.infinity, Double.nan] {
            session.grant(seconds: value, now: now)
            expectNil(session.snapshot.endsAt)
        }
    }

    func testEscapePolicyInEveryMode() {
        var session = Session(snapshot: .init(), now: now)
        for configured in [false, true] {
            session = Session(snapshot: .init(configured: configured), now: now)
            expectTrue(session.blocksKey(isEscape: true, hasCommand: false))
            expectTrue(session.blocksKey(isEscape: false, hasCommand: true))
            expectFalse(session.blocksKey(isEscape: false, hasCommand: false))
            expectFalse(session.allowsExit)
        }
        session.enterParent(authenticated: true, now: now)
        expectFalse(session.blocksKey(isEscape: true, hasCommand: true))
        expectTrue(session.allowsExit)
        session.grant(seconds: 60, now: now)
        expectTrue(session.blocksKey(isEscape: true, hasCommand: true))
        expectFalse(session.allowsExit)
    }

    func testAtomicPersistenceRoundTripAndCorruptFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnapshotStore(url: directory.appendingPathComponent("state.json"))
        expectEqual(try store.load(), Snapshot())
        let snapshot = Snapshot(configured: true, endsAt: now.addingTimeInterval(60))
        try store.save(snapshot)
        expectEqual(try store.load(), snapshot)
        try Data("broken".utf8).write(to: store.url)
        expectThrowsError(try store.load())
        try Data("{\"schemaVersion\":99,\"configured\":true}".utf8).write(to: store.url)
        expectThrowsError(try store.load())
    }
}

// A dependency-free runner supports Macs with Command Line Tools only.
func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    precondition(lhs == rhs, "Expected \(rhs), got \(lhs)", file: file, line: line)
}
func expectTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(value, "Expected true", file: file, line: line)
}
func expectFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(!value, "Expected false", file: file, line: line)
}
func expectNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
    precondition(value == nil, "Expected nil", file: file, line: line)
}
func expectThrowsError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) {
    do {
        _ = try expression()
        preconditionFailure("Expected an error", file: file, line: line)
    } catch {}
}

@main
struct TestRunner {
    static func main() throws {
        let tests = SessionTests()
        tests.testFirstLaunchRequiresAuthenticatedSetup()
        tests.testChildCannotGrantTimeOrUnlockWithoutAuthentication()
        tests.testAbsoluteExpiryAndRelaunch()
        tests.testParentRoundTripPreservesVisaButNeverPersistsUnlock()
        tests.testInvalidGrantAndUnconfiguredVisaFailClosed()
        tests.testEscapePolicyInEveryMode()
        try tests.testAtomicPersistenceRoundTripAndCorruptFile()
        print("PASS: 7 state, timer, authentication-boundary and persistence tests")
    }
}
