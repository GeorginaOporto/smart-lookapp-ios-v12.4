import Foundation
import UIKit
import onnxruntime_objc

/// MobileSAM promptable segmenter. This is the iOS counterpart of Android's
/// SmartSegmentEngine: one positive tap is sent to the encoder/decoder pair,
/// and only the selected mask instance is rendered on a black background.
final class MVDMobileSAM {
    static let shared = MVDMobileSAM()

    private let lock = NSLock()
    private var environment: ORTEnv?
    private var encoder: ORTSession?
    private var decoder: ORTSession?

    private let inputSize = 1024
    private let threshold: Float = 0.1

    private init() {
        do {
            let env = try ORTEnv(loggingLevel: .warning)
            let options = try ORTSessionOptions()
            environment = env
            encoder = try ORTSession(
                env: env,
                modelPath: Self.modelPath(name: "mobile_sam_encoder"),
                sessionOptions: options
            )
            decoder = try ORTSession(
                env: env,
                modelPath: Self.modelPath(name: "mobile_sam"),
                sessionOptions: options
            )
        } catch {
            print("MobileSAM load error: \(error.localizedDescription)")
        }
    }

    func extract(_ image: UIImage, normalizedPoint: CGPoint) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        // Keep the environment retained for the lifetime of both sessions. The
        // ORTValue tensors themselves do not need the environment as an argument.
        guard environment != nil, let encoder, let decoder else { return nil }
        // Match the calibrated Android pipeline: orientation is normalized once
        // at the boundary, then the original pixel geometry is letterboxed to
        // the model input. Do not add a second working-image resize here: it
        // changes the tap-to-source mapping and the final crop coordinates.
        let source = image.normalizedForVision()
        guard let sourceCGImage = source.cgImage else { return nil }
        let prep = preprocess(source, inputSize: inputSize)

