import CoreGraphics
import Foundation
import ReticleCore
import XCTest

@testable import ReticlePipeline

/// The pipeline transforms the screenshot in place through its after-capture
/// tasks — static masks, PII redaction, border, watermark — and everything that
/// consumes the capture afterwards has to receive *that* image.  These tests pin
/// down the hand-off, because the failure mode is silent: the saved file looks
/// correctly redacted while uploads, OCR and the history thumbnail carry the
/// untouched original.
final class PipelineRunnerTests: XCTestCase {

    // MARK: - finalScreenshot

    func testFinalScreenshotIsNilOnAFreshContext() {
        let ctx = CaptureContext(workflowID: UUID())
        XCTAssertNil(ctx.finalScreenshot)
    }

    func testFinalScreenshotCarriesTheTransformedImage() async throws {
        let original = try makeImage(width: 32, height: 32)
        let shot = Screenshot(image: original, sourceRect: .zero, scaleFactor: 2)

        let ctx = try await PipelineRunner().run(
            preCapture: shot,
            afterCapture: [ResizeTask(width: 64, height: 64)],
            outputs: []
        )

        let produced = try XCTUnwrap(ctx.finalScreenshot)
        XCTAssertEqual(produced.image.width, 64, "the published image must be the task's output")
        XCTAssertEqual(original.width, 32, "the caller's own image must be left alone")
    }

    /// The *last* task's output is what gets published, not the first one's.
    func testFinalScreenshotReflectsEveryAfterCaptureTaskInOrder() async throws {
        let shot = Screenshot(image: try makeImage(width: 8, height: 8),
                              sourceRect: .zero, scaleFactor: 1)

        let ctx = try await PipelineRunner().run(
            preCapture: shot,
            afterCapture: [
                ResizeTask(width: 16, height: 16),
                ResizeTask(width: 48, height: 48),
            ],
            outputs: []
        )

        XCTAssertEqual(try XCTUnwrap(ctx.finalScreenshot).image.width, 48)
    }

    func testFinalScreenshotIsSetEvenWithNoAfterCaptureTasks() async throws {
        let shot = Screenshot(image: try makeImage(width: 20, height: 10),
                              sourceRect: .zero, scaleFactor: 1)

        let ctx = try await PipelineRunner().run(preCapture: shot, outputs: [])

        let produced = try XCTUnwrap(ctx.finalScreenshot)
        XCTAssertEqual(produced.image.width, 20)
        XCTAssertEqual(produced.image.height, 10)
    }

    func testFinalScreenshotKeepsSourceRectAndScaleFactor() async throws {
        let rect = CGRect(x: 12, y: 34, width: 56, height: 78)
        let shot = Screenshot(image: try makeImage(width: 8, height: 8),
                              sourceRect: rect, scaleFactor: 2)

        let ctx = try await PipelineRunner().run(
            preCapture: shot,
            afterCapture: [ResizeTask(width: 16, height: 16)],
            outputs: []
        )

        let produced = try XCTUnwrap(ctx.finalScreenshot)
        XCTAssertEqual(produced.sourceRect, rect)
        XCTAssertEqual(produced.scaleFactor, 2)
    }

    // MARK: - Output stage

    /// Outputs run after the transform, so a file written to disk and a clipboard
    /// copy both have to show the redacted pixels.
    func testOutputsReceiveTheTransformedImage() async throws {
        let shot = Screenshot(image: try makeImage(width: 8, height: 8),
                              sourceRect: .zero, scaleFactor: 1)

        let ctx = try await PipelineRunner().run(
            preCapture: shot,
            afterCapture: [ResizeTask(width: 72, height: 72)],
            outputs: [WidthReportingOutput()]
        )

        XCTAssertEqual(ctx.outputURLs.map(\.lastPathComponent), ["72.png"])
    }

    func testAfterCaptureFailureStopsTheRunBeforeAnyOutput() async throws {
        let shot = Screenshot(image: try makeImage(width: 8, height: 8),
                              sourceRect: .zero, scaleFactor: 1)

        do {
            _ = try await PipelineRunner().run(
                preCapture: shot,
                afterCapture: [FailingTask()],
                outputs: [WidthReportingOutput()]
            )
            XCTFail("the run should have propagated the task's error")
        } catch is FailingTask.Failure {
            // Expected: a redaction step that throws must abort the whole capture
            // rather than let the untouched image reach an output.
        }
    }
}

// MARK: - Test doubles

/// Swaps in a differently sized image, standing in for the real after-capture
/// tasks whose job is to change the pixels before anything leaves the machine.
/// Size is the signal here because it survives into `CGImage` cheaply.
private struct ResizeTask: AfterCaptureTask {
    let width: Int
    let height: Int

    func execute(screenshot: inout Screenshot, context: CaptureContext) async throws {
        let replacement = try makeImage(width: width, height: height)
        screenshot = Screenshot(
            image: replacement,
            sourceRect: screenshot.sourceRect,
            scaleFactor: screenshot.scaleFactor
        )
    }
}

/// Records the width it was handed by appending it as a filename, which keeps the
/// reporting synchronous and inside the `inout` context the protocol provides.
private struct WidthReportingOutput: OutputTask {
    func execute(screenshot: Screenshot, context: inout CaptureContext) async throws {
        context.outputURLs.append(
            URL(fileURLWithPath: "/dev/null/\(screenshot.image.width).png"))
    }
}

private struct FailingTask: AfterCaptureTask {
    struct Failure: Error {}

    func execute(screenshot: inout Screenshot, context: CaptureContext) async throws {
        throw Failure()
    }
}

// MARK: - Helpers

private enum TestImageError: Error {
    case contextUnavailable
    case imageUnavailable
}

private func makeImage(width: Int, height: Int) throws -> CGImage {
    guard let ctx = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw TestImageError.contextUnavailable
    }
    guard let image = ctx.makeImage() else {
        throw TestImageError.imageUnavailable
    }
    return image
}
