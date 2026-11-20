import CoreGraphics
import Foundation

/// Chooses the launcher's display. Pure geometry, so it is testable without screens.
public enum DisplayPlacement {
    /// Quartz window bounds use a top-left origin on the primary display with y
    /// increasing downward; Cocoa screen frames use a bottom-left origin.
    public static func cocoaRect(fromQuartz rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The screen the focused window covers most; otherwise the one under the pointer.
    public static func screenIndex(window: CGRect?, pointer: CGPoint, screens: [CGRect]) -> Int? {
        if let window {
            let areas = screens.map { screen -> CGFloat in
                let overlap = screen.intersection(window)
                return overlap.isNull ? 0 : overlap.width * overlap.height
            }
            if let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 { return best }
        }
        return screens.firstIndex { $0.contains(pointer) }
    }
}
