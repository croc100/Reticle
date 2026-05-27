import CoreImage
import CoreGraphics
import CentreeCore

/// Composites one or more MaskRegions onto a CGImage using CoreImage filters.
///
/// All rendering is GPU-accelerated via CIContext backed by Metal.
/// Implemented in Phase 3.
public struct MaskRenderer {
    private let context: CIContext

    public init() {
        context = CIContext(options: [.useSoftwareRenderer: false])
    }

    public func render(image: CGImage, masks: [MaskRegion]) throws -> CGImage {
        // Implemented in Phase 3.
        return image
    }
}
