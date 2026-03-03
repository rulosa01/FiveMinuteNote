import XCTest
@testable import FiveMinuteNote

final class NoteStateTests: XCTestCase {

    var sut: NoteState!

    override func setUp() {
        super.setUp()
        sut = NoteState()
    }

    override func tearDown() {
        sut.clearNote()
        sut = nil
        super.tearDown()
    }

    // MARK: - 1.1 New Note Lifecycle

    func testStartNewNote_setsHasActiveNoteTrue() {
        sut.startNewNote()
        XCTAssertTrue(sut.hasActiveNote)
    }

    func testStartNewNote_setsTimeRemainingToDefaultDuration() {
        sut.startNewNote()
        // defaultDuration is 5 * 60 = 300s; allow small tolerance for execution time
        XCTAssertEqual(sut.timeRemaining, sut.defaultDuration, accuracy: 1.0)
    }

    func testStartNewNote_setsTextToEmpty() {
        sut.text = "some old text"
        sut.startNewNote()
        XCTAssertEqual(sut.text, "")
    }

    func testStartNewNote_setsDeadline() {
        sut.startNewNote()
        XCTAssertNotNil(sut.deadline)
        let expectedDeadline = Date().addingTimeInterval(sut.defaultDuration)
        XCTAssertEqual(sut.deadline!.timeIntervalSince1970, expectedDeadline.timeIntervalSince1970, accuracy: 1.0)
    }

    func testStartNewNote_whileAlreadyActive_resetsTimer() {
        sut.startNewNote()
        // Simulate some time passing by moving deadline back
        sut.deadline = Date().addingTimeInterval(100)
        sut.startNewNote()
        // After reset, should be back to ~300s
        XCTAssertEqual(sut.timeRemaining, sut.defaultDuration, accuracy: 1.0)
    }

    func testStartNewNote_clearsExistingText() {
        sut.startNewNote()
        sut.text = "some notes here"
        sut.startNewNote()
        XCTAssertEqual(sut.text, "")
    }

    // MARK: - 1.2 Timer Countdown

    func testTimeRemaining_neverGoesBelowZero() {
        sut.startNewNote()
        // Set deadline in the past
        sut.deadline = Date().addingTimeInterval(-10)
        // Manually trigger an update by calling onKeystroke path
        // timeRemaining should clamp to 0
        // Use extendTimer to trigger updateTimeRemaining indirectly... but deadline is in the past
        // Actually, the simplest way: just start a new note, set deadline to past, start another
        sut.startNewNote() // This calls updateTimeRemaining
        sut.deadline = Date().addingTimeInterval(-100)
        // Force an update via the public API
        sut.extendTimer() // adds 5 min to the past deadline; but what matters is the clamp
        // The deadline is now -100 + 300 = +200, so timeRemaining should be ~200, not negative
        // Let's test the clamp more directly
        let freshState = NoteState()
        freshState.startNewNote()
        freshState.deadline = Date().addingTimeInterval(-5)
        // Call a method that triggers updateTimeRemaining
        freshState.onKeystroke() // This resets timer, not ideal for testing clamp
        // Better: extend with a deadline so far in the past it stays negative
        let clampState = NoteState()
        clampState.startNewNote()
        clampState.deadline = Date().addingTimeInterval(-1000)
        // extendTimer adds 300s, so -1000 + 300 = -700, still negative
        clampState.extendTimer()
        XCTAssertEqual(clampState.timeRemaining, 0, accuracy: 0.01,
                       "timeRemaining should be clamped to 0 when deadline is in the past")
        clampState.clearNote()
    }

    func testTimerExpiry_postsNotification() {
        let expectation = expectation(forNotification: .noteDidExpire, object: nil)
        sut.startNewNote()
        // Set deadline to just barely in the future so the timer fires and expires quickly
        sut.deadline = Date().addingTimeInterval(0.1)
        // Wait for the notification
        wait(for: [expectation], timeout: 3.0)
        XCTAssertFalse(sut.hasActiveNote, "hasActiveNote should be false after expiry")
    }

    func testTimerExpiry_setsTimeRemainingToZero() {
        let expectation = expectation(forNotification: .noteDidExpire, object: nil)
        sut.startNewNote()
        sut.deadline = Date().addingTimeInterval(0.1)
        wait(for: [expectation], timeout: 3.0)
        XCTAssertEqual(sut.timeRemaining, 0, accuracy: 0.01)
    }

