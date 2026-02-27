import SwiftUI
import UIKit

/// A UITextView wrapper that supports word-level text selection (long press to select,
/// Look Up, Define, Copy, Share) while remaining non-editable and scrolling-disabled.
struct SelectableText: UIViewRepresentable {
    let text: String
    let font: UIFont
    let textColor: UIColor

    func makeUIView(context: Context) -> SelfSizingTextView {
        let textView = SelfSizingTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.required, for: .vertical)
        configure(textView)
        return textView
    }

    func updateUIView(_ textView: SelfSizingTextView, context: Context) {
        configure(textView)
    }

    private func configure(_ textView: SelfSizingTextView) {
        textView.text = text
        textView.font = font
        textView.textColor = textColor
    }
}

/// UITextView subclass that reports its intrinsic content size so SwiftUI
/// allocates the correct height for the full text.
final class SelfSizingTextView: UITextView {
    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : 300
        let size = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: size.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        invalidateIntrinsicContentSize()
    }
}
