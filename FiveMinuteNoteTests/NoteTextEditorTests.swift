import XCTest
import AppKit
import SwiftUI
@testable import FiveMinuteNote

final class NoteTextEditorCoordinatorTests: XCTestCase {

    var textView: NSTextView!
    var coordinator: NoteTextEditor.Coordinator!
    var boundText: String = ""

    override func setUp() {
        super.setUp()
        boundText = ""
        let binding = Binding<String>(
            get: { self.boundText },
            set: { self.boundText = $0 }
        )
        let editor = NoteTextEditor(text: binding, onKeystroke: {})
        coordinator = editor.makeCoordinator()
        textView = NSTextView()
        textView.string = ""
    }

    override func tearDown() {
        textView = nil
        coordinator = nil
        super.tearDown()
    }

    // MARK: - Character Limit (100K)

    func testShouldChangeText_allowsNormalInput() {
        textView.string = "hello"
        let result = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 5, length: 0),
            replacementString: " world"
        )
        XCTAssertTrue(result)
    }

    func testShouldChangeText_allowsInputUpToLimit() {
        // Fill to exactly 100,000 - 1 characters
        textView.string = String(repeating: "a", count: 99_999)
        let result = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 99_999, length: 0),
            replacementString: "b"
        )
        XCTAssertTrue(result, "Should allow typing up to exactly 100K characters")
    }

    func testShouldChangeText_rejectsInputBeyondLimit() {
        // Fill to exactly 100,000 characters
        textView.string = String(repeating: "a", count: 100_000)
        let result = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 100_000, length: 0),
            replacementString: "b"
        )
        XCTAssertFalse(result, "Should reject input beyond 100K characters")
    }

    func testShouldChangeText_allowsReplacementWithinLimit() {
        textView.string = String(repeating: "a", count: 100_000)
        // Replace 5 characters with 5 characters — net zero, should be allowed
        let result = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 0, length: 5),
            replacementString: "bbbbb"
        )
        XCTAssertTrue(result, "Replacing same-length text at limit should be allowed")
    }

    func testShouldChangeText_allowsDeletionAtLimit() {
        textView.string = String(repeating: "a", count: 100_000)
        // Delete 10 characters
        let result = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 0, length: 10),
            replacementString: ""
        )
        XCTAssertTrue(result, "Deletion should always be allowed")
    }

    func testShouldChangeText_rejectsPasteThatExceedsLimit() {
        textView.string = String(repeating: "a", count: 99_990)
        // Paste 20 characters — would be 100,010, exceeds limit
        let result = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 99_990, length: 0),
            replacementString: String(repeating: "b", count: 20)
        )
        XCTAssertFalse(result, "Paste that exceeds 100K should be rejected")
    }

    func testShouldChangeText_allowsPasteExactlyToLimit() {
        textView.string = String(repeating: "a", count: 99_990)
        // Paste 10 characters — would be exactly 100,000
        let result = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 99_990, length: 0),
            replacementString: String(repeating: "b", count: 10)
        )
        XCTAssertTrue(result, "Paste that brings total to exactly 100K should be allowed")
    }

    func testShouldChangeText_replacementShorterAllowed() {
        textView.string = String(repeating: "a", count: 100_000)
        // Replace 10 characters with 5 — net -5, total 99,995
        let result = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 0, length: 10),
            replacementString: "bbbbb"
        )
        XCTAssertTrue(result, "Replacing with shorter text should always be allowed")
    }

    func testShouldChangeText_allowsNilReplacement() {
        textView.string = "hello"
        let result = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 0, length: 5),
            replacementString: nil
        )
        XCTAssertTrue(result, "Nil replacement string should be allowed (attribute changes)")
    }

    // MARK: - UTF-16 Counting (NSString length)

    func testShouldChangeText_usesUTF16LengthNotGraphemeClusters() {
        // Emoji like 👨‍👩‍👧‍👦 is 1 grapheme cluster but 11 UTF-16 code units
        let family = "👨‍👩‍👧‍👦"
        let familyUTF16Count = (family as NSString).length
        XCTAssertGreaterThan(familyUTF16Count, 1, "Sanity: family emoji should be >1 UTF-16 unit")

        // Fill near limit, accounting for UTF-16 size
        let remaining = 100_000 - familyUTF16Count
        textView.string = String(repeating: "a", count: remaining)

        // This emoji should fit exactly
        let resultFits = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: remaining, length: 0),
            replacementString: family
        )
        XCTAssertTrue(resultFits, "Emoji that fits within UTF-16 limit should be allowed")

        // Now fill to exactly the limit
        textView.string = String(repeating: "a", count: 100_000)
        // Adding the emoji should exceed the limit
        let resultExceeds = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 100_000, length: 0),
            replacementString: family
        )
        XCTAssertFalse(resultExceeds, "Emoji that would exceed UTF-16 limit should be rejected")
    }

    func testShouldChangeText_emptyString_allowsInput() {
        textView.string = ""
        let result = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 0, length: 0),
            replacementString: "hello"
        )
        XCTAssertTrue(result)
    }

    // MARK: - Coordinator Flag

    func testCoordinator_initialFlagIsFalse() {
        XCTAssertFalse(coordinator.isUpdatingFromTextView)
    }
}
