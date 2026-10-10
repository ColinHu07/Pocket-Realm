import AVFoundation
import CoreImage
import SwiftUI
import UIKit
import Vision

private let ink = Color(red: 0.055, green: 0.095, blue: 0.10)
private let lime = Color(red: 0.80, green: 0.98, blue: 0.59)
private let paper = Color(red: 0.96, green: 0.96, blue: 0.89)

/// Back camera for photographing a paper drawing. The photo is cropped to the on-screen guide,
/// then straightened if the paper's edges are visible.
@MainActor
final class DrawingCamera: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published private(set) var denied = false
    @Published private(set) var capturing = false
    let session = AVCaptureSession()
    let preview = AVCaptureVideoPreviewLayer()
    private let output = AVCapturePhotoOutput()
    private var configured = false
    private var guide = CGRect.zero
    private var completion: ((UIImage?) -> Void)?

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else { denied = true; return }
        if !configured {
            session.beginConfiguration()
            session.sessionPreset = .photo
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input), session.canAddOutput(output) else {
                session.commitConfiguration()
                denied = true
                return
            }
            session.addInput(input)
            session.addOutput(output)
            session.commitConfiguration()
            preview.session = session
            preview.videoGravity = .resizeAspectFill
            configured = true
        }
        let session = self.session
        await Task.detached { session.startRunning() }.value
    }

    func stop() {
        let session = self.session
        Task.detached { session.stopRunning() }
    }

    /// `guide` is in the preview layer's coordinates.
    func capture(guide: CGRect, completion: @escaping (UIImage?) -> Void) {
        guard configured, !capturing else { return }
        capturing = true
        self.guide = guide
        self.completion = completion
        // Portrait photos keep sensor-oriented pixels plus an EXIF rotation, matching the
        // coordinate space of metadataOutputRectConverted below.
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor in
            let image = data.flatMap(UIImage.init(data:)).flatMap(self.crop)
            self.capturing = false
            self.completion?(image)
            self.completion = nil
        }
    }

    private func crop(_ photo: UIImage) -> UIImage? {
        // A little larger than the guide so the paper's edges survive for straightening.
        let padded = guide.insetBy(dx: -guide.width * 0.06, dy: -guide.height * 0.06)
        let normalized = preview.metadataOutputRectConverted(fromLayerRect: padded)
        guard let cg = photo.cgImage else { return nil }
        let full = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        let region = CGRect(x: normalized.minX * full.width, y: normalized.minY * full.height,
                            width: normalized.width * full.width, height: normalized.height * full.height)
            .intersection(full).integral
        guard !region.isEmpty, let cropped = cg.cropping(to: region) else { return nil }
        let upright = Self.upright(UIImage(cgImage: cropped, scale: 1, orientation: photo.imageOrientation))
        return Self.straighten(upright) ?? upright
    }

    private static func upright(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in image.draw(at: .zero) }
    }

    /// Finds the sheet of paper and flattens it; nil when no clear page edge is visible.
    static func straighten(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.3
        request.maximumAspectRatio = 1
        request.minimumSize = 0.55
        request.minimumConfidence = 0.8
        request.quadratureTolerance = 25
        request.maximumObservations = 1
        try? VNImageRequestHandler(cgImage: cg).perform([request])
        guard let page = request.results?.first, let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        let source = CIImage(cgImage: cg)
        let size = source.extent.size
        func corner(_ point: CGPoint) -> CIVector { CIVector(x: point.x * size.width, y: point.y * size.height) }
        filter.setValue(source, forKey: kCIInputImageKey)
        filter.setValue(corner(page.topLeft), forKey: "inputTopLeft")
        filter.setValue(corner(page.topRight), forKey: "inputTopRight")
        filter.setValue(corner(page.bottomLeft), forKey: "inputBottomLeft")
        filter.setValue(corner(page.bottomRight), forKey: "inputBottomRight")
        guard let flat = filter.outputImage,
              let result = CIContext().createCGImage(flat, from: flat.extent) else { return nil }
        return UIImage(cgImage: result)
    }
}

struct DrawingCaptureView: View {
    /// `.camera` runs its own capture session (before the adventure starts). `.ar` overlays the
    /// running AR view and grabs its camera frame, so room tracking is never interrupted.
    enum Source {
        case camera
        case ar((CGRect) -> UIImage?)
    }

    let title: String
    let prompt: String
    let source: Source
    let onUse: (UIImage) -> Void
    let onClose: () -> Void
    @StateObject private var camera = DrawingCamera()
    @State private var captured: UIImage?
    @State private var failed = false
    @State private var grabbing = false