    func testTimerExpiry_stopsTimer() {
        let expiryExpectation = expectation(forNotification: .noteDidExpire, object: nil)
        sut.startNewNote()
        sut.deadline = Date().addingTimeInterval(0.1)
        wait(for: [expiryExpectation], timeout: 3.0)

        // After expiry, timeRemaining should stay at 0 (timer stopped)
        let beforeRemaining = sut.timeRemaining
        // Wait a moment and check it hasn't changed (i.e., timer isn't still running)
        let stableExpectation = expectation(description: "timeRemaining stays stable")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            stableExpectation.fulfill()
        }
        wait(for: [stableExpectation], timeout: 2.0)
        XCTAssertEqual(sut.timeRemaining, beforeRemaining, accuracy: 0.01)
    }

    func testTimerDecrementsOverTime() {
        sut.startNewNote()
        let initialRemaining = sut.timeRemaining

        let expectation = expectation(description: "Timer decrements")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)
        XCTAssertLessThan(sut.timeRemaining, initialRemaining,
                          "timeRemaining should decrease over time")
    }

    func testAdaptiveInterval_switchesToFasterNearExpiry() {
        sut.startNewNote()
        // Set deadline to 2 seconds from now (within 60s zone = 0.5s interval)
        sut.deadline = Date().addingTimeInterval(2.0)

        // The timer should tick at 0.5s interval in the final 60s
        // We verify by checking that it ticks more than once per second
        var tickCount = 0
        let observer = sut.$timeRemaining
            .dropFirst()
            .sink { _ in tickCount += 1 }

        let expectation = expectation(description: "Fast ticks")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)
        observer.cancel()

        // In 1.5 seconds at 0.5s intervals, we should get at least 2 ticks
        XCTAssertGreaterThanOrEqual(tickCount, 2,
                                     "Timer should tick at 0.5s intervals when <= 60s remaining")
    }

    // MARK: - 1.3 Timer Reset (Keystroke)

    func testOnKeystroke_resetsTimeRemainingWhenActive() {
        sut.startNewNote()
        // Simulate time passing by moving deadline closer
        sut.deadline = Date().addingTimeInterval(100)
        sut.onKeystroke()
        // After keystroke, should be back to ~300s
        XCTAssertEqual(sut.timeRemaining, sut.defaultDuration, accuracy: 1.0)
    }

    func testOnKeystroke_updatesDeadlineWhenActive() {
        sut.startNewNote()
        sut.deadline = Date().addingTimeInterval(100)
        let beforeKeystroke = sut.deadline!
        sut.onKeystroke()
        XCTAssertGreaterThan(sut.deadline!.timeIntervalSince1970, beforeKeystroke.timeIntervalSince1970)
    }

    func testOnKeystroke_isNoOpWhenNoActiveNote() {
        XCTAssertFalse(sut.hasActiveNote)
        sut.onKeystroke()
        XCTAssertEqual(sut.timeRemaining, 0)
        XCTAssertNil(sut.deadline)
    }

    func testOnKeystroke_doesNotChangeHasActiveNote() {
        sut.startNewNote()
        XCTAssertTrue(sut.hasActiveNote)
        sut.onKeystroke()
        XCTAssertTrue(sut.hasActiveNote)
    }

    // MARK: - 1.4 Timer Extension

    func testExtendTimer_adds5Minutes() {
        sut.startNewNote()
        let beforeDeadline = sut.deadline!
        sut.extendTimer()
        let expectedDeadline = beforeDeadline.addingTimeInterval(5 * 60)
        XCTAssertEqual(sut.deadline!.timeIntervalSince1970, expectedDeadline.timeIntervalSince1970, accuracy: 0.1)
    }

    func testExtendTimer_updatesTimeRemaining() {
        sut.startNewNote()
        let before = sut.timeRemaining
        sut.extendTimer()
        // Should now be ~600s (300 + 300)
        XCTAssertEqual(sut.timeRemaining, before + 300, accuracy: 1.0)
    }

    func testExtendTimer_capsAt24Hours() {
        sut.startNewNote()
        // Set deadline to 23h 58m from now
        sut.deadline = Date().addingTimeInterval(23 * 3600 + 58 * 60)
        sut.extendTimer() // adds 5 min → would be 24h03m, should clamp to 24h
        let maxDeadline = Date().addingTimeInterval(sut.maxTimerDuration)
        XCTAssertLessThanOrEqual(sut.deadline!.timeIntervalSince1970, maxDeadline.timeIntervalSince1970 + 1.0)
        XCTAssertEqual(sut.timeRemaining, sut.maxTimerDuration, accuracy: 2.0)
    }

    func testExtendTimer_multipleCallsAccumulateUpToCap() {
        sut.startNewNote()
        // Extend many times
        for _ in 0..<300 { // 300 * 5min = 1500min = 25h > 24h cap
            sut.extendTimer()
        }
        let maxDeadline = Date().addingTimeInterval(sut.maxTimerDuration)
        XCTAssertLessThanOrEqual(sut.deadline!.timeIntervalSince1970, maxDeadline.timeIntervalSince1970 + 1.0,
                                 "Deadline should never exceed 24 hours from now")
    }

    func testExtendTimer_pastCapClampsToExactly24h() {
        sut.startNewNote()
        // Set deadline to exactly 24h from now
        sut.deadline = Date().addingTimeInterval(sut.maxTimerDuration)
        sut.extendTimer() // Should not go beyond 24h
        let maxDeadline = Date().addingTimeInterval(sut.maxTimerDuration)
        XCTAssertLessThanOrEqual(sut.deadline!.timeIntervalSince1970, maxDeadline.timeIntervalSince1970 + 1.0)
    }

    func testExtendTimer_noOpWithoutDeadline() {
        // No active note, deadline is nil
        sut.extendTimer()
        XCTAssertNil(sut.deadline)
        XCTAssertEqual(sut.timeRemaining, 0)
    }

    // MARK: - 1.5 Note Destruction (clearNote)

    func testClearNote_setsHasActiveNoteFalse() {
        sut.startNewNote()
        sut.clearNote()
        XCTAssertFalse(sut.hasActiveNote)
    }

    func testClearNote_setsTextToEmpty() {
        sut.startNewNote()
        sut.text = "important stuff"
        sut.clearNote()
        XCTAssertEqual(sut.text, "")
    }

    func testClearNote_setsTimeRemainingToZero() {
        sut.startNewNote()
        sut.clearNote()
        XCTAssertEqual(sut.timeRemaining, 0)
    }

    func testClearNote_nillsDeadline() {
        sut.startNewNote()
        sut.clearNote()
        XCTAssertNil(sut.deadline)
    }

    func testClearNote_stopsTimer() {
        sut.startNewNote()
        sut.clearNote()

        // After clearing, timeRemaining should stay at 0
        let expectation = expectation(description: "Stable after clear")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)
        XCTAssertEqual(sut.timeRemaining, 0, accuracy: 0.01)
    }

    func testClearNote_isIdempotent() {
        sut.startNewNote()
        sut.clearNote()
        sut.clearNote() // Should not crash
        XCTAssertFalse(sut.hasActiveNote)
        XCTAssertEqual(sut.timeRemaining, 0)
    }

    // MARK: - 1.6 Text Content

    func testTextStoresValue() {
        sut.text = "hello world"
        XCTAssertEqual(sut.text, "hello world")
    }

    func testDefaultDuration_isFiveMinutes() {
        XCTAssertEqual(sut.defaultDuration, 300.0)
    }

    // MARK: - 1.7 Singleton

    func testShared_returnsSameInstance() {
        let a = NoteState.shared
        let b = NoteState.shared
        XCTAssertTrue(a === b)
    }

    func testFreshInstanceIsIndependent() {
        let a = NoteState()
        let b = NoteState()
        a.startNewNote()
        a.text = "only in a"
        XCTAssertFalse(b.hasActiveNote)
        XCTAssertEqual(b.text, "")
        a.clearNote()
    }

    // MARK: - Initial State

    func testInitialState_hasNoActiveNote() {
        XCTAssertFalse(sut.hasActiveNote)
    }

    func testInitialState_timeRemainingIsZero() {
        XCTAssertEqual(sut.timeRemaining, 0)
    }

    func testInitialState_textIsEmpty() {
        XCTAssertEqual(sut.text, "")
    }

    func testInitialState_deadlineIsNil() {
        XCTAssertNil(sut.deadline)
    }

    // MARK: - Date-based Timer Accuracy

    func testTimerUsesDateBasedCalculation() {
        sut.startNewNote()
        let deadline = sut.deadline!
        // Wait briefly, then check that timeRemaining matches deadline - now
        let expectation = expectation(description: "Check date-based")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
        let expected = deadline.timeIntervalSinceNow
        // timeRemaining should closely match the date-based calculation
        XCTAssertEqual(sut.timeRemaining, expected, accuracy: 1.0,
                       "timeRemaining should be computed from deadline, not decremented")
    }

    // MARK: - Full Lifecycle Integration

    func testFullLifecycle_startTypeClearRestart() {
        // Start a note
        sut.startNewNote()
        XCTAssertTrue(sut.hasActiveNote)
        XCTAssertEqual(sut.timeRemaining, sut.defaultDuration, accuracy: 1.0)

        // Type (sets text, triggers keystroke)
        sut.text = "some notes"
        sut.onKeystroke()
        XCTAssertEqual(sut.text, "some notes")
        XCTAssertEqual(sut.timeRemaining, sut.defaultDuration, accuracy: 1.0)

        // Clear
        sut.clearNote()
        XCTAssertFalse(sut.hasActiveNote)
        XCTAssertEqual(sut.text, "")
        XCTAssertEqual(sut.timeRemaining, 0)

        // Start a new note
        sut.startNewNote()
        XCTAssertTrue(sut.hasActiveNote)
        XCTAssertEqual(sut.text, "")
        XCTAssertEqual(sut.timeRemaining, sut.defaultDuration, accuracy: 1.0)
    }
}
