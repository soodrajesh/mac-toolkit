import SwiftUI

/// One user-created cut region on the waveform, in source-file seconds.
struct CutRegion: Identifiable, Equatable {
    let id = UUID()
    var range: ClosedRange<Double>
    var fadeIn = false
    var fadeOut = false
}

/// Interactive waveform: draws mirrored peak bars, supports pinch-to-zoom +
/// horizontal pan, a click-to-seek playhead, and multiple draggable cut
/// regions (create by dragging empty space, move/resize existing ones).
/// Adapted from RegionSelector's drag skeleton (Sources/Components/RegionSelector.swift),
/// collapsed from 2D rects to 1D time ranges, extended to support more than
/// one simultaneous selection (RegionSelector's Blur mode allows multiple
/// rects but not resize; this needs both, so the interaction logic is
/// reimplemented here rather than reused directly).
struct WaveformView: View {
    let peaks: [Float]
    let duration: Double
    @Binding var regions: [CutRegion]
    @Binding var selectedID: CutRegion.ID?
    var playheadTime: Double = 0
    var onSeek: ((Double) -> Void)? = nil

    @State private var zoom: Double = 1
    @State private var baseZoom: Double = 1
    @State private var mode: DragMode = .none
    @State private var dragStartRegions: [CutRegion] = []
    @State private var newRegionStart: CGFloat?
    @State private var newRegionCurrent: CGFloat?

    private enum DragMode: Equatable { case none, createNew, move(Int), resizeStart(Int), resizeEnd(Int) }
    private let handle: CGFloat = 8
    private let tapThreshold: CGFloat = 3
    private var minSelection: Double { min(0.05, duration / 2) }

