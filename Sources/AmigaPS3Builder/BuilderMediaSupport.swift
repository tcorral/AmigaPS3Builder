import AppKit
import AVFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum PS3ImageSpec: String, Identifiable {
    case icon0
    case pic1

    var id: String { rawValue }

    var width: Int {
        switch self {
        case .icon0: return 320
        case .pic1: return 1_920
        }
    }

    var height: Int {
        switch self {
        case .icon0: return 180
        case .pic1: return 1_080
        }
    }

    var outputFilename: String {
        switch self {
        case .icon0: return "ICON0.PNG"
        case .pic1: return "PIC1.PNG"
        }
    }

    var aspectRatio: CGFloat { CGFloat(width) / CGFloat(height) }

    var minimumPixelSize: (width: Int, height: Int) {
        (width, height)
    }
}

enum PS3ImageIO {
    static func pixelSize(of url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return nil
        }
        return (width, height)
    }

    static func cropsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let folder = base
            .appendingPathComponent("AmigaPS3Builder", isDirectory: true)
            .appendingPathComponent("crops", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func exportCroppedPNG(
        sourceURL: URL,
        spec: PS3ImageSpec,
        zoom: CGFloat,
        offset: CGSize
    ) throws -> URL {
        guard let nsImage = NSImage(contentsOf: sourceURL) else {
            throw BuilderError.ffmpegRequired(sourceURL)
        }
        var proposed = NSRect(origin: .zero, size: nsImage.size)
        guard let cgImage = nsImage.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            throw BuilderError.ffmpegRequired(sourceURL)
        }

        let targetW = spec.width
        let targetH = spec.height
        let imageW = CGFloat(cgImage.width)
        let imageH = CGFloat(cgImage.height)
        let coverScale = max(CGFloat(targetW) / imageW, CGFloat(targetH) / imageH)
        let drawScale = coverScale * max(zoom, 0.25)
        let drawW = imageW * drawScale
        let drawH = imageH * drawScale
        // Core Graphics uses a bottom-left origin; SwiftUI crop offsets use top-left (+y = down).
        let drawX = (CGFloat(targetW) - drawW) / 2 + offset.width
        let drawY = (CGFloat(targetH) - drawH) / 2 - offset.height

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw BuilderError.ffmpegRequired(sourceURL)
        }
        context.interpolationQuality = .high
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: targetW, height: targetH))
        context.draw(cgImage, in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))

        guard let outputImage = context.makeImage() else {
            throw BuilderError.ffmpegRequired(sourceURL)
        }
        let rep = NSBitmapImageRep(cgImage: outputImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw BuilderError.ffmpegRequired(sourceURL)
        }
        let destination = cropsDirectory().appendingPathComponent("\(spec.rawValue)-\(UUID().uuidString).png")
        try data.write(to: destination, options: .atomic)
        return destination
    }
}

struct ImageCropSheet: View {
    let sourceURL: URL
    let spec: PS3ImageSpec
    let onConfirm: (URL) -> Void
    let onCancel: () -> Void

    @State private var zoom: CGFloat = 1
    @State private var dragOffset: CGSize = .zero
    @State private var gestureOffset: CGSize = .zero
    @State private var exportError: String?

    private let frameWidth: CGFloat = 560

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Adjust \(spec.outputFilename)")
                .font(.title2.bold())
            Text("Drag to reposition and use the slider to zoom in or out. The frame matches the PS3 asset size (\(spec.width)×\(spec.height)).")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            CropPreview(
                sourceURL: sourceURL,
                spec: spec,
                frameWidth: frameWidth,
                zoom: zoom,
                offset: CGSize(
                    width: dragOffset.width + gestureOffset.width,
                    height: dragOffset.height + gestureOffset.height
                )
            )
            .frame(width: frameWidth, height: frameWidth / spec.aspectRatio)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor.opacity(0.6), lineWidth: 2)
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        gestureOffset = value.translation
                    }
                    .onEnded { value in
                        dragOffset.width += value.translation.width
                        dragOffset.height += value.translation.height
                        gestureOffset = .zero
                    }
            )

            HStack {
                Text("Zoom")
                Slider(value: $zoom, in: 0.25...3)
                Text(zoom, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }

            if let exportError {
                Text(exportError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Use image") {
                    do {
                        let pixelScale = CGFloat(spec.width) / frameWidth
                        let exported = try PS3ImageIO.exportCroppedPNG(
                            sourceURL: sourceURL,
                            spec: spec,
                            zoom: zoom,
                            offset: CGSize(
                                width: (dragOffset.width + gestureOffset.width) * pixelScale,
                                height: (dragOffset.height + gestureOffset.height) * pixelScale
                            )
                        )
                        onConfirm(exported)
                    } catch {
                        exportError = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 620)
    }
}

private struct CropPreview: View {
    let sourceURL: URL
    let spec: PS3ImageSpec
    let frameWidth: CGFloat
    let zoom: CGFloat
    let offset: CGSize

    var body: some View {
        GeometryReader { proxy in
            if let image = NSImage(contentsOf: sourceURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(zoom)
                    .offset(x: offset.width, y: offset.height)
                    .frame(width: frameWidth, height: proxy.size.height)
                    .clipped()
            } else {
                Text("Could not load image.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct ArtworkAssetRow: View {
    let title: String
    let spec: PS3ImageSpec
    @Binding var exportedPath: String
    @Binding var cropSourceURL: URL?
    @Binding var showCropSheet: Bool
    @Binding var alertMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text("\(spec.width)×\(spec.height) PNG")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !exportedPath.isEmpty, let preview = NSImage(contentsOf: URL(fileURLWithPath: exportedPath)) {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80 / spec.aspectRatio)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Button("Choose image…") {
                    pickImage()
                }
                if !exportedPath.isEmpty {
                    Button("Clear") {
                        exportedPath = ""
                    }
                }
            }
        }
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ["png", "jpg", "jpeg", "webp"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if spec == .pic1, let size = PS3ImageIO.pixelSize(of: url) {
            let min = spec.minimumPixelSize
            if size.width < min.width || size.height < min.height {
                alertMessage =
                    "This image is \(size.width)×\(size.height). PIC1.PNG needs at least \(min.width)×\(min.height). Choose a larger image."
                return
            }
        }
        cropSourceURL = url
        showCropSheet = true
    }
}

struct MusicAssetRow: View {
    @Binding var musicPath: String
    @Binding var showPreview: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("XMB background music (SND0.AT3)")
                        .font(.headline)
                    Text("Choose an MP3 or other audio file; it is converted when you build the package.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose audio…") {
                    chooseMusic()
                }
                if !musicPath.isEmpty {
                    Button("Preview") {
                        showPreview = true
                    }
                    Button("Clear") {
                        musicPath = ""
                    }
                }
            }
            if !musicPath.isEmpty {
                Text(URL(fileURLWithPath: musicPath).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chooseMusic() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ["mp3", "wav", "m4a", "aac", "flac", "at3"].compactMap {
            UTType(filenameExtension: $0)
        }
        if panel.runModal() == .OK, let url = panel.url {
            musicPath = url.path
        }
    }
}

struct AudioPreviewSheet: View {
    let audioURL: URL
    let onClose: () -> Void

    @State private var player: AVPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preview")
                .font(.title2.bold())
            Text(audioURL.lastPathComponent)
                .foregroundStyle(.secondary)
            HStack {
                Button("Play") {
                    player?.play()
                }
                Button("Pause") {
                    player?.pause()
                }
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            player = AVPlayer(url: audioURL)
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
