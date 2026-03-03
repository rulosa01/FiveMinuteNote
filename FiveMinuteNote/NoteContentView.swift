import SwiftUI

struct NoteContentView: View {
    @EnvironmentObject var noteState: NoteState
    @State private var isHovering = false
    var onClose: () -> Void
    var onNoteDied: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Main content
            VStack(spacing: 0) {
                // Text editor
                NoteTextEditor(text: $noteState.text, onKeystroke: {
                    noteState.onKeystroke()
                })
                .padding(.top, 28)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

                // Bottom bar with destroy button and timer
                HStack {
                    Button(action: onNoteDied) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.secondary.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    TimerView(
                        timeRemaining: noteState.timeRemaining,
                        onExtend: { noteState.extendTimer() }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            // Close button (appears on hover) — pinned to true top-left
            if isHovering {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 8)
                .padding(.leading, 8)
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 300, minHeight: 200)
        .background(Color(nsColor: .windowBackgroundColor))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .noteDidExpire)) { _ in
            onNoteDied()
        }
    }
}

// MARK: - Text Editor
struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onKeystroke: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: 4)

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay

        // Make text view the first responder after a brief delay
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    // #6: Skip comparison when the change originated from the text view itself
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard !context.coordinator.isUpdatingFromTextView else { return }
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextEditor
        private let maxCharacters = 100_000
        // #6: Flag to skip updateNSView when we're the source of the change
        var isUpdatingFromTextView = false

        init(_ parent: NoteTextEditor) {
            self.parent = parent
        }

        // #5: Use utf16.count (O(1) for NSString-backed) with matching UTF-16 units
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let replacement = replacementString else { return true }
            let currentLength = (textView.string as NSString).length
            let newLength = currentLength - affectedCharRange.length + (replacement as NSString).length
            return newLength <= maxCharacters
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isUpdatingFromTextView = true
            parent.text = textView.string
            isUpdatingFromTextView = false
            parent.onKeystroke()
        }
    }
}

// MARK: - Timer View
struct TimerView: View {
    let timeRemaining: Double
    let onExtend: () -> Void

    var timerText: String {
        let total = max(0, Int(ceil(timeRemaining)))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var timerColor: Color {
        if timeRemaining <= 15 {
            return .red
        } else if timeRemaining <= 60 {
            return .orange
        } else {
            return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // +5 min button
            Button(action: onExtend) {
                Text("+5m")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)

            // Timer label
            Text(timerText)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(timerColor)
        }
    }
}
