import Foundation

struct CompactWindowLayout {
    private var expandedSize: CGSize?

    var isCollapsed: Bool { expandedSize != nil }

    mutating func toggle(frame: CGRect, headerHeight: CGFloat) -> CGRect {
        let size: CGSize
        if let expandedSize {
            size = expandedSize
            self.expandedSize = nil
        } else {
            expandedSize = frame.size
            size = CGSize(width: frame.width, height: max(1, headerHeight))
        }

        return CGRect(
            x: frame.minX,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
