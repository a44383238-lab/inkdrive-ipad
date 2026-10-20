import UIKit
import PDFKit
import PencilKit

/// Preserve PDFKit's delegate callbacks while replacing its release velocity with the exact release position.
final class StationaryScrollDelegate: NSObject, UIScrollViewDelegate {
    weak var original: UIScrollViewDelegate?
    init(original: UIScrollViewDelegate?) { self.original = original }
    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }
    override func forwardingTarget(for selector: Selector!) -> Any? { original }
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        original?.scrollViewWillEndDragging?(scrollView, withVelocity: velocity, targetContentOffset: targetContentOffset)
        targetContentOffset.pointee = scrollView.contentOffset
    }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        original?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
        if decelerate { scrollView.setContentOffset(scrollView.contentOffset, animated: false) }
    }
}

@MainActor final class NotebookViewport {
    private var delegates: [ObjectIdentifier: StationaryScrollDelegate] = [:]
    func configure(_ view: UIView) {
        guard !(view is PKCanvasView) else { return }
        if let scroll = view as? UIScrollView {
            scroll.bounces = false; scroll.alwaysBounceVertical = false; scroll.alwaysBounceHorizontal = false
            scroll.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            scroll.pinchGestureRecognizer?.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            scroll.panGestureRecognizer.minimumNumberOfTouches = 1
            scroll.delaysContentTouches = false; scroll.canCancelContentTouches = false
            let key = ObjectIdentifier(scroll)
            if !(scroll.delegate is StationaryScrollDelegate) {
                let proxy = StationaryScrollDelegate(original: scroll.delegate)
                delegates[key] = proxy; scroll.delegate = proxy
            }
        }
        view.subviews.forEach(configure)
    }
}