    var body: some View {
        GeometryReader { outer in
            ScrollView(.horizontal, showsIndicators: true) {
                let width = max(outer.size.width, outer.size.width * zoom)
                ZStack(alignment: .leading) {
                    Canvas { ctx, size in draw(ctx, size) }
                    ForEach(regions) { region in
                        regionOverlay(region, width: width, height: outer.size.height)
                    }
                    if let s = newRegionStart, let c = newRegionCurrent {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor.opacity(0.2))
                            .frame(width: max(2, abs(c - s)), height: outer.size.height - 8)
                            .offset(x: min(s, c), y: 4)
                    }
                    playheadMark(width: width, height: outer.size.height)
                }
                .frame(width: width, height: outer.size.height)
                .contentShape(Rectangle())
                .gesture(drag(width: width))
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { v in zoom = max(1, min(20, baseZoom * v)) }
                    .onEnded { _ in baseZoom = zoom }
            )
        }
        .frame(height: 140)
    }

    // MARK: Drawing

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        guard !peaks.isEmpty else { return }
        let midY = size.height / 2
        let slot = size.width / CGFloat(peaks.count)
        // Below ~6px per bucket, a gapped/rounded bar's gap rounds away to a
        // sub-pixel sliver (invisible after antialiasing) and just reads as a
        // solid block. Render a smooth continuous silhouette until the user
        // has pinch-zoomed in enough for individual rounded bars to actually
        // show — mirrors how real waveform editors (Logic, Audition) switch
        // from a filled wave shape to discrete sample bars as you zoom in.
        if slot < 6 {
            drawContinuous(ctx, size: size, midY: midY)
        } else {
            drawBars(ctx, size: size, midY: midY, slot: slot)
        }
    }

    private func isInRegion(_ i: Int) -> Bool {
        let t = duration * Double(i) / Double(peaks.count)
        return regions.contains { $0.range.contains(t) }
    }

    private func drawBars(_ ctx: GraphicsContext, size: CGSize, midY: CGFloat, slot: CGFloat) {
        let barWidth = max(1, slot * 0.65)
        let inset = (slot - barWidth) / 2
        for (i, peak) in peaks.enumerated() {
            let x = CGFloat(i) * slot + inset
            let h = max(1.5, CGFloat(peak) * size.height / 2)
            let rect = CGRect(x: x, y: midY - h, width: barWidth, height: h * 2)
            let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
            fill(ctx, path, inRegion: isInRegion(i), top: midY - h, bottom: midY + h)
        }
    }

    /// Groups consecutive buckets with the same in/out-of-region state into
    /// one smooth filled polygon each, so region boundaries still read as a
    /// clean color change without any seam between adjacent runs.
    private func drawContinuous(_ ctx: GraphicsContext, size: CGSize, midY: CGFloat) {
        let n = peaks.count
        guard n > 0 else { return }
        let dx = size.width / CGFloat(n)
        var runStart = 0
        var runInRegion = isInRegion(0)
        for i in 1...n {
            let cur = i < n ? isInRegion(i) : !runInRegion
            if cur != runInRegion || i == n {
                drawRun(ctx, from: runStart, to: i - 1, dx: dx, midY: midY, size: size, inRegion: runInRegion)
                runStart = i
                if i < n { runInRegion = cur }
            }
        }
    }

    private func drawRun(_ ctx: GraphicsContext, from: Int, to: Int, dx: CGFloat, midY: CGFloat, size: CGSize, inRegion: Bool) {
        guard to >= from else { return }
        func height(_ i: Int) -> CGFloat { max(1.5, CGFloat(peaks[i]) * size.height / 2) }
        var path = Path()
        path.move(to: CGPoint(x: CGFloat(from) * dx, y: midY - height(from)))
        for i in from...to { path.addLine(to: CGPoint(x: CGFloat(i) * dx, y: midY - height(i))) }
        path.addLine(to: CGPoint(x: CGFloat(to) * dx, y: midY + height(to)))
        for i in stride(from: to, through: from, by: -1) { path.addLine(to: CGPoint(x: CGFloat(i) * dx, y: midY + height(i))) }
        path.closeSubpath()
        fill(ctx, path, inRegion: inRegion, top: 0, bottom: size.height)
    }

    private func fill(_ ctx: GraphicsContext, _ path: Path, inRegion: Bool, top: CGFloat, bottom: CGFloat) {
        if inRegion {
            let gradient = Gradient(colors: [Color.accentColor.opacity(0.85), Color.accentColor])
            ctx.fill(path, with: .linearGradient(gradient,
                startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)))
        } else {
            ctx.fill(path, with: .color(Color.secondary.opacity(0.4)))
        }
    }

    @ViewBuilder
    private func regionOverlay(_ region: CutRegion, width: CGFloat, height: CGFloat) -> some View {
        let startX = x(for: region.range.lowerBound, width: width)
        let endX = x(for: region.range.upperBound, width: width)
        let isSelected = region.id == selectedID
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.accentColor.opacity(isSelected ? 0.16 : 0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.yellow.opacity(isSelected ? 0.9 : 0), lineWidth: 1.5)
            )
            .frame(width: max(2, endX - startX), height: height - 8)
            .offset(x: startX, y: 4)
        if isSelected {
            handleBar(at: startX, height: height)
            handleBar(at: endX, height: height)
        }
    }

    private func handleBar(at x: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(Color.yellow)
            .frame(width: 4, height: height - 16)
            .offset(x: x - 2, y: 8)
    }

    @ViewBuilder
    private func playheadMark(width: CGFloat, height: CGFloat) -> some View {
        let px = x(for: playheadTime, width: width)
        ZStack(alignment: .top) {
            Circle()
                .fill(Color.white)
                .frame(width: 7, height: 7)
                .offset(x: px - 3.5, y: -1)
            Rectangle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 1, height: height)
                .offset(x: px)
        }
    }

    // MARK: Gesture

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if mode == .none {
                    mode = resolveMode(at: v.startLocation.x, width: width)
                    dragStartRegions = regions
                    if case .move(let i) = mode { selectedID = regions[i].id }
                    if case .resizeStart(let i) = mode { selectedID = regions[i].id }
                    if case .resizeEnd(let i) = mode { selectedID = regions[i].id }
                    if case .createNew = mode { newRegionStart = v.startLocation.x }
                }
                if case .createNew = mode {
                    newRegionCurrent = v.location.x
                } else {
                    applyDrag(translationX: v.translation.width, width: width)
                }
            }
            .onEnded { v in
                let dragDistance = abs(v.translation.width)
                if case .createNew = mode {
                    if dragDistance < tapThreshold {
                        onSeek?(time(for: v.startLocation.x, width: width))
                    } else if let s = newRegionStart, let c = newRegionCurrent {
                        let startT = time(for: min(s, c), width: width)
                        let endT = time(for: max(s, c), width: width)
                        if endT - startT >= minSelection {
                            let region = CutRegion(range: startT...endT)
                            regions.append(region)
                            selectedID = region.id
                        }
                    }
                }
                newRegionStart = nil; newRegionCurrent = nil
                mode = .none
            }
    }

    private func resolveMode(at x: CGFloat, width: CGFloat) -> DragMode {
        for (i, region) in regions.enumerated() {
            let startX = self.x(for: region.range.lowerBound, width: width)
            let endX = self.x(for: region.range.upperBound, width: width)
            if abs(x - startX) < handle { return .resizeStart(i) }
            if abs(x - endX) < handle { return .resizeEnd(i) }
            if x > startX, x < endX { return .move(i) }
        }
        return .createNew
    }

    private func applyDrag(translationX: CGFloat, width: CGFloat) {
        guard width > 0, duration > 0 else { return }
        let deltaSeconds = Double(translationX / width) * duration
        switch mode {
        case .move(let i):
            guard dragStartRegions.indices.contains(i) else { return }
            let start = dragStartRegions[i]
            let span = start.range.upperBound - start.range.lowerBound
            var newStart = start.range.lowerBound + deltaSeconds
            newStart = min(max(newStart, 0), duration - span)
            regions[i].range = newStart...(newStart + span)
        case .resizeStart(let i):
            guard dragStartRegions.indices.contains(i) else { return }
            let start = dragStartRegions[i]
            let newStart = min(max(start.range.lowerBound + deltaSeconds, 0), start.range.upperBound - minSelection)
            regions[i].range = newStart...start.range.upperBound
        case .resizeEnd(let i):
            guard dragStartRegions.indices.contains(i) else { return }
            let start = dragStartRegions[i]
            let newEnd = max(min(start.range.upperBound + deltaSeconds, duration), start.range.lowerBound + minSelection)
            regions[i].range = start.range.lowerBound...newEnd
        case .none, .createNew:
            break
        }
    }

    private func x(for time: Double, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(time / duration) * width
    }

    private func time(for x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(max(Double(x / width) * duration, 0), duration)
    }
}
