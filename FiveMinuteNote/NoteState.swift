import SwiftUI
import Combine

class NoteState: ObservableObject {
    static let shared = NoteState()

    @Published var text: String = ""
    @Published var timeRemaining: Double = 0
    @Published var hasActiveNote: Bool = false

    private var timer: Timer?
    // #3: Date-based timer — record when the deadline is, compute remaining on each tick
    // internal for testability
    var deadline: Date?
    let maxTimerDuration: Double = 24 * 60 * 60 // 24 hours

    // internal (not private) so the test target can create isolated instances
    init() {}

    var defaultDuration: Double {
        Double(defaultTimerMinutes * 60)
    }

    func startNewNote() {
        text = ""
        deadline = Date().addingTimeInterval(defaultDuration)
        hasActiveNote = true
        updateTimeRemaining()
        startTimer()
    }

    func clearNote() {
        text = ""
        timeRemaining = 0
        deadline = nil
        hasActiveNote = false
        stopTimer()
    }

    func resetTimer() {
        deadline = Date().addingTimeInterval(defaultDuration)
        updateTimeRemaining()
    }

    func extendTimer() {
        guard let current = deadline else { return }
        let newDeadline = current.addingTimeInterval(5 * 60)
        let maxDeadline = Date().addingTimeInterval(maxTimerDuration)
        deadline = min(newDeadline, maxDeadline)
        updateTimeRemaining()
    }

    func onKeystroke() {
        if hasActiveNote {
            resetTimer()
        }
    }

    private func updateTimeRemaining() {
        guard let deadline = deadline else {
            timeRemaining = 0
            return
        }
        timeRemaining = max(0, deadline.timeIntervalSinceNow)
    }

    // #2: Adaptive timer interval — 1s normally, 0.5s in final 60s for smooth pie
    private func startTimer() {
        stopTimer()
        scheduleTimer()
    }

    private func scheduleTimer() {
        let interval: Double = timeRemaining <= 60 ? 0.5 : 1.0
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateTimeRemaining()

            // Switch to faster interval when entering pie animation zone
            if self.timeRemaining <= 60 && self.timeRemaining > 0 && interval != 0.5 {
                self.stopTimer()
                self.scheduleTimer()
                return
            }

            if self.timeRemaining <= 0 {
                self.timeRemaining = 0
                self.onTimerExpired()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func onTimerExpired() {
        stopTimer()
        hasActiveNote = false
        // Post notification so the app delegate can handle window closure
        NotificationCenter.default.post(name: .noteDidExpire, object: nil)
    }
}

extension Notification.Name {
    static let noteDidExpire = Notification.Name("noteDidExpire")
}
