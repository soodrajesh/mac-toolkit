import SwiftUI

/// Interactive image canvas. Draws an image (aspect-fit) and lets the user create
/// selection rectangles by dragging. Rects are reported normalized (0…1, top-left
/// origin) relative to the image.
///
/// In `singleSelection` (crop) mode the rectangle is editable Paint-style: drag a
/// corner/edge handle to resize, drag inside to move, drag empty space for a new box.
/// `onSelection` streams the live normalized rect (or nil) so callers can show its size.
struct RegionSelector: View {
    let image: NSImage
    @Binding var rects: [CGRect]
    var singleSelection = false
    var onSelection: ((CGRect?) -> Void)? = nil

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var mode: DragMode = .none
    @State private var startRect: CGRect = .zero   // absolute, captured at gesture start

    private enum DragMode { case none, new, move, resize(Edge) }
    private struct Edge: Equatable { var left = false; var right = false; var top = false; var bottom = false }
    private let handle: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let frame = fittedRect(imageSize: image.size, in: geo.size)
            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable().scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)

                ForEach(rects.indices, id: \.self) { i in
                    let r = denorm(rects[i], in: frame)
                    box(r, color: .red)
                    if singleSelection { handles(for: r) }
                }
                if let s = dragStart, let c = dragCurrent, case .new = mode {
                    box(CGRect(x: min(s.x, c.x), y: min(s.y, c.y),
                               width: abs(c.x - s.x), height: abs(c.y - s.y)), color: .accentColor)
                }
            }
            .contentShape(Rectangle())
            .gesture(drag(frame: frame))
        }
    }

    // MARK: Gesture

    private func drag(frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                if dragStart == nil {
                    dragStart = v.startLocation
                    mode = resolveMode(at: v.startLocation, frame: frame)
                    startRect = singleSelection && !rects.isEmpty ? denorm(rects[0], in: frame) : .zero
                }
                dragCurrent = clamp(v.location, frame)
                applyDrag(translation: v.translation, frame: frame)
            }
            .onEnded { _ in
                if case .new = mode, let s = dragStart, let c = dragCurrent {
                    let rect = CGRect(x: min(s.x, c.x), y: min(s.y, c.y),
                                      width: abs(c.x - s.x), height: abs(c.y - s.y))
                    let n = normalize(rect, in: frame)
                    if n.width > 0.01, n.height > 0.01 {
                        if singleSelection { rects = [n]; onSelection?(n) } else { rects.append(n) }
                    }
                }
                dragStart = nil; dragCurrent = nil; mode = .none
            }
    }

    private func resolveMode(at p: CGPoint, frame: CGRect) -> DragMode {
        guard singleSelection, !rects.isEmpty else { return .new }
        let r = denorm(rects[0], in: frame)
        let nearL = abs(p.x - r.minX) < handle, nearR = abs(p.x - r.maxX) < handle
        let nearT = abs(p.y - r.minY) < handle, nearB = abs(p.y - r.maxY) < handle
        let withinX = p.x > r.minX - handle && p.x < r.maxX + handle
        let withinY = p.y > r.minY - handle && p.y < r.maxY + handle
        if (nearL || nearR || nearT || nearB) && withinX && withinY {
            return .resize(Edge(left: nearL, right: nearR, top: nearT, bottom: nearB))
        }
        if r.insetBy(dx: -2, dy: -2).contains(p) { return .move }
        return .new
    }

    private func applyDrag(translation t: CGSize, frame: CGRect) {
        guard singleSelection else { return }
        switch mode {
        case .move:
            var r = startRect.offsetBy(dx: t.width, dy: t.height)
            r.origin.x = min(max(r.minX, frame.minX), frame.maxX - r.width)
            r.origin.y = min(max(r.minY, frame.minY), frame.maxY - r.height)
            commit(r, frame: frame)
        case .resize(let e):
            var minX = startRect.minX, minY = startRect.minY
            var maxX = startRect.maxX, maxY = startRect.maxY
            if e.left { minX = startRect.minX + t.width }
            if e.right { maxX = startRect.maxX + t.width }
            if e.top { minY = startRect.minY + t.height }
            if e.bottom { maxY = startRect.maxY + t.height }
            let r = CGRect(x: min(minX, maxX), y: min(minY, maxY),
                           width: abs(maxX - minX), height: abs(maxY - minY))
                .intersection(frame)
            if r.width > 4, r.height > 4 { commit(r, frame: frame) }
        default:
            break
        }
    }

    private func commit(_ absRect: CGRect, frame: CGRect) {
        let n = normalize(absRect, in: frame)
        rects = [n]
        onSelection?(n)
    }

    // MARK: Views

    private func box(_ r: CGRect, color: Color) -> some View {
        Rectangle()
            .fill(color.opacity(0.22))
            .overlay(Rectangle().strokeBorder(color, lineWidth: 2))
            .frame(width: r.width, height: r.height)
            .offset(x: r.minX, y: r.minY)
    }

    private func handles(for r: CGRect) -> some View {
        let pts: [CGPoint] = [
            CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.minX, y: r.midY), CGPoint(x: r.maxX, y: r.midY),
            CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY),
        ]
        return ForEach(pts.indices, id: \.self) { i in
            Rectangle()
                .fill(Color.white)
                .overlay(Rectangle().strokeBorder(Color.red, lineWidth: 1))
                .frame(width: 8, height: 8)
                .offset(x: pts[i].x - 4, y: pts[i].y - 4)
        }
    }

    // MARK: Coordinate math

    private func fittedRect(imageSize s: CGSize, in c: CGSize) -> CGRect {
        guard s.width > 0, s.height > 0 else { return .zero }
        let scale = min(c.width / s.width, c.height / s.height)
        let w = s.width * scale, h = s.height * scale
        return CGRect(x: (c.width - w) / 2, y: (c.height - h) / 2, width: w, height: h)
    }
    private func clamp(_ p: CGPoint, _ f: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, f.minX), f.maxX), y: min(max(p.y, f.minY), f.maxY))
    }
    private func normalize(_ r: CGRect, in f: CGRect) -> CGRect {
        guard f.width > 0, f.height > 0 else { return .zero }
        return CGRect(x: (r.minX - f.minX) / f.width, y: (r.minY - f.minY) / f.height,
                      width: r.width / f.width, height: r.height / f.height)
    }
    private func denorm(_ n: CGRect, in f: CGRect) -> CGRect {
        CGRect(x: f.minX + n.minX * f.width, y: f.minY + n.minY * f.height,
               width: n.width * f.width, height: n.height * f.height)
    }
}