        do {
            let encoderInput = try makeTensor(
                values: prep.channelValues,
                shape: [1, 3, inputSize, inputSize]
            )
            let encoderOutputNames = try encoder.outputNames()
            let encoderOutputs = try encoder.run(
                withInputs: ["image": encoderInput],
                outputNames: Set(encoderOutputNames),
                runOptions: nil
            )
            // Android consumes result.get(0). Preserve that model-output
            // contract instead of choosing an output by an arbitrary name.
            guard let encoderOutputName = encoderOutputNames.first,
                  let embedding = encoderOutputs[encoderOutputName] else { return nil }

            let modelX = min(max(normalizedPoint.x * CGFloat(sourceCGImage.width) * prep.scale + CGFloat(prep.offsetX), 0), CGFloat(inputSize - 1))
            let modelY = min(max(normalizedPoint.y * CGFloat(sourceCGImage.height) * prep.scale + CGFloat(prep.offsetY), 0), CGFloat(inputSize - 1))
            print(
                "EXTRACTION_MODEL source=(\(sourceCGImage.width)x\(sourceCGImage.height)) " +
                "tap=(\(String(format: "%.1f", normalizedPoint.x * CGFloat(sourceCGImage.width))),\(String(format: "%.1f", normalizedPoint.y * CGFloat(sourceCGImage.height)))) " +
                "model=(\(String(format: "%.1f", modelX)),\(String(format: "%.1f", modelY)))"
            )


            // Keep the iOS prompt identical to Android: one positive point.
            // A synthetic negative ring can land on the same component or on
            // a neighboring part and force MobileSAM to reject the real tap.
            let pointCoords = try makeTensor(
                values: [Float(modelX), Float(modelY)],
                shape: [1, 1, 2]
            )
            let pointLabels = try makeTensor(
                values: [1],
                shape: [1, 1]
            )
            let maskInput = try makeTensor(
                values: Array(repeating: 0, count: 256 * 256),
                shape: [1, 1, 256, 256]
            )
            let hasMaskInput = try makeTensor(
                values: [0],
                shape: [1]
            )
            let originalSize = try makeTensor(
                values: [Float(inputSize), Float(inputSize)],
                shape: [2]
            )

            let decoderOutputNames = try decoder.outputNames()
            let decoderOutputs = try decoder.run(
                withInputs: [
                    "image_embeddings": embedding,
                    "point_coords": pointCoords,
                    "point_labels": pointLabels,
                    "mask_input": maskInput,
                    "has_mask_input": hasMaskInput,
                    "orig_im_size": originalSize
                ],
                outputNames: Set(decoderOutputNames),
                runOptions: nil
            )
            // Android consumes result.get(0) as the mask and result.get(1) as
            // IoU. Keep the same first-output selection for this one-tap path.
            guard let maskOutputName = decoderOutputNames.first,
                  let maskValue = decoderOutputs[maskOutputName] else { return nil }
            let maskData = try maskValue.tensorData()
            let maskInfo = try maskValue.tensorTypeAndShapeInfo()
            let maskShape = maskInfo.shape.map { $0.intValue }
            guard maskShape.count >= 2 else { return nil }
            let maskHeight = maskShape[maskShape.count - 2]
            let maskWidth = maskShape[maskShape.count - 1]
            guard maskWidth > 0,
                  maskHeight > 0 else { return nil }
            let maskPointer = maskData.bytes.assumingMemoryBound(to: Float.self)
            let allMaskValues = [Float](UnsafeBufferPointer<Float>(
                start: maskPointer,
                count: maskData.length / MemoryLayout<Float>.size
            ))
            let planeSize = maskWidth * maskHeight
            guard allMaskValues.count >= planeSize else { return nil }
            let tapMaskPoint = CGPoint(
                x: modelX * CGFloat(maskWidth) / CGFloat(inputSize),
                y: modelY * CGFloat(maskHeight) / CGFloat(inputSize)
            )
            // The decoder may return several candidate masks. Selecting the
            // first plane is unreliable for small objects, because that plane
            // can be the broad foreground proposal. Choose the proposal whose
            // raw mask score is strongest exactly at the user's tap.
            let tapX = min(max(Int(tapMaskPoint.x.rounded()), 0), maskWidth - 1)
            let tapY = min(max(Int(tapMaskPoint.y.rounded()), 0), maskHeight - 1)
            let candidateCount = max(1, allMaskValues.count / planeSize)
            var selectedCandidate = 0
            var bestCandidateScore = -Float.greatestFiniteMagnitude
            for candidate in 0..<candidateCount {
                let score = allMaskValues[candidate * planeSize + tapY * maskWidth + tapX]
                if score > bestCandidateScore {
                    bestCandidateScore = score
                    selectedCandidate = candidate
                }
            }
            let maskStart = selectedCandidate * planeSize
            let maskValues = Array(allMaskValues[maskStart..<min(maskStart + planeSize, allMaskValues.count)])
            guard maskValues.count == planeSize else { return nil }
            return render(
                maskValues: maskValues,
                maskWidth: maskWidth,
                maskHeight: maskHeight,
                source: sourceCGImage,
                prep: prep,
                tapMaskPoint: tapMaskPoint
            )
        } catch {
            print("MobileSAM inference error: \(error.localizedDescription)")
            return nil
        }
    }

    private static func modelPath(name: String) -> String {
        Bundle.main.path(forResource: name, ofType: "onnx") ?? ""
    }

    private struct Prep {
        let channelValues: [Float]
        let scale: CGFloat
        let offsetX: Int
        let offsetY: Int
    }

    private func preprocess(_ image: UIImage, inputSize: Int) -> Prep {
        let cgImage = image.cgImage!
        let scale = min(
            CGFloat(inputSize) / CGFloat(cgImage.width),
            CGFloat(inputSize) / CGFloat(cgImage.height)
        )
        let resizedWidth = max(1, Int(CGFloat(cgImage.width) * scale))
        let resizedHeight = max(1, Int(CGFloat(cgImage.height) * scale))
        let offsetX = (inputSize - resizedWidth) / 2
        let offsetY = (inputSize - resizedHeight) / 2

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: inputSize, height: inputSize), format: format)
        let padded = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: inputSize, height: inputSize))
            image.draw(in: CGRect(x: offsetX, y: offsetY, width: resizedWidth, height: resizedHeight))
        }
        guard let paddedCGImage = padded.cgImage,
              let bitmap = rgbaBitmap(paddedCGImage, width: inputSize, height: inputSize) else {
            return Prep(channelValues: Array(repeating: 0, count: 3 * inputSize * inputSize), scale: scale, offsetX: offsetX, offsetY: offsetY)
        }
        let planeSize = inputSize * inputSize
        var values = Array(repeating: Float(0), count: planeSize * 3)
        for index in 0..<planeSize {
            let pixel = index * 4
            values[index] = Float(bitmap[pixel]) / 255
            values[planeSize + index] = Float(bitmap[pixel + 1]) / 255
            values[2 * planeSize + index] = Float(bitmap[pixel + 2]) / 255
        }
        return Prep(channelValues: values, scale: scale, offsetX: offsetX, offsetY: offsetY)
    }

    private func render(
        maskValues: [Float],
        maskWidth: Int,
        maskHeight: Int,
        source: CGImage,
        prep: Prep,
        tapMaskPoint: CGPoint
    ) -> UIImage? {
        let width = source.width
        let height = source.height
        guard !maskValues.isEmpty, let sourcePixels = rgbaBitmap(source, width: width, height: height) else { return nil }
        guard maskValues.count >= maskWidth * maskHeight else { return nil }

        func maskValue(x: Int, y: Int) -> Float {
            maskValues[y * maskWidth + x]
        }

        // MobileSAM can return small disconnected islands around a one-tap
        // prompt, especially when the object occupies little of the photo.
        // Keep only the foreground component that contains (or is nearest to)
        // the actual tap. This prevents a generic mask from bringing along
        // unrelated background regions while preserving the complete object.
        let foreground = maskValues.map { $0 > threshold }
        var visited = Array(repeating: false, count: maskWidth * maskHeight)
        var bestComponent: [Int] = []
        var bestDistance = CGFloat.greatestFiniteMagnitude
        let tapX = min(max(tapMaskPoint.x, 0), CGFloat(maskWidth - 1))
        let tapY = min(max(tapMaskPoint.y, 0), CGFloat(maskHeight - 1))
        let neighbors = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]

        for startY in 0..<maskHeight {
            for startX in 0..<maskWidth {
                let start = startY * maskWidth + startX
                guard foreground[start], !visited[start] else { continue }
                var queue = [start]
                var component: [Int] = []
                visited[start] = true
                var head = 0
                while head < queue.count {
                    let index = queue[head]
                    head += 1
                    component.append(index)
                    let x = index % maskWidth
                    let y = index / maskWidth
                    for (dx, dy) in neighbors {
                        let nx = x + dx
                        let ny = y + dy
                        guard nx >= 0, nx < maskWidth, ny >= 0, ny < maskHeight else { continue }
                        let next = ny * maskWidth + nx
                        if foreground[next], !visited[next] {
                            visited[next] = true
                            queue.append(next)
                        }
                    }
                }
                let nearestDistance = component.reduce(CGFloat.greatestFiniteMagnitude) { current, index in
                    let x = CGFloat(index % maskWidth)
                    let y = CGFloat(index / maskWidth)
                    return min(current, hypot(x - tapX, y - tapY))
                }
                // Prefer the component nearest the tap; for ties keep the
                // larger component so all connected parts of the object stay.
                if nearestDistance < bestDistance - 0.5 ||
                    (abs(nearestDistance - bestDistance) <= 0.5 && component.count > bestComponent.count) {
                    bestDistance = nearestDistance
                    bestComponent = component
                }
            }
        }
        guard !bestComponent.isEmpty else { return nil }
        let selected = Set(bestComponent)
        var minX = maskWidth
        var minY = maskHeight
        var maxX = 0
        var maxY = 0
        for index in bestComponent {
            let x = index % maskWidth
            let y = index / maskWidth
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
        guard minX < maxX, minY < maxY else { return nil }

        func maskToSource(_ mx: Int, _ my: Int) -> (Int, Int) {
            let sourceX = Int((CGFloat(mx) - CGFloat(prep.offsetX)) / prep.scale)
            let sourceY = Int((CGFloat(my) - CGFloat(prep.offsetY)) / prep.scale)
            return (
                min(max(sourceX, 0), max(0, width - 1)),
                min(max(sourceY, 0), max(0, height - 1))
            )
        }

        let (left, top) = maskToSource(minX, minY)
        let (right, bottom) = maskToSource(maxX, maxY)
        print(
            "EXTRACTION_MASK mask=(\(maskWidth)x\(maskHeight)) " +
            "sourceBounds=(\(left),\(top))-(\(right),\(bottom))"
        )
        // The mask bounds are inclusive. Keeping the final pixel avoids
        // trimming the selected part at its right/bottom edge.
        let outputWidth = min(width - left, max(1, right - left + 1))
        let outputHeight = min(height - top, max(1, bottom - top + 1))
        var output = Array(repeating: UInt8(0), count: outputWidth * outputHeight * 4)
        for y in 0..<outputHeight {
            for x in 0..<outputWidth {
                let sourceX = left + x
                let sourceY = top + y
                let mx = min(max(Int(CGFloat(sourceX) * prep.scale) + prep.offsetX, 0), maskWidth - 1)
                let my = min(max(Int(CGFloat(sourceY) * prep.scale) + prep.offsetY, 0), maskHeight - 1)
                let destination = (y * outputWidth + x) * 4
                if selected.contains(my * maskWidth + mx) {
                    let sourceIndex = (sourceY * width + sourceX) * 4
                    output[destination] = sourcePixels[sourceIndex]
                    output[destination + 1] = sourcePixels[sourceIndex + 1]
                    output[destination + 2] = sourcePixels[sourceIndex + 2]
                    output[destination + 3] = 255
                } else {
                    output[destination] = 0
                    output[destination + 1] = 0
                    output[destination + 2] = 0
                    output[destination + 3] = 0
                }
            }
        }
        // `output` is generated in the same top-left row order used by the
        // mask and by `rgbaBitmap`. A CGImage created directly from a provider
        // consumes the provider rows in the opposite vertical direction on
        // this path, so reverse the rows once at this raster boundary. This
        // is a vertical row-order correction, not a 90-degree image rotation
        // and not a change to the user's tap coordinates.
        var displayOutput = Array(repeating: UInt8(0), count: output.count)
        for row in 0..<outputHeight {
            let sourceRow = outputHeight - 1 - row
            let sourceStart = sourceRow * outputWidth * 4
            let destinationStart = row * outputWidth * 4
            displayOutput.replaceSubrange(
                destinationStart..<(destinationStart + outputWidth * 4),
                with: output[sourceStart..<(sourceStart + outputWidth * 4)]
            )
        }

        // The source was already rendered to `.up`, so the crop must also be
        // `.up`; applying the original EXIF orientation again would rotate it.
        guard let provider = CGDataProvider(data: NSData(bytes: displayOutput,
                                                         length: displayOutput.count) as CFData),
              let result = CGImage(
                width: outputWidth,
                height: outputHeight,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: outputWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else { return nil }
        return UIImage(cgImage: result, scale: 1, orientation: .up)
    }

    private func makeTensor(values: [Float], shape: [Int]) throws -> ORTValue {
        let data = values.withUnsafeBytes { raw in
            NSMutableData(bytes: raw.baseAddress!, length: values.count * MemoryLayout<Float>.size)
        }
        return try ORTValue(
            tensorData: data,
            elementType: .float,
            shape: shape.map { NSNumber(value: $0) }
        )
    }

    private func rgbaBitmap(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = context.data else { return nil }
        // Match UIKit's top-left image coordinates with the row order used by
        // the Android Bitmap path. Without this transform, off-centre taps on
        // portrait photos can be mirrored vertically before MobileSAM sees them.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pointer = data.assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: pointer, count: width * height * 4))
    }
}

