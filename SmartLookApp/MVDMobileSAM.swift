import Foundation
import UIKit
import onnxruntime_objc

private enum MVDMaskSelection {
    /// Choose a decoder proposal that contains the tapped area. A single
    /// decoder pixel is too brittle for thin parts (for example a red strap),
    /// because the screen tap can land on an anti-aliased edge after the
    /// image has been letterboxed and resized to the model canvas.
    static func candidate(
        values: [Float],
        scores: [Float],
        width: Int,
        height: Int,
        count: Int,
        point: CGPoint,
        threshold: Float
    ) -> Int? {
        guard width > 0, height > 0, count > 0,
              values.count >= count * width * height,
              point.x.isFinite, point.y.isFinite else { return nil }

        let centerX = min(max(Int(point.x.rounded()), 0), width - 1)
        let centerY = min(max(Int(point.y.rounded()), 0), height - 1)
        // Eight pixels at a 1024px model resolution is small enough to avoid
        // jumping to a neighboring component, while covering a normal finger
        // tap and mask-boundary quantization.
        let radius = max(3, min(12, Int((CGFloat(min(width, height)) * 0.008).rounded())))
        let planeSize = width * height

        var best: (index: Int, iou: Float, hits: Int, peak: Float)?
        for candidate in 0..<count {
            let start = candidate * planeSize
            var hits = 0
            var peak = -Float.greatestFiniteMagnitude
            let minY = max(0, centerY - radius)
            let maxY = min(height - 1, centerY + radius)
            let minX = max(0, centerX - radius)
            let maxX = min(width - 1, centerX + radius)
            for y in minY...maxY {
                for x in minX...maxX {
                    if hypot(CGFloat(x - centerX), CGFloat(y - centerY)) > CGFloat(radius) { continue }
                    let value = values[start + y * width + x]
                    peak = max(peak, value)
                    if value > threshold { hits += 1 }
                }
            }
            guard hits > 0 else { continue }
            let iou = candidate < scores.count && scores[candidate].isFinite
                ? scores[candidate]
                : -Float.greatestFiniteMagnitude

            if let current = best {
                let hasComparableIoU = iou.isFinite && current.iou.isFinite
                let shouldReplace: Bool
                if hasComparableIoU && abs(iou - current.iou) > 0.02 {
                    shouldReplace = iou > current.iou
                } else if hits != current.hits {
                    shouldReplace = hits > current.hits
                } else {
                    shouldReplace = peak > current.peak
                }
                if shouldReplace { best = (candidate, iou, hits, peak) }
            } else {
                best = (candidate, iou, hits, peak)
            }
        }
        return best?.index
    }

    /// Isolate the foreground island containing the positive tap. This is
    /// performed after decoder-proposal selection so a broad mask cannot
    /// return adjacent mechanical parts that were not touched.
    static func component(
        values: [Float],
        width: Int,
        height: Int,
        point: CGPoint,
        threshold: Float
    ) -> [Float]? {
        guard width > 0, height > 0, values.count == width * height,
              point.x.isFinite, point.y.isFinite else { return nil }

        let centerX = min(max(Int(point.x.rounded()), 0), width - 1)
        let centerY = min(max(Int(point.y.rounded()), 0), height - 1)
        let radius = max(2, min(12, Int((CGFloat(min(width, height)) * 0.008).rounded())))
        var seed: Int?
        var nearestDistance = CGFloat.greatestFiniteMagnitude
        for y in max(0, centerY - radius)...min(height - 1, centerY + radius) {
            for x in max(0, centerX - radius)...min(width - 1, centerX + radius) {
                guard values[y * width + x] > threshold else { continue }
                let distance = hypot(CGFloat(x - centerX), CGFloat(y - centerY))
                guard distance <= CGFloat(radius), distance < nearestDistance else { continue }
                nearestDistance = distance
                seed = y * width + x
            }
        }
        guard let seed else { return nil }

        var result = [Float](repeating: 0, count: values.count)
        var queue = [Int32(seed)]
        result[seed] = 1
        var head = 0
        while head < queue.count {
            let index = Int(queue[head])
            head += 1
            let x = index % width
            let y = index / width

            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let nx = x + dx
                    let ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let next = ny * width + nx
                    if result[next] == 0, values[next] > threshold {
                        result[next] = 1
                        queue.append(Int32(next))
                    }
                }
            }
        }
        return result
    }
}

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
            // Match Android v12.4 exactly: OrtSession.Result.get(0) is the
            // mask tensor used for both the preview and the extracted piece.
            // ORT's outputNames preserves the graph-output order represented
            // by Result.get(index), so consume its first entry here as well.
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
            // Android reads y * maskWidth + x directly from result.get(0),
            // which is the first mask plane. Do not substitute a different
            // proposal by IoU and do not post-filter connected components.
            let maskValues = Array(allMaskValues[0..<planeSize])
            return render(
                maskValues: maskValues,
                maskWidth: maskWidth,
                maskHeight: maskHeight,
                source: sourceCGImage,
                prep: prep
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
        prep: Prep
    ) -> UIImage? {
        let width = source.width
        let height = source.height
        guard !maskValues.isEmpty, let sourcePixels = rgbaBitmap(source, width: width, height: height) else { return nil }
        guard maskValues.count >= maskWidth * maskHeight else { return nil }

        // Keep the selected decoder proposal intact. MobileSAM can represent a
        // mechanical assembly as several disconnected foreground islands; a
        // nearest-component filter would keep only one wheel/roller and throw
        // away the rest of the requested NLG assembly.
        let selected = maskValues.map { $0 > threshold }
        var minX = maskWidth
        var minY = maskHeight
        var maxX = 0
        var maxY = 0
        for y in 0..<maskHeight {
            for x in 0..<maskWidth where selected[y * maskWidth + x] {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
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
                if selected[my * maskWidth + mx] {
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

    /// Copy an ONNX tensor while its runtime-owned buffer is still valid.
    private func floatValues(_ value: ORTValue) throws -> [Float] {
        let data = try value.tensorData()
        guard data.length % MemoryLayout<Float>.size == 0 else { return [] }
        var result = [Float](repeating: 0, count: data.length / MemoryLayout<Float>.size)
        result.withUnsafeMutableBytes { bytes in
            if let destination = bytes.baseAddress {
                data.getBytes(destination, length: bytes.count)
            }
        }
        return result
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

