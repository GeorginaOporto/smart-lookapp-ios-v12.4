import SwiftUI
import UIKit
import Foundation

/// One isolated component produced by the Mobile-SAM touch extraction flow.
struct MVDExtractedTrainingImage: Identifiable {
    let id = UUID()
    let sourceIndex: Int
    let image: UIImage
}

/// Image preparation shared by the iOS training UI.
enum MVDTouchImageExtractor {
    static let androidSafeBitmapSize: CGFloat = 1024
    private static let androidCropHalfWidth: CGFloat = 0.35
    private static let androidCropHalfHeight: CGFloat = 0.35

    static func prepare(_ image: UIImage) -> UIImage {
        let normalized = normalizedImage(image)
        let pixelWidth = CGFloat(normalized.cgImage?.width ?? Int(normalized.size.width))
        let pixelHeight = CGFloat(normalized.cgImage?.height ?? Int(normalized.size.height))
        let scale = min(
            1,
            min(
                androidSafeBitmapSize / max(pixelWidth, 1),
                androidSafeBitmapSize / max(pixelHeight, 1)
            )
        )
        guard scale < 1 else { return normalized }
        return rendered(normalized, pixelSize: CGSize(width: pixelWidth * scale, height: pixelHeight * scale))
    }

    static func extractComponentAroundTouch(_ image: UIImage, pixelPoint: CGPoint) async -> UIImage? {
        let source = normalizedImage(image)
        let size = pixelSize(of: source)
        guard size.width > 0, size.height > 0 else { return nil }
        // Small parts occupy too few pixels when SAM sees the whole photo.
        // Run the model on a generous local window around the touch so the
        // selected part has enough resolution, while keeping all nearby pieces
        // that belong to the same assembly.
        guard let sourceCGImage = source.cgImage else { return nil }
        let windowWidth = max(1, min(Int(size.width), Int(size.width * 0.52)))
        let windowHeight = max(1, min(Int(size.height), Int(size.height * 0.52)))
        let centerX = min(max(Int(pixelPoint.x.rounded()), 0), sourceCGImage.width - 1)
        let centerY = min(max(Int(pixelPoint.y.rounded()), 0), sourceCGImage.height - 1)
        let left = min(max(centerX - windowWidth / 2, 0), sourceCGImage.width - windowWidth)
        let top = min(max(centerY - windowHeight / 2, 0), sourceCGImage.height - windowHeight)
        let cropRect = CGRect(x: left, y: top, width: windowWidth, height: windowHeight)
        guard let croppedCGImage = sourceCGImage.cropping(to: cropRect) else { return nil }
        let localSource = UIImage(cgImage: croppedCGImage, scale: 1, orientation: .up)
        let localPoint = CGPoint(
            x: min(max(CGFloat(centerX - left) / CGFloat(windowWidth), 0), 1),
            y: min(max(CGFloat(centerY - top) / CGFloat(windowHeight), 0), 1)
        )
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Always use the enlarged touch window for this flow. A full
                // frame pass can look compact while still containing the wrong
                // object, which is especially common with small parts.
                let isolated = MVDMobileSAM.shared.extract(localSource, normalizedPoint: localPoint)
                continuation.resume(returning: isolated)
            }
        }
    }

    /// Synchronous variant for UIKit/Vision callers that already run on a
    /// background queue. It uses the same enlarged touch window as the async
    /// extraction sheet.
    static func extractComponentAroundTouchSync(_ image: UIImage, pixelPoint: CGPoint) -> UIImage? {
        let source = normalizedImage(image)
        let size = pixelSize(of: source)
        guard size.width > 0, size.height > 0, let sourceCGImage = source.cgImage else { return nil }
        let windowWidth = max(1, min(Int(size.width), Int(size.width * 0.52)))
        let windowHeight = max(1, min(Int(size.height), Int(size.height * 0.52)))
        let centerX = min(max(Int(pixelPoint.x.rounded()), 0), sourceCGImage.width - 1)
        let centerY = min(max(Int(pixelPoint.y.rounded()), 0), sourceCGImage.height - 1)
        let left = min(max(centerX - windowWidth / 2, 0), sourceCGImage.width - windowWidth)
        let top = min(max(centerY - windowHeight / 2, 0), sourceCGImage.height - windowHeight)
        let rect = CGRect(x: left, y: top, width: windowWidth, height: windowHeight)
        guard let cropped = sourceCGImage.cropping(to: rect) else { return nil }
        let localSource = UIImage(cgImage: cropped, scale: 1, orientation: .up)
        let localPoint = CGPoint(
            x: min(max(CGFloat(centerX - left) / CGFloat(windowWidth), 0), 1),
            y: min(max(CGFloat(centerY - top) / CGFloat(windowHeight), 0), 1)
        )
        return MVDMobileSAM.shared.extract(localSource, normalizedPoint: localPoint)
    }

    static func cropAroundTouch(_ image: UIImage, pixelPoint: CGPoint) -> UIImage? {
        let source = normalizedImage(image)
        guard let cgImage = source.cgImage else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let cropRect = cropRectAroundTouch(source, pixelPoint: pixelPoint).intersection(bounds).integral
        guard cropRect.width > 0, cropRect.height > 0, let cropped = cgImage.cropping(to: cropRect) else {
            return nil
        }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }

    static func cropRectAroundTouch(_ image: UIImage, pixelPoint: CGPoint) -> CGRect {
        let size = pixelSize(of: image)
        let width = max(Int(size.width.rounded()), 1)
        let height = max(Int(size.height.rounded()), 1)
        let centerX = Int(pixelPoint.x.rounded()).clamped(to: 0...(width - 1))
        let centerY = Int(pixelPoint.y.rounded()).clamped(to: 0...(height - 1))
        let halfWidth = max(1, Int(CGFloat(width) * androidCropHalfWidth))
        let halfHeight = max(1, Int(CGFloat(height) * androidCropHalfHeight))
        let left = max(centerX - halfWidth, 0)
        let top = max(centerY - halfHeight, 0)
        let right = min(centerX + halfWidth, width)
        let bottom = min(centerY + halfHeight, height)
        return CGRect(x: left, y: top, width: max(right - left, 1), height: max(bottom - top, 1))
    }

    static func pixelSize(of image: UIImage) -> CGSize {
        if let cgImage = image.cgImage {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }
        return CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    static func normalizedImage(_ image: UIImage) -> UIImage {
        let alreadyNormalized = image.imageOrientation == .up && image.scale == 1
        if alreadyNormalized { return image }
        let orientedSize = CGSize(
            width: max(image.size.width * image.scale, 1),
            height: max(image.size.height * image.scale, 1)
        )
        return rendered(image, pixelSize: orientedSize)
    }

    private static func rendered(_ image: UIImage, pixelSize: CGSize) -> UIImage {
        var format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: pixelSize))
        }
    }
}

