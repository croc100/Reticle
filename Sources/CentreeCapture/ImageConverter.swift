import CoreImage
import CoreMedia
import CoreVideo
import CoreGraphics

/// Converts a `CMSampleBuffer` produced by `SCStream` into a `CGImage`.
///
/// SCStream outputs `kCVPixelFormatType_32BGRA` pixel buffers.
/// `CIImage` handles the BGRA → display color space conversion automatically.
enum ImageConverter {

    private static let context = CIContext(options: [
        .useSoftwareRenderer: false,   // GPU path via Metal
        .highQualityDownsample: false, // we want speed, not photo resampling
    ])

    static func cgImage(from sampleBuffer: CMSampleBuffer) throws -> CGImage {
        guard let pixelBuffer = sampleBuffer.imageBuffer else {
            throw CaptureError.invalidFrame
        }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw CaptureError.invalidFrame
        }
        return cgImage
    }
}
