import SwiftUI

/// Interactive image canvas: displays an image (aspect-fit) and lets the user
/// draw selection rectangles by dragging. Rects are reported normalized
/// (0…1, top-left origin) relative to the image, so callers can map them to
/// pixels regardless of display size.
struct RegionSelector: View {
    let image: NSImage
    @Binding var rects: [CGRect]     // normalized, top-left origin
    var singleSelection = false

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let frame = fittedRect(imageSize: image.size, in: geo.size)
            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)

                ForEach(rects.indices, id: \.self) { i in
                    let r = denorm(rects[i], in: frame)
                    box(r, color: .red)
                }

                if let s = dragStart, let c = dragCurrent {
                    box(CGRect(x: min(s.x, c.x), y: min(s.y, c.y),
                               width: abs(c.x - s.x), height: abs(c.y - s.y)), color: .accentColor)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { v in
                        if dragStart == nil { dragStart = clamp(v.startLocation, frame) }
                        dragCurrent = clamp(v.location, frame)
                    }
                    .onEnded { _ in
                        if let s = dragStart, let c = dragCurrent {
                            let rect = CGRect(x: min(s.x, c.x), y: min(s.y, c.y),
                                              width: abs(c.x - s.x), height: abs(c.y - s.y))
                            let n = normalize(rect, in: frame)
                            if n.width > 0.01, n.height > 0.01 {
                                if singleSelection { rects = [n] } else { rects.append(n) }
                            }
                        }
                        dragStart = nil; dragCurrent = nil
                    }
            )
        }
    }

    private func box(_ r: CGRect, color: Color) -> some View {
        Rectangle()
            .fill(color.opacity(0.22))
            .overlay(Rectangle().strokeBorder(color, lineWidth: 2))
            .frame(width: r.width, height: r.height)
            .offset(x: r.minX, y: r.minY)
    }

    private func fittedRect(imageSize s: CGSize, in c: CGSize) -> CGRect {
        guard s.width > 0, s.height > 0 else { return .zero }
        let scale = min(c.width / s.width, c.height / s.height)
        let w = s.width * scale, h = s.height * scale
        return CGRect(x: (c.width - w) / 2, y: (c.height - h) / 2, width: w, height: h)
    }

    private func clamp(_ p: CGPoint, _ f: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, f.minX), f.maxX), y: min(max(p.y, f.minY), f.maxY))
    }

    /// Absolute rect (in view space) → normalized (top-left) relative to image frame.
    private func normalize(_ r: CGRect, in f: CGRect) -> CGRect {
        guard f.width > 0, f.height > 0 else { return .zero }
        return CGRect(x: (r.minX - f.minX) / f.width, y: (r.minY - f.minY) / f.height,
                      width: r.width / f.width, height: r.height / f.height)
    }

    /// Normalized rect → absolute rect in view space.
    private func denorm(_ n: CGRect, in f: CGRect) -> CGRect {
        CGRect(x: f.minX + n.minX * f.width, y: f.minY + n.minY * f.height,
               width: n.width * f.width, height: n.height * f.height)
    }
}
