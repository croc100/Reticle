import CoreImage
import CoreGraphics
import AppKit
import ReticleCore

/// Composites one or more MaskRegions onto a CGImage using CoreImage filters.
///
/// All rendering is GPU-accelerated via CIContext backed by Metal.
///
/// ## Coordinate contract
///
/// Three origin conventions meet in this type, so each one is pinned down here:
///
/// - `MaskRule.rect`, and the rects resolved from window rules, are **screen points with
///   origin top-left** — the space `CGWindowListCopyWindowInfo` reports bounds in.
/// - `CGImage` pixel space is **origin top-left**; `CGImage.cropping(to:)` reads rects
///   in that space.
/// - `CGContext` user space is **origin bottom-left**.
///
/// Everything below works in top-left pixel space, and the flip to bottom-left happens
/// exactly once — where a rect is handed to the context to draw into.
public struct MaskRenderer {
    private let context: CIContext

    public init() {
        context = CIContext(options: [.useSoftwareRenderer: false])
    }

    /// Apply all mask regions to `image` in order and return the composite result.
    ///
    /// - Parameters:
    ///   - image: The captured CGImage. May be a crop of a display rather than a whole one.
    ///   - masks: Mask rules to apply. App/window rules are resolved against live window list.
    ///   - scaleFactor: Points → pixels ratio for the captured display (typically 2.0 on Retina).
    ///   - sourceOrigin: The screen point (top-left origin) that pixel (0, 0) of `image`
    ///     corresponds to. Pass the capture's `sourceRect.origin` so masks stored in absolute
    ///     screen coordinates line up with a region, window, or secondary-display capture.
    ///     The `.zero` default is only correct for a full capture of a display sitting at the
    ///     screen origin.
    public func render(image: CGImage,
                       masks: [MaskRegion],
                       scaleFactor: CGFloat = 1,
                       sourceOrigin: CGPoint = .zero) throws -> CGImage {
        let active = masks.filter(\.enabled)
        guard !active.isEmpty else { return image }

        let imageBounds = CGRect(x: 0, y: 0,
                                 width: CGFloat(image.width), height: CGFloat(image.height))

        // Resolve every rule to image-local pixel rects, dropping whatever falls outside
        // the captured area.
        let windowList = Self.queryWindowList()
        var targets: [(rect: CGRect, style: MaskStyle)] = []
        for mask in active {
            for screenRect in resolveRects(rule: mask.rule, windowList: windowList) {
                let local = screenRect.offsetBy(dx: -sourceOrigin.x, dy: -sourceOrigin.y)
                let pixels = CGRect(x: local.minX * scaleFactor,
                                    y: local.minY * scaleFactor,
                                    width: local.width * scaleFactor,
                                    height: local.height * scaleFactor)
                let clipped = pixels.intersection(imageBounds)
                guard !clipped.isEmpty else { continue }
                // Snap outward only after the bounds check — `intersection` yields a null
                // rect for a mask that misses the image entirely, and `integral` of null
                // is not a rect worth reasoning about.
                targets.append((clipped.integral, mask.style))
            }
        }
        guard !targets.isEmpty else { return image }

        guard let ctx = CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { throw EffectsError.contextCreationFailed }

        // Drawing the source over the whole context is an upright round-trip: the image's
        // top row lands on the context's top row.
        ctx.draw(image, in: imageBounds)

        for (rect, style) in targets {
            // `rect` is top-left pixel space; the context draws in bottom-left user space.
            let drawRect = CGRect(x: rect.minX,
                                  y: imageBounds.height - rect.maxY,
                                  width: rect.width,
                                  height: rect.height)

            switch style {
            case .blur(let radius):
                if let blurred = applyBlur(image: image, rect: rect, radius: Float(radius)) {
                    ctx.draw(blurred, in: drawRect)
                }
            case .pixelate(let blockSize):
                if let pixelated = applyPixelate(image: image, rect: rect, blockSize: Float(blockSize)) {
                    ctx.draw(pixelated, in: drawRect)
                }
            case .solidFill(let r, let g, let b):
                ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
                ctx.fill(drawRect)
            }
        }

        guard let result = ctx.makeImage() else { throw EffectsError.renderFailed }
        return result
    }

    // MARK: - Rule resolution

    private func resolveRects(rule: MaskRule, windowList: [[CFString: Any]]) -> [CGRect] {
        switch rule {
        case .rect(let r):
            return [r]
        case .appBundle(let bundleID):
            return windowList.compactMap { info -> CGRect? in
                guard let pid = info[kCGWindowOwnerPID as CFString] as? pid_t,
                      let bounds = info[kCGWindowBounds as CFString] as? [String: CGFloat]
                else { return nil }
                // Match by bundle ID via running application list
                guard NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == bundleID
                else { return nil }
                return boundsToRect(bounds)
            }
        case .windowTitle(let substring):
            return windowList.compactMap { info -> CGRect? in
                guard let title = info[kCGWindowName as CFString] as? String,
                      title.localizedCaseInsensitiveContains(substring),
                      let bounds = info[kCGWindowBounds as CFString] as? [String: CGFloat]
                else { return nil }
                return boundsToRect(bounds)
            }
        }
    }

    private func boundsToRect(_ d: [String: CGFloat]) -> CGRect? {
        guard let x = d["X"], let y = d["Y"], let w = d["Width"], let h = d["Height"],
              w > 0, h > 0 else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private static func queryWindowList() -> [[CFString: Any]] {
        let opts = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[CFString: Any]]
        else { return [] }
        return list
    }

    // MARK: - Private filters

    /// Blurs `rect` of `image`, where `rect` is top-left pixel space.
    ///
    /// The crop is widened by the blur radius first: blurring an exact crop samples
    /// transparent black past its edges, which bleeds a dark halo inward.
    private func applyBlur(image: CGImage, rect: CGRect, radius: Float) -> CGImage? {
        let expand = CGFloat(radius)
        let imgBounds = CGRect(x: 0, y: 0,
                               width: CGFloat(image.width), height: CGFloat(image.height))
        let expanded = rect.insetBy(dx: -expand, dy: -expand).intersection(imgBounds).integral
        guard !expanded.isEmpty, let cropped = image.cropping(to: expanded) else { return nil }

        let ci = CIImage(cgImage: cropped)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(max(radius, 1), forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }

        // `cropped` carries its own origin, and CIImage measures from the bottom, so the
        // inset from the top of the crop becomes an inset from the bottom here.
        let innerRect = CGRect(x: rect.minX - expanded.minX,
                               y: expanded.maxY - rect.maxY,
                               width: rect.width,
                               height: rect.height)
        return context.createCGImage(output, from: innerRect)
    }

    /// Pixelates `rect` of `image`, where `rect` is top-left pixel space.
    private func applyPixelate(image: CGImage, rect: CGRect, blockSize: Float) -> CGImage? {
        guard let cropped = image.cropping(to: rect) else { return nil }
        let ci = CIImage(cgImage: cropped)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(max(blockSize, 2), forKey: kCIInputScaleKey)
        // Anchor the block grid to the crop's centre. Left at its default the grid centres
        // on (150, 150), which shifts blocks unpredictably for small regions.
        filter.setValue(CIVector(x: ci.extent.midX, y: ci.extent.midY), forKey: kCIInputCenterKey)
        guard let output = filter.outputImage else { return nil }
        return context.createCGImage(output, from: ci.extent)
    }
}

// MARK: - Error

public enum EffectsError: Error {
    case contextCreationFailed
    case renderFailed
}