    private var usesOwnCamera: Bool { if case .camera = source { return true } else { return false } }

    var body: some View {
        GeometryReader { geometry in
            let guide = guideRect(in: geometry.size)
            ZStack {
                if usesOwnCamera || captured != nil { Color.black }
                if let captured {
                    review(captured, guide: guide)
                } else if camera.denied {
                    deniedMessage
                } else {
                    if usesOwnCamera { CameraPreview(layer: camera.preview) }
                    Color.black.opacity(0.55)
                        .mask {
                            ZStack {
                                Rectangle()
                                RoundedRectangle(cornerRadius: 18).frame(width: guide.width, height: guide.height)
                                    .position(x: guide.midX, y: guide.midY).blendMode(.destinationOut)
                            }.compositingGroup()
                        }
                        .allowsHitTesting(false)
                    RoundedRectangle(cornerRadius: 18).stroke(lime, lineWidth: 3)
                        .frame(width: guide.width, height: guide.height).position(x: guide.midX, y: guide.midY)
                        .allowsHitTesting(false)
                    VStack(spacing: 14) {
                        Spacer()
                        Text(failed ? "Couldn't read that photo. Try again in brighter light."
                                    : "Fit your paper inside the box. Bold lines and colors work best.")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(failed ? .orange : paper)
                            .multilineTextAlignment(.center).padding(.horizontal, 32)
                        Button {
                            failed = false
                            switch source {
                            case .camera:
                                camera.capture(guide: guide) { image in
                                    if let image { captured = image } else { failed = true }
                                }
                            case .ar(let grab):
                                grabbing = true
                                if let image = grab(guide) { captured = image } else { failed = true }
                                grabbing = false
                            }
                        } label: {
                            Circle().fill(paper).frame(width: 72, height: 72)
                                .overlay(Circle().stroke(lime, lineWidth: 4).padding(-6))
                                .overlay { if camera.capturing || grabbing { ProgressView().tint(ink) } }
                        }
                        .disabled(camera.capturing || grabbing)
                        .accessibilityLabel("Capture drawing")
                    }.padding(.bottom, 44)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Text(captured == nil ? title : "Use this drawing?")
                            .font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(paper)
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(paper)
                                .frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
                        }.accessibilityLabel("Close")
                    }
                    if captured == nil {
                        Text(prompt).font(.system(size: 14)).foregroundStyle(paper.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(14).background(captured == nil ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.clear),
                                          in: RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 12).padding(.top, 54)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .contentShape(Rectangle())
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .task { if usesOwnCamera { await camera.start() } }
        .onDisappear { if usesOwnCamera { camera.stop() } }
    }

    /// Portrait, roughly the shape of a letter or A4 page, below the prompt card.
    private func guideRect(in size: CGSize) -> CGRect {
        let width = min(size.width * 0.78, size.height * 0.5 * 3 / 4)
        let height = width * 4 / 3
        return CGRect(x: (size.width - width) / 2, y: size.height * 0.5 - height / 2, width: width, height: height)
    }

    private func review(_ image: UIImage, guide: CGRect) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(uiImage: image).resizable().scaledToFit()
                .frame(maxWidth: guide.width, maxHeight: guide.height)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            Text("Codex will sculpt this in Blender and decide what it can do. Then it joins your adventure.")
                .font(.system(size: 14)).foregroundStyle(paper.opacity(0.75)).multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            HStack(spacing: 12) {
                Button { captured = nil } label: {
                    Text("Retake").font(.system(size: 16, weight: .semibold)).foregroundStyle(paper)
                        .frame(maxWidth: .infinity, minHeight: 56).background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 17))
                }
                Button { onUse(image); onClose() } label: {
                    Text("Use drawing").font(.system(size: 16, weight: .semibold)).foregroundStyle(ink)
                        .frame(maxWidth: .infinity, minHeight: 56).background(lime, in: RoundedRectangle(cornerRadius: 17))
                }
            }.padding(.horizontal, 24).padding(.bottom, 44)
        }
    }

    private var deniedMessage: some View {
        VStack(spacing: 14) {
            Text("Allow camera access to photograph your drawing.")
                .font(.system(size: 16)).foregroundStyle(paper).multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }.foregroundStyle(lime)
        }.padding(32)
    }
}

private struct CameraPreview: UIViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview = layer
        view.layer.addSublayer(layer)
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        var preview: CALayer?
        override func layoutSubviews() {
            super.layoutSubviews()
            preview?.frame = bounds
        }
    }
}
