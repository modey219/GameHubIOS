import UIKit
import UniformTypeIdentifiers

enum DocumentPickerPresenter {
    private static var assocKey = "DocumentPickerDelegateKey"

    static func topViewController(from base: UIViewController? = nil) -> UIViewController? {
        var base = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .first?
            .keyWindow?
            .rootViewController
        while let presented = base?.presentedViewController {
            base = presented
        }
        return base
    }

    static func present(
        types: [UTType] = [.data, .folder],
        allowsMultiple: Bool = true,
        onPick: @escaping ([URL]) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.allowsMultipleSelection = allowsMultiple
        let delegate = DocumentPickerDelegate(onPick: onPick, onCancel: onCancel)
        picker.delegate = delegate
        objc_setAssociatedObject(picker, &assocKey, delegate, .OBJC_ASSOCIATION_RETAIN)

        guard let presenter = topViewController() else {
            onCancel?()
            return
        }
        presenter.present(picker, animated: true)
    }
}

private final class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    let onPick: ([URL]) -> Void
    let onCancel: (() -> Void)?

    init(onPick: @escaping ([URL]) -> Void, onCancel: (() -> Void)?) {
        self.onPick = onPick
        self.onCancel = onCancel
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        onPick(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        onCancel?()
    }
}
