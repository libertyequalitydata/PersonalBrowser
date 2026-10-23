import SwiftUI
import UIKit

struct AddressBarTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let inactiveText: String
    let textColor: UIColor
    let tintColor: UIColor
    let onSubmit: () -> Void
    var placeholder = "Search or enter address"
    var fontSize: CGFloat = 15

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.placeholder = placeholder
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.keyboardType = .webSearch
        field.returnKeyType = .go
        field.clearButtonMode = .never
        field.adjustsFontForContentSizeCategory = true
        field.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: fontSize)
        )
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        let presentedText = isFocused ? text : inactiveText
        if field.text != presentedText {
            field.text = presentedText
        }
        field.textColor = textColor
        field.tintColor = tintColor
        field.placeholder = placeholder
        field.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: fontSize)
        )
        field.textAlignment = isFocused ? .natural : .center

        if isFocused, !field.isFirstResponder {
            field.becomeFirstResponder()
        } else if !isFocused, field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AddressBarTextField

        init(parent: AddressBarTextField) {
            self.parent = parent
        }

        @objc func textChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFocused = true
            DispatchQueue.main.async {
                textField.text = self.parent.text
                textField.textAlignment = .natural
                textField.selectAll(nil)
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFocused = false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }
    }
}

enum AddressBarPresentation {
    static let newTabPlaceholder = "Enter URL or Search"

    static func inactiveText(for url: URL?) -> String {
        guard let url, let host = url.host, !host.isEmpty else { return "" }
        let presentedHost = host.contains(":") ? "[\(host)]" : host
        guard let port = url.port, !isDefaultPort(port, for: url.scheme) else {
            return presentedHost
        }
        return "\(presentedHost):\(port)"
    }

    private static func isDefaultPort(_ port: Int, for scheme: String?) -> Bool {
        switch scheme?.lowercased() {
        case "http": port == 80
        case "https": port == 443
        default: false
        }
    }
}
