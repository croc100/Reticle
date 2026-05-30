import CoreImage
import CoreGraphics
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
    public func render(image: CGImage, masks: [MaskRegion]) throws -> CGImage {
        guard !masks.isEmpty else { return image }

        let w = image.width; let h = image.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { throw EffectsError.contextCreationFailed }

        // Draw base image (CG convention: y=0=bottom, draw fills full rect top-to-bottom)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        for mask in masks {
            // mask.rect is in screen/view coords (y=0=top).
            // CG context has y=0=bottom: flip y = imageH - rect.maxY.
            let pixelRect = CGRect(
                x: mask.rect.minX,
                y: CGFloat(h) - mask.rect.maxY,
                width: mask.rect.width,
                height: mask.rect.height
            )
            let clipped = pixelRect.intersection(CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
            guard !clipped.isEmpty else { continue }

            switch mask.style {
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

    // MARK: - Private filters

    private func applyBlur(image: CGImage, rect: CGRect, radius: Float) -> CGImage? {
        guard let cropped = image.cropping(to: rect) else { return nil }
        let ci = CIImage(cgImage: cropped)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(max(radius, 1), forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        // CIGaussianBlur pads the output; crop back to original size
        let dest = CGRect(origin: .zero, size: rect.size)
        let shifted = output.transformed(by: .init(translationX: -output.extent.minX,
                                                    y: -output.extent.minY))
        return context.createCGImage(shifted, from: dest)
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
