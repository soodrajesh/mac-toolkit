import SwiftUI

/// Image preview with click-and-drag selection rectangle. The image is always
/// scaled to fit the box; the selection is stored normalized (0...1) in image
/// space so callers can map it straight to pixel coordinates for cropping.
struct SelectableImagePreview: View {
    let image: NSImage
    @Binding var selection: CGRect?
    var caption: String? = nil
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let fitted = fittedRect(imageSize: image.size, in: geo.size)
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.12))

                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: fitted.width, height: fitted.height)
                        .position(x: fitted.midX, y: fitted.midY)

                    if let start = dragStart, let current = dragCurrent {
                        selectionOverlay(normalizedDragRect(start: start, end: current, clampTo: fitted), color: .accentColor)
                    } else if let selection {
                        selectionOverlay(denormalize(selection, in: fitted), color: .green)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            if dragStart == nil { dragStart = clamp(value.startLocation, to: fitted) }
                            dragCurrent = clamp(value.location, to: fitted)
                        }
                        .onEnded { _ in
                            if let start = dragStart, let current = dragCurrent {
                                let viewRect = normalizedDragRect(start: start, end: current, clampTo: fitted)
                                selection = viewRect.width > 4 && viewRect.height > 4
                                    ? normalize(viewRect, in: fitted) : nil
                            }
                            dragStart = nil; dragCurrent = nil
                        }
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active: NSCursor.crosshair.push()
                    case .ended: NSCursor.arrow.pop()
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.25)))

            HStack(spacing: 12) {
                if let caption { Text(caption).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if selection != nil {
                    Button("Clear Selection") { selection = nil }
                        .font(.caption).controlSize(.small).buttonStyle(.bordered)
                }
            }
        }
    }

    private func fittedRect(imageSize: NSSize, in boxSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, boxSize.width > 0, boxSize.height > 0 else {
            return CGRect(origin: .zero, size: boxSize)
        }
        let scale = min(boxSize.width / imageSize.width, boxSize.height / imageSize.height)
        let w = imageSize.width * scale, h = imageSize.height * scale
        return CGRect(x: (boxSize.width - w) / 2, y: (boxSize.height - h) / 2, width: w, height: h)
    }

    private func clamp(_ p: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, rect.minX), rect.maxX), y: min(max(p.y, rect.minY), rect.maxY))
    }

    private func normalizedDragRect(start: CGPoint, end: CGPoint, clampTo rect: CGRect) -> CGRect {
        let a = clamp(start, to: rect), b = clamp(end, to: rect)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func normalize(_ viewRect: CGRect, in fitted: CGRect) -> CGRect {
        CGRect(x: (viewRect.minX - fitted.minX) / fitted.width,
               y: (viewRect.minY - fitted.minY) / fitted.height,
               width: viewRect.width / fitted.width,
               height: viewRect.height / fitted.height)
    }

    private func denormalize(_ norm: CGRect, in fitted: CGRect) -> CGRect {
        CGRect(x: fitted.minX + norm.minX * fitted.width,
               y: fitted.minY + norm.minY * fitted.height,
               width: norm.width * fitted.width,
               height: norm.height * fitted.height)
    }

    @ViewBuilder
    private func selectionOverlay(_ rect: CGRect, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .strokeBorder(color, lineWidth: 2)
            .background(color.opacity(0.08))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}