// MARK: - UIKit image view: pixel-accurate tap (same idea as Android ImageView + OnTouch)

struct MVDTappableImageView: UIViewRepresentable {
    let image: UIImage
    let zoomScale: CGFloat
    let pan: CGSize
    var onTapPixel: (CGPoint) -> Void

    func makeUIView(context: Context) -> MVDImageTouchView {
        let view = MVDImageTouchView()
        view.isUserInteractionEnabled = true
        view.backgroundColor = .black
        view.clipsToBounds = true
        view.onTapPixel = onTapPixel
        view.image = image
        view.zoomScale = zoomScale
        view.panOffset = pan
        return view
    }

    func updateUIView(_ uiView: MVDImageTouchView, context: Context) {
        uiView.image = image
        uiView.zoomScale = zoomScale
        uiView.panOffset = pan
        uiView.onTapPixel = onTapPixel
        uiView.setNeedsDisplay()
    }
}

final class MVDImageTouchView: UIView {
    var image: UIImage? { didSet { setNeedsDisplay() } }
    var zoomScale: CGFloat = 1
    var panOffset: CGSize = .zero
    var onTapPixel: ((CGPoint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func fitRect(in bounds: CGRect, imageSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return .zero
        }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(
            x: (bounds.width - w) / 2,
            y: (bounds.height - h) / 2,
            width: w,
            height: h
        )
    }

    override func draw(_ rect: CGRect) {
        guard let image else { return }
        let pixelSize = MVDTouchImageExtractor.pixelSize(of: image)
        let base = fitRect(in: bounds, imageSize: pixelSize)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let scaled = CGRect(
            x: center.x + (base.minX - center.x) * zoomScale + panOffset.width,
            y: center.y + (base.minY - center.y) * zoomScale + panOffset.height,
            width: base.width * zoomScale,
            height: base.height * zoomScale
        )
        image.draw(in: scaled)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let image else { return }
        let location = gesture.location(in: self)
        let pixelSize = MVDTouchImageExtractor.pixelSize(of: image)
        let base = fitRect(in: bounds, imageSize: pixelSize)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let safeZoom = max(zoomScale, 0.0001)

        let unzoomed = CGPoint(
            x: center.x + (location.x - panOffset.width - center.x) / safeZoom,
            y: center.y + (location.y - panOffset.height - center.y) / safeZoom
        )

        let localX = unzoomed.x - base.minX
        let localY = unzoomed.y - base.minY
        guard localX >= 0, localY >= 0, localX <= base.width, localY <= base.height else { return }

        let px = (localX / max(base.width, 1)) * pixelSize.width
        let py = (localY / max(base.height, 1)) * pixelSize.height
        let point = CGPoint(
            x: min(max(px, 0), pixelSize.width - 1),
            y: min(max(py, 0), pixelSize.height - 1)
        )
        onTapPixel?(point)
    }
}

// MARK: - Sheet

struct MVDImageExtractionSheet: View {
    let images: [UIImage]
    let onFinish: ([MVDExtractedTrainingImage]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var activeIndex = 0
    @State private var extractedImages: [Int: UIImage] = [:]
    @State private var selectedPixelPoint: CGPoint?
    @State private var zoomScale: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var committedPan: CGSize = .zero
    @State private var isSegmenting = false

    private let maxZoom: CGFloat = 12

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("TOCÁ EL COMPONENTE QUE QUERÉS EXTRAER")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.blue)
                    .multilineTextAlignment(.center)

