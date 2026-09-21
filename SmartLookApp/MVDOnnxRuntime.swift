import Foundation
import UIKit
import onnxruntime_objc

/// Local ONNX Runtime adapter. Models and inference stay on the iPad.
final class MVDOnnxEmbedding {
    static let shared = MVDOnnxEmbedding()

    private let lock = NSLock()
    private var session: ORTSession?
    private var environment: ORTEnv?
    private(set) var lastError: String?

    private init() {}

    static func cosine(_ lhs: [Float], _ rhs: [Float]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot: Float = 0
        var left: Float = 0
        var right: Float = 0
        for (a, b) in zip(lhs, rhs) {
            dot += a * b
            left += a * a
            right += b * b
        }
        guard left > 0, right > 0 else { return 0 }
        return Double(dot / (sqrt(left) * sqrt(right)))
    }

    func vector(for image: UIImage) -> [Float]? {
        guard let input = Self.preprocess(image) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let session = loadSessionLocked() else { return nil }
        do {
            let bytes = input.withUnsafeBytes { raw in
                NSMutableData(bytes: raw.baseAddress!, length: input.count * MemoryLayout<Float>.size)
            }
            let value = try ORTValue(tensorData: bytes, elementType: .float, shape: [1, 3, 224, 224])
            let outputs = try session.run(withInputs: ["input": value], outputNames: ["embedding"], runOptions: nil)
            guard let output = outputs["embedding"] else { return nil }
            let data = try output.tensorData()
            let pointer = data.bytes.assumingMemoryBound(to: Float.self)
            return Array(UnsafeBufferPointer(
                start: pointer,
                count: data.length / MemoryLayout<Float>.size
            ))
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func loadSessionLocked() -> ORTSession? {
        if let session { return session }
        guard let modelPath = Bundle.main.path(forResource: "mobilenetv2_embedding", ofType: "onnx") else {
            lastError = "mobilenetv2_embedding.onnx no está en el bundle"
            return nil
        }
        do {
            let env = try ORTEnv(loggingLevel: .warning)
            let options = try ORTSessionOptions()
            session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: options)
            environment = env
            return session
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private static func preprocess(_ image: UIImage) -> [Float]? {
        let size = CGSize(width: 224, height: 224)
        let renderer = UIGraphicsImageRenderer(size: size)
        // The embedding query must see the same upright pixels as the
        // extractor. Camera images can carry rotation only in EXIF metadata.
        let source = image.normalizedForVision()
        let resized = renderer.image { _ in source.draw(in: CGRect(origin: .zero, size: size)) }
        guard let cgImage = resized.cgImage,
              let context = CGContext(data: nil, width: 224, height: 224, bitsPerComponent: 8,
                                      bytesPerRow: 224 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 224, height: 224))
        let pixels = data.bindMemory(to: UInt8.self, capacity: 224 * 224 * 4)
        // Match the MobileNet preprocessing used by the Android v12.4
        // search engine: RGB in [0, 1], then ImageNet channel normalization.
        let mean: [Float] = [0.485, 0.456, 0.406]
        let standardDeviation: [Float] = [0.229, 0.224, 0.225]
        var result = Array(repeating: Float(0), count: 3 * 224 * 224)
        for y in 0..<224 {
            for x in 0..<224 {
                let pixel = (y * 224 + x) * 4
                let index = y * 224 + x
                let red = Float(pixels[pixel]) / 255.0
                let green = Float(pixels[pixel + 1]) / 255.0
                let blue = Float(pixels[pixel + 2]) / 255.0
                result[index] = (red - mean[0]) / standardDeviation[0]
                result[224 * 224 + index] = (green - mean[1]) / standardDeviation[1]
                result[2 * 224 * 224 + index] = (blue - mean[2]) / standardDeviation[2]
            }
        }

    }
}
