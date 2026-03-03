import XCTest
import SwiftUI
@testable import FiveMinuteNote

final class TimerViewTests: XCTestCase {

    // MARK: - Timer Text Formatting

    func testTimerText_fiveMinutes() {
        let view = TimerView(timeRemaining: 300, onExtend: {})
        XCTAssertEqual(view.timerText, "5:00")
    }

    func testTimerText_fourMinutesTwentyThreeSeconds() {
        let view = TimerView(timeRemaining: 263, onExtend: {})
        XCTAssertEqual(view.timerText, "4:23")
    }

    func testTimerText_oneMinute() {
        let view = TimerView(timeRemaining: 60, onExtend: {})
        XCTAssertEqual(view.timerText, "1:00")
    }

    func testTimerText_thirtySeconds() {
        let view = TimerView(timeRemaining: 30, onExtend: {})
        XCTAssertEqual(view.timerText, "0:30")
    }

    func testTimerText_oneSecond() {
        let view = TimerView(timeRemaining: 1, onExtend: {})
        XCTAssertEqual(view.timerText, "0:01")
    }

    func testTimerText_zero() {
        let view = TimerView(timeRemaining: 0, onExtend: {})
        XCTAssertEqual(view.timerText, "0:00")
    }

    func testTimerText_fractionalSecondRoundsUp() {
        // 4.3 seconds → ceil → 5 → "0:05"
        let view = TimerView(timeRemaining: 4.3, onExtend: {})
        XCTAssertEqual(view.timerText, "0:05")
    }

    func testTimerText_justUnderOneMinute() {
        let view = TimerView(timeRemaining: 59.9, onExtend: {})
        XCTAssertEqual(view.timerText, "1:00") // ceil(59.9) = 60
    }

    func testTimerText_negativeClampedToZero() {
        let view = TimerView(timeRemaining: -5, onExtend: {})
        XCTAssertEqual(view.timerText, "0:00")
    }

    func testTimerText_tenMinutes() {
        let view = TimerView(timeRemaining: 600, onExtend: {})
        XCTAssertEqual(view.timerText, "10:00")
    }

    func testTimerText_oneHour() {
        let view = TimerView(timeRemaining: 3600, onExtend: {})
        XCTAssertEqual(view.timerText, "60:00")
    }

    func testTimerText_singleDigitSecondsPadded() {
        let view = TimerView(timeRemaining: 65, onExtend: {})
        XCTAssertEqual(view.timerText, "1:05")
    }

    // MARK: - Timer Color

    func testTimerColor_moreThan60s_isSecondary() {
        let view = TimerView(timeRemaining: 120, onExtend: {})
        XCTAssertEqual(view.timerColor, .secondary)
    }

    func testTimerColor_exactly61s_isSecondary() {
        let view = TimerView(timeRemaining: 61, onExtend: {})
        XCTAssertEqual(view.timerColor, .secondary)
    }

    func testTimerColor_exactly60s_isOrange() {
        let view = TimerView(timeRemaining: 60, onExtend: {})
        XCTAssertEqual(view.timerColor, .orange)
    }

    func testTimerColor_30s_isOrange() {
        let view = TimerView(timeRemaining: 30, onExtend: {})
        XCTAssertEqual(view.timerColor, .orange)
    }

    func testTimerColor_16s_isOrange() {
        let view = TimerView(timeRemaining: 16, onExtend: {})
        XCTAssertEqual(view.timerColor, .orange)
    }

    func testTimerColor_exactly15s_isRed() {
        let view = TimerView(timeRemaining: 15, onExtend: {})
        XCTAssertEqual(view.timerColor, .red)
    }

    func testTimerColor_5s_isRed() {
        let view = TimerView(timeRemaining: 5, onExtend: {})
        XCTAssertEqual(view.timerColor, .red)
    }

    func testTimerColor_1s_isRed() {
        let view = TimerView(timeRemaining: 1, onExtend: {})
        XCTAssertEqual(view.timerColor, .red)
    }

    func testTimerColor_zero_isRed() {
        let view = TimerView(timeRemaining: 0, onExtend: {})
        XCTAssertEqual(view.timerColor, .red)
    }

    // MARK: - Boundary Transitions

    func testColorBoundary_60to59_changesFromSecondaryToOrange() {
        let at60 = TimerView(timeRemaining: 60, onExtend: {})
        let at61 = TimerView(timeRemaining: 60.01, onExtend: {})
        XCTAssertEqual(at60.timerColor, .orange)
        XCTAssertEqual(at61.timerColor, .secondary)
    }

    func testColorBoundary_15to14_changesFromOrangeToRed() {
        let at16 = TimerView(timeRemaining: 15.01, onExtend: {})
        let at15 = TimerView(timeRemaining: 15, onExtend: {})
        XCTAssertEqual(at16.timerColor, .orange)
        XCTAssertEqual(at15.timerColor, .red)
    }
}
