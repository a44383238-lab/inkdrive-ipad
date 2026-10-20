import UIKit
import UniformTypeIdentifiers

@MainActor final class NativePicker: NSObject, UIDocumentPickerDelegate {
    private var continuation: CheckedContinuation<URL?, Error>?
    func pick(types: [UTType], from controller: UIViewController) async throws -> URL? {
        guard continuation == nil, controller.presentedViewController == nil else { throw InkError.busy }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
            picker.delegate = self; picker.allowsMultipleSelection = false
            controller.present(picker, animated: true)
        }
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { controller.dismiss(animated: true) { self.finish(nil) } }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        controller.dismiss(animated: true) { self.finish(urls.first) }
    }
    private func finish(_ url: URL?) { let pending = continuation; continuation = nil; pending?.resume(returning: url) }
}
