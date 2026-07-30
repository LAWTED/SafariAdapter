import AppKit
import Carbon
import SwiftUI

enum CommandBarMaterial: String, CaseIterable, Hashable {
    case oldHUD
    case popoverBlur
    case liquidGlass

    var title: String {
        switch self {
        case .oldHUD: "Old HUD · Original"
        case .popoverBlur: "Popover Blur"
        case .liquidGlass: "Liquid Glass"
        }
    }
}

@MainActor
final class CommandBarModel: ObservableObject {
    @Published var text: String
    @Published var focusRequest = 0

    let navigate: (String, Bool) -> Void
    let dismiss: () -> Void

    init(
        initialURL: String,
        navigate: @escaping (String, Bool) -> Void,
        dismiss: @escaping () -> Void
    ) {
        text = initialURL
        self.navigate = navigate
        self.dismiss = dismiss
    }

    func submit(opensInNewTab: Bool) {
        navigate(text, opensInNewTab)
    }
}

struct CommandBarView: View {
    @ObservedObject var model: CommandBarModel
    @Environment(\.colorScheme) private var colorScheme
    let material: CommandBarMaterial

    private enum Palette {
        static let cornerRadius: CGFloat = 22
    }

    private enum Layout {
        static let searchHeight: CGFloat = 68
    }

    var body: some View {
        switch material {
        case .oldHUD:
            content
                .background {
                    ZStack {
                        VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                        Color.black.opacity(0.12)
                    }
                    .clipShape(
                        RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.13), lineWidth: 1)
                    }
                }
                .preferredColorScheme(.dark)
        case .popoverBlur:
            content
                .background {
                    VisualEffectView(material: .popover, blendingMode: .behindWindow)
                        .clipShape(
                            RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)
                                .stroke(Color.white.opacity(0.13), lineWidth: 1)
                        }
                }
        case .liquidGlass:
            liquidGlassContent
        }
    }

    @ViewBuilder
    private var liquidGlassContent: some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(
                        colorScheme == .dark
                            ? Color.black.opacity(0.22)
                            : Color.white.opacity(0.16)
                    ),
                    in: .rect(cornerRadius: Palette.cornerRadius)
                )
        } else {
            content
                .background(
                    Color(red: 0.11, green: 0.11, blue: 0.14),
                    in: RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)
                )
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)

                AutoSelectingTextField(
                    text: $model.text,
                    focusRequest: model.focusRequest,
                    onSubmit: model.submit,
                    onCancel: model.dismiss
                )
                .frame(height: 34)

            }
            .padding(.horizontal, 20)
            .frame(height: Layout.searchHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct AutoSelectingTextField: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    let onSubmit: (Bool) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CommandTextField {
        let field = CommandTextField()
        field.delegate = context.coordinator
        field.onCommandReturn = { onSubmit(true) }
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 20, weight: .regular)
        field.textColor = .labelColor
        field.placeholderString = "Search or enter URL"
        field.lineBreakMode = .byTruncatingMiddle
        return field
    }

    func updateNSView(_ field: CommandTextField, context: Context) {
        context.coordinator.parent = self
        field.onCommandReturn = { onSubmit(true) }
        if field.stringValue != text {
            field.stringValue = text
        }

        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AutoSelectingTextField
        var lastFocusRequest = -1

        init(parent: AutoSelectingTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit(false)
                return true
            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                parent.onSubmit(true)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}

final class CommandTextField: NSTextField {
    var onCommandReturn: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isReturn = event.keyCode == UInt16(kVK_Return)
            || event.keyCode == UInt16(kVK_ANSI_KeypadEnter)
        if isReturn, flags.contains(.command) {
            onCommandReturn?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