                Text("Tocá solo el objeto. Usá zoom si hace falta.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                GeometryReader { geometry in
                    let image = MVDTouchImageExtractor.prepare(images[activeIndex])
                    let pixelSize = MVDTouchImageExtractor.pixelSize(of: image)

                    ZStack {
                        MVDTappableImageView(
                            image: image,
                            zoomScale: zoomScale,
                            pan: pan,
                            onTapPixel: { pixelPoint in
                                handleTap(pixelPoint: pixelPoint, image: image)
                            }
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)

                        if let selectedPixelPoint {
                            let marker = markerPosition(
                                pixel: selectedPixelPoint,
                                pixelSize: pixelSize,
                                container: geometry.size
                            )
                            Circle()
                                .stroke(Color.cyan, lineWidth: 2)
                                .frame(width: 28, height: 28)
                                .position(marker)
                                .allowsHitTesting(false)
                        }

                        if isSegmenting {
                            ProgressView("SEGMENTANDO CON IA…")
                                .tint(.blue)
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .allowsHitTesting(false)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                zoomScale = (baseZoom * value).clamped(to: 1...maxZoom)
                            }
                            .onEnded { _ in
                                baseZoom = zoomScale
                                committedPan = clampedPan(committedPan, zoom: zoomScale, imageSize: pixelSize, container: geometry.size)
                                pan = committedPan
                            }
                    )
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                guard zoomScale > 1 else { return }
                                pan = clampedPan(
                                    CGSize(
                                        width: committedPan.width + value.translation.width,
                                        height: committedPan.height + value.translation.height
                                    ),
                                    zoom: zoomScale,
                                    imageSize: pixelSize,
                                    container: geometry.size
                                )
                            }
                            .onEnded { _ in
                                committedPan = pan
                            }
                    )
                }
                .frame(minHeight: 280)

                if let extracted = extractedImages[activeIndex] {
                    HStack(spacing: 10) {
                        Image(uiImage: extracted)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 88, height: 64)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text("SILUETA — \(String(format: "%.0f", extracted.size.width)) × \(String(format: "%.0f", extracted.size.height)) px")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                        Spacer()
                    }
                } else {
                    Text("Todavía no hay recorte. Tocá la parte exacta de la imagen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if images.count > 1 {
                    HStack {
                        Button("ANTERIOR") { move(by: -1) }
                            .disabled(isSegmenting || activeIndex == 0)
                        Spacer()
                        Text("IMAGEN \(activeIndex + 1) / \(images.count)")
                            .font(.caption.weight(.bold))
                        Spacer()
                        Button("SIGUIENTE") { move(by: 1) }
                            .disabled(isSegmenting || activeIndex == images.count - 1)
                    }
                }

                Button {
                    let results = extractedImages.keys.sorted().compactMap { index in
                        extractedImages[index].map {
                            MVDExtractedTrainingImage(sourceIndex: index, image: $0)
                        }
                    }
                    onFinish(results)
                    dismiss()
                } label: {
                    Label("USAR RECORTES SELECCIONADOS", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(extractedImages.isEmpty)
            }
            .padding(16)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("EXTRACCIÓN DE IMAGEN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("CANCELAR") { dismiss() }
                }
            }
        }
    }

    private func handleTap(pixelPoint: CGPoint, image: UIImage) {
        guard !isSegmenting else { return }
        selectedPixelPoint = pixelPoint
        let index = activeIndex

        if let fallback = MVDTouchImageExtractor.cropAroundTouch(image, pixelPoint: pixelPoint) {
            extractedImages[index] = fallback
        }
        isSegmenting = true

        Task {
            let isolated = await MVDTouchImageExtractor.extractComponentAroundTouch(
                image,
                pixelPoint: pixelPoint
            )
            await MainActor.run {
                if let isolated {
                    extractedImages[index] = isolated
                }
                isSegmenting = false
            }
        }
    }

    private func markerPosition(pixel: CGPoint, pixelSize: CGSize, container: CGSize) -> CGPoint {
        let scale = min(container.width / max(pixelSize.width, 1), container.height / max(pixelSize.height, 1))
        let dw = pixelSize.width * scale
        let dh = pixelSize.height * scale
        let origin = CGPoint(x: (container.width - dw) / 2, y: (container.height - dh) / 2)
        let base = CGPoint(
            x: origin.x + (pixel.x / max(pixelSize.width, 1)) * dw,
            y: origin.y + (pixel.y / max(pixelSize.height, 1)) * dh
        )
        let center = CGPoint(x: container.width / 2, y: container.height / 2)
        return CGPoint(
            x: center.x + (base.x - center.x) * zoomScale + pan.width,
            y: center.y + (base.y - center.y) * zoomScale + pan.height
        )
    }

    private func clampedPan(_ pan: CGSize, zoom: CGFloat, imageSize: CGSize, container: CGSize) -> CGSize {
        let scale = min(container.width / max(imageSize.width, 1), container.height / max(imageSize.height, 1))
        let dw = imageSize.width * scale
        let dh = imageSize.height * scale
        let maxX = max((dw * zoom - dw) / 2, 0)
        let maxY = max((dh * zoom - dh) / 2, 0)
        return CGSize(
            width: pan.width.clamped(to: -maxX...maxX),
            height: pan.height.clamped(to: -maxY...maxY)
        )
    }

    private func move(by delta: Int) {
        let next = (activeIndex + delta).clamped(to: 0...(images.count - 1))
        guard next != activeIndex else { return }
        activeIndex = next
        selectedPixelPoint = nil
        zoomScale = 1
        baseZoom = 1
        pan = .zero
        committedPan = .zero
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
