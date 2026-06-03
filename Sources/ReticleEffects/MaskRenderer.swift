import CoreImage
import CoreGraphics
import AppKit
import ReticleCore

/// Composites one or more MaskRegions onto a CGImage using CoreImage filters.
///
/// All rendering is GPU-accelerated via CIContext backed by Metal.
public struct MaskRenderer {
    private let context: CIContext

    public init() {
        context = CIContext(options: [.useSoftwareRenderer: false])
    }

    /// Apply all mask regions to `image` in order and return the composite result.
    ///
    /// - Parameters:
    ///   - image: The full captured CGImage (screen-coordinate space, y=0=top).
    ///   - masks: Mask rules to apply. App/window rules are resolved against live window list.
    ///   - scaleFactor: Points → pixels ratio for the captured display (typically 2.0 on Retina).
    public func render(image: CGImage, masks: [MaskRegion], scaleFactor: CGFloat = 1) throws -> CGImage {
        let active = masks.filter(\.enabled)
        guard !active.isEmpty else { return image }

        // Resolve app/window rules to pixel rects
        let windowList = Self.queryWindowList()
        var pixelRects: [(CGRect, MaskStyle)] = []
        for mask in active {
            let screenRects = resolveRects(rule: mask.rule, windowList: windowList)
            for r in screenRects {
                // screen coords (pt, y=0=top) → pixel coords (y=0=top, scaled)
                let px = CGRect(x: r.minX * scaleFactor, y: r.minY * scaleFactor,
                                width: r.width * scaleFactor, height: r.height * scaleFactor)
                pixelRects.append((px, mask.style))
            }
        }
        guard !pixelRects.isEmpty else { return image }

        let w = image.width; let h = image.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { throw EffectsError.contextCreationFailed }

        // CGContext y=0=bottom; input image y=0=top → flip y
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        for (pixRect, style) in pixelRects {
            // flip y: cgY = imageH - pixRect.maxY
            let cgRect = CGRect(
                x: pixRect.minX,
                y: CGFloat(h) - pixRect.maxY,
                width: pixRect.width,
                height: pixRect.height
            )
            let clipped = cgRect.intersection(CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
            guard !clipped.isEmpty else { continue }

            switch style {
            case .blur(let radius):
                if let blurred = applyBlur(image: image, rect: clipped, radius: Float(radius)) {
                    ctx.draw(blurred, in: clipped)
                }
            case .pixelate(let blockSize):
                if let pixelated = applyPixelate(image: image, rect: clipped, blockSize: Float(blockSize)) {
                    ctx.draw(pixelated, in: clipped)
                }
            case .solidFill(let r, let g, let b):
                ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
                ctx.fill(clipped)
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
                guard let owner = info[kCGWindowOwnerName as CFString] as? String,
                      let pid = info[kCGWindowOwnerPID as CFString] as? pid_t,
                      let bounds = info[kCGWindowBounds as CFString] as? [String: CGFloat]
                else { return nil }
                _ = owner
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

    private func applyBlur(image: CGImage, rect: CGRect, radius: Float) -> CGImage? {
        let expand = CGFloat(radius)
        let imgBounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        let expanded = rect.insetBy(dx: -expand, dy: -expand).intersection(imgBounds)
        guard !expanded.isEmpty, let cropped = image.cropping(to: expanded) else { return nil }

        let ci = CIImage(cgImage: cropped)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(max(radius, 1), forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }

        let innerRect = CGRect(x: rect.minX - expanded.minX,
                               y: rect.minY - expanded.minY,
                               width: rect.width, height: rect.height)
        return context.createCGImage(output, from: innerRect)
    }

    private func applyPixelate(image: CGImage, rect: CGRect, blockSize: Float) -> CGImage? {
        guard let cropped = image.cropping(to: rect) else { return nil }
        let ci = CIImage(cgImage: cropped)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(max(blockSize, 2), forKey: kCIInputScaleKey)
        guard let output = filter.outputImage else { return nil }
        let dest = CGRect(origin: .zero, size: rect.size)
        return context.createCGImage(output, from: dest)
    }
}

// MARK: - Error

public enum EffectsError: Error {
    case contextCreationFailed
    case renderFailed
}
