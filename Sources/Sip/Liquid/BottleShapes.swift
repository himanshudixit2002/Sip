import SwiftUI

/// Bottle silhouettes, drawn in a fixed 100 × 220 design space. Everything the
/// simulation does — levels, bubbles, droplets — happens in these units, and
/// the renderer scales the result to whatever size the view is.
struct BottleGeometry {
    static let designSize = CGSize(width: 100, height: 220)
    static let centerX: CGFloat = 50

    enum Cap { case screw, flip, cork, lid, none }

    let style: BottleStyle
    /// Identifies this exact shape (style, or the designer's settings).
    let id: String
    /// The outside of the glass.
    let outer: Path
    /// The inside of the glass; the liquid is clipped to this.
    let inner: Path
    /// Liquid surface at 100% of the goal.
    let fullY: CGFloat
    /// Liquid surface at 0%: the inside of the base.
    let emptyY: CGFloat
    /// Where poured droplets appear.
    let mouthY: CGFloat
    let cap: Cap
    let capRect: CGRect
    /// The straight-sided part of the body, for highlights and condensation.
    let bodyRect: CGRect
    /// Steel bottles: the only part of the body you can see the water through.
    var window: CGRect? = nil
    /// The gallon jug's handle, drawn as glass but never filled.
    var handle: Path? = nil
    /// Right-hand inner wall as (y, x) samples ordered top to bottom.
    private let rightWall: [CGPoint]

    /// Half the inner width at height `y`.
    func halfWidth(at y: CGFloat) -> CGFloat {
        guard let first = rightWall.first, let last = rightWall.last else { return 30 }
        if y <= first.y { return first.x - Self.centerX }
        if y >= last.y { return max(last.x - Self.centerX, 0) }
        var lo = 0, hi = rightWall.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if rightWall[mid].y <= y { lo = mid } else { hi = mid }
        }
        let a = rightWall[lo], b = rightWall[hi]
        let t = b.y == a.y ? 0 : (y - a.y) / (b.y - a.y)
        return max(a.x + (b.x - a.x) * t - Self.centerX, 0)
    }

    func levelY(_ fraction: Double) -> CGFloat {
        emptyY - CGFloat(fraction) * (emptyY - fullY)
    }

    func fraction(atY y: CGFloat) -> Double {
        Double((emptyY - y) / (emptyY - fullY))
    }

    // MARK: - Construction

    private static var cache: [String: BottleGeometry] = [:]

    static func of(_ style: BottleStyle, custom: CustomBottleSpec = CustomBottleSpec()) -> BottleGeometry {
        let key = style == .custom ? "custom:" + custom.key : style.rawValue
        if let cached = cache[key] { return cached }
        let geometry = style == .custom ? makeCustom(custom, id: key) : make(style)
        // The designer's sliders make a new shape per step; keep the cache small.
        if cache.count > 24 { cache = cache.filter { !$0.key.hasPrefix("custom:") } }
        cache[key] = geometry
        return geometry
    }

    static func of(_ look: BottleAppearance) -> BottleGeometry { of(look.style, custom: look.custom) }

    private init(style: BottleStyle, id: String? = nil, outer: Path, inner: Path, fullY: CGFloat, emptyY: CGFloat,
                 mouthY: CGFloat, cap: Cap, capRect: CGRect, bodyRect: CGRect) {
        self.style = style
        self.id = id ?? style.rawValue
        self.outer = outer
        self.inner = inner
        self.fullY = fullY
        self.emptyY = emptyY
        self.mouthY = mouthY
        self.cap = cap
        self.capRect = capRect
        self.bodyRect = bodyRect
        self.rightWall = Self.rightWall(of: inner)
    }

    private static func make(_ style: BottleStyle) -> BottleGeometry {
        let wall: CGFloat = 3.2
        switch style {
        case .classic:
            return BottleGeometry(style: style, outer: classic(0), inner: classic(wall),
                                  fullY: 72, emptyY: 218 - wall, mouthY: 30, cap: .screw,
                                  capRect: CGRect(x: 31, y: 3, width: 38, height: 26),
                                  bodyRect: CGRect(x: 8, y: 84, width: 84, height: 112))
        case .sport:
            return BottleGeometry(style: style, outer: sport(0), inner: sport(wall),
                                  fullY: 62, emptyY: 218 - wall, mouthY: 40, cap: .flip,
                                  capRect: CGRect(x: 27, y: 13, width: 46, height: 23),
                                  bodyRect: CGRect(x: 12, y: 64, width: 76, height: 140))
        case .carafe:
            return BottleGeometry(style: style, outer: carafe(0), inner: carafe(wall),
                                  fullY: 108, emptyY: 216 - wall, mouthY: 26, cap: .cork,
                                  capRect: CGRect(x: 39, y: 2, width: 22, height: 22),
                                  bodyRect: CGRect(x: 10, y: 128, width: 80, height: 70))
        case .tumbler:
            return BottleGeometry(style: style, outer: tumbler(0), inner: tumbler(wall),
                                  fullY: 52, emptyY: 204, mouthY: -10, cap: .none,
                                  capRect: .zero,
                                  bodyRect: CGRect(x: 14, y: 40, width: 72, height: 160))
        case .flask:
            var geo = BottleGeometry(style: style, outer: flask(0), inner: flask(wall),
                                     fullY: 86, emptyY: 218 - wall, mouthY: 30, cap: .screw,
                                     capRect: CGRect(x: 31, y: 1, width: 38, height: 29),
                                     bodyRect: CGRect(x: 14, y: 80, width: 72, height: 126))
            geo.window = CGRect(x: 41, y: 84, width: 18, height: 122)
            return geo
        case .jar:
            return BottleGeometry(style: style, outer: jar(0), inner: jar(wall),
                                  fullY: 70, emptyY: 218 - wall, mouthY: 32, cap: .lid,
                                  capRect: CGRect(x: 18, y: 17, width: 64, height: 15),
                                  bodyRect: CGRect(x: 10, y: 64, width: 80, height: 138))
        case .jug:
            var geo = BottleGeometry(style: style, outer: jug(0), inner: jug(wall),
                                     fullY: 80, emptyY: 218 - wall, mouthY: 30, cap: .screw,
                                     capRect: CGRect(x: 35, y: 8, width: 30, height: 22),
                                     bodyRect: CGRect(x: 8, y: 78, width: 84, height: 124))
            var handle = Path()
            handle.move(to: CGPoint(x: 66, y: 46))
            handle.addCurve(to: CGPoint(x: 92, y: 104), control1: CGPoint(x: 100, y: 40), control2: CGPoint(x: 104, y: 92))
            geo.handle = handle
            return geo
        case .lab:
            return BottleGeometry(style: style, outer: lab(0), inner: lab(wall),
                                  fullY: 112, emptyY: 218 - wall, mouthY: 30, cap: .cork,
                                  capRect: CGRect(x: 38, y: 5, width: 24, height: 27),
                                  bodyRect: CGRect(x: 18, y: 124, width: 64, height: 78))
        case .custom:
            return makeCustom(CustomBottleSpec(), id: "custom")
        }
    }

    /// "Your Design": a neck, a shoulder, a body with an optional waist and a
    /// rounded base, all from the designer's sliders.
    private static func makeCustom(_ spec: CustomBottleSpec, id: String) -> BottleGeometry {
        let wall: CGFloat = 3.2
        let neckHalf = CGFloat(min(max(spec.neckWidth, 14), 46)) / 2
        let neckTop: CGFloat = 26
        let shoulderTop = neckTop + CGFloat(min(max(spec.neckHeight, 6), 70))
        let cap: Cap
        let capRect: CGRect
        switch spec.cap {
        case .screw:
            cap = .screw
            capRect = CGRect(x: 50 - neckHalf - 3, y: 2, width: (neckHalf + 3) * 2, height: 25)
        case .flip:
            cap = .flip
            capRect = CGRect(x: 50 - neckHalf - 5, y: 12, width: (neckHalf + 5) * 2, height: 22)
        case .cork:
            cap = .cork
            capRect = CGRect(x: 50 - neckHalf + 3, y: 4, width: (neckHalf - 3) * 2, height: 24)
        case .lid:
            cap = .lid
            capRect = CGRect(x: 50 - neckHalf - 5, y: 15, width: (neckHalf + 5) * 2, height: 13)
        case .none:
            cap = .none
            capRect = .zero
        }
        let outer = custom(spec, 0)
        let shoulderBottom = shoulderTop + 10 + CGFloat(spec.shoulder) * 40
        let full = min(max(shoulderBottom + 6, 60), 150)
        let bodyHalf = CGFloat(min(max(spec.bodyWidth, 50), 96)) / 2
        return BottleGeometry(style: .custom, id: id, outer: outer, inner: custom(spec, wall),
                              fullY: full, emptyY: 218 - wall, mouthY: cap == .none ? -10 : neckTop + 4, cap: cap,
                              capRect: capRect,
                              bodyRect: CGRect(x: 50 - bodyHalf, y: shoulderBottom, width: bodyHalf * 2,
                                               height: max(218 - shoulderBottom - 16, 30)))
    }

    private static func custom(_ spec: CustomBottleSpec, _ w: CGFloat) -> Path {
        var p = Path()
        let neckHalf = CGFloat(min(max(spec.neckWidth, 14), 46)) / 2 - w
        let bodyHalf = CGFloat(min(max(spec.bodyWidth, 50), 96)) / 2 - w
        let neckTop: CGFloat = 26
        let shoulderTop = neckTop + CGFloat(min(max(spec.neckHeight, 6), 70))
        let shoulderBottom = shoulderTop + 10 + CGFloat(spec.shoulder) * 40
        let bottom = 218 - w
        let r = min(CGFloat(spec.baseRound), bodyHalf - 2, 40) - w * 0.4
        let pinch = CGFloat(min(max(spec.waist, 0), 12))
        let waistY = (shoulderBottom + bottom) / 2
        let nl = 50 - neckHalf, nr = 50 + neckHalf
        let bl = 50 - bodyHalf, br = 50 + bodyHalf
        p.move(to: CGPoint(x: nl, y: neckTop))
        p.addLine(to: CGPoint(x: nl, y: shoulderTop))
        p.addCurve(to: CGPoint(x: bl, y: shoulderBottom),
                   control1: CGPoint(x: nl, y: shoulderTop + (shoulderBottom - shoulderTop) * 0.6),
                   control2: CGPoint(x: bl, y: shoulderTop + (shoulderBottom - shoulderTop) * 0.35))
        if pinch > 0.5 {
            p.addCurve(to: CGPoint(x: bl + pinch, y: waistY), control1: CGPoint(x: bl, y: waistY - 24),
                       control2: CGPoint(x: bl + pinch, y: waistY - 12))
            p.addCurve(to: CGPoint(x: bl, y: min(waistY + 30, bottom - r - 1)), control1: CGPoint(x: bl + pinch, y: waistY + 12),
                       control2: CGPoint(x: bl, y: waistY + 18))
        }
        p.addLine(to: CGPoint(x: bl, y: bottom - r))
        p.addQuadCurve(to: CGPoint(x: bl + r, y: bottom), control: CGPoint(x: bl, y: bottom))
        p.addLine(to: CGPoint(x: br - r, y: bottom))
        p.addQuadCurve(to: CGPoint(x: br, y: bottom - r), control: CGPoint(x: br, y: bottom))
        if pinch > 0.5 {
            p.addLine(to: CGPoint(x: br, y: min(waistY + 30, bottom - r - 1)))
            p.addCurve(to: CGPoint(x: br - pinch, y: waistY), control1: CGPoint(x: br, y: waistY + 18),
                       control2: CGPoint(x: br - pinch, y: waistY + 12))
            p.addCurve(to: CGPoint(x: br, y: shoulderBottom), control1: CGPoint(x: br - pinch, y: waistY - 12),
                       control2: CGPoint(x: br, y: waistY - 24))
        } else {
            p.addLine(to: CGPoint(x: br, y: shoulderBottom))
        }
        p.addCurve(to: CGPoint(x: nr, y: shoulderTop),
                   control1: CGPoint(x: br, y: shoulderTop + (shoulderBottom - shoulderTop) * 0.35),
                   control2: CGPoint(x: nr, y: shoulderTop + (shoulderBottom - shoulderTop) * 0.6))
        p.addLine(to: CGPoint(x: nr, y: neckTop))
        p.closeSubpath()
        return p
    }

    /// Insulated steel: straight sides, a short neck and rounded shoulders.
    private static func flask(_ w: CGFloat) -> Path {
        var p = Path()
        let nl = 35 + w, nr = 65 - w
        let bl = 14 + w, br = 86 - w
        let bottom = 218 - w
        let r = 12 - w * 0.4
        p.move(to: CGPoint(x: nl, y: 28))
        p.addLine(to: CGPoint(x: nl, y: 44))
        p.addCurve(to: CGPoint(x: bl, y: 78), control1: CGPoint(x: nl, y: 58), control2: CGPoint(x: bl, y: 56))
        p.addLine(to: CGPoint(x: bl, y: bottom - r))
        p.addQuadCurve(to: CGPoint(x: bl + r, y: bottom), control: CGPoint(x: bl, y: bottom))
        p.addLine(to: CGPoint(x: br - r, y: bottom))
        p.addQuadCurve(to: CGPoint(x: br, y: bottom - r), control: CGPoint(x: br, y: bottom))
        p.addLine(to: CGPoint(x: br, y: 78))
        p.addCurve(to: CGPoint(x: nr, y: 44), control1: CGPoint(x: br, y: 56), control2: CGPoint(x: nr, y: 58))
        p.addLine(to: CGPoint(x: nr, y: 28))
        p.closeSubpath()
        return p
    }

    /// A mason jar: a wide threaded mouth, a short shoulder, a broad body.
    private static func jar(_ w: CGFloat) -> Path {
        var p = Path()
        let ml = 22 + w, mr = 78 - w
        let bl = 10 + w, br = 90 - w
        let bottom = 218 - w
        let r = 16 - w * 0.4
        p.move(to: CGPoint(x: ml, y: 30))
        p.addLine(to: CGPoint(x: ml, y: 44))
        p.addQuadCurve(to: CGPoint(x: bl, y: 64), control: CGPoint(x: bl, y: 46))
        p.addLine(to: CGPoint(x: bl, y: bottom - r))
        p.addQuadCurve(to: CGPoint(x: bl + r, y: bottom), control: CGPoint(x: bl, y: bottom))
        p.addLine(to: CGPoint(x: br - r, y: bottom))
        p.addQuadCurve(to: CGPoint(x: br, y: bottom - r), control: CGPoint(x: br, y: bottom))
        p.addLine(to: CGPoint(x: br, y: 64))
        p.addQuadCurve(to: CGPoint(x: mr, y: 44), control: CGPoint(x: br, y: 46))
        p.addLine(to: CGPoint(x: mr, y: 30))
        p.closeSubpath()
        return p
    }

    /// A gallon jug: a short neck, sloping shoulders, a boxy body. The handle
    /// is a separate path.
    private static func jug(_ w: CGFloat) -> Path {
        var p = Path()
        let nl = 38 + w, nr = 62 - w
        let bl = 8 + w, br = 92 - w
        let bottom = 218 - w
        let r = 18 - w * 0.4
        p.move(to: CGPoint(x: nl, y: 28))
        p.addLine(to: CGPoint(x: nl, y: 38))
        p.addCurve(to: CGPoint(x: bl, y: 76), control1: CGPoint(x: nl - 10, y: 46), control2: CGPoint(x: bl, y: 58))
        p.addLine(to: CGPoint(x: bl, y: bottom - r))
        p.addQuadCurve(to: CGPoint(x: bl + r, y: bottom), control: CGPoint(x: bl, y: bottom))
        p.addLine(to: CGPoint(x: br - r, y: bottom))
        p.addQuadCurve(to: CGPoint(x: br, y: bottom - r), control: CGPoint(x: br, y: bottom))
        p.addLine(to: CGPoint(x: br, y: 76))
        p.addCurve(to: CGPoint(x: nr, y: 38), control1: CGPoint(x: br, y: 58), control2: CGPoint(x: nr + 10, y: 46))
        p.addLine(to: CGPoint(x: nr, y: 28))
        p.closeSubpath()
        return p
    }

    /// An Erlenmeyer flask: a long narrow neck over a cone with a flat base.
    private static func lab(_ w: CGFloat) -> Path {
        var p = Path()
        let nl = 40 + w, nr = 60 - w
        let bl = 6 + w * 1.4, br = 94 - w * 1.4
        let bottom = 218 - w
        let r = 9 - w * 0.4
        p.move(to: CGPoint(x: nl, y: 30))
        p.addLine(to: CGPoint(x: nl, y: 96))
        p.addLine(to: CGPoint(x: bl + 2, y: bottom - r - 2))
        p.addQuadCurve(to: CGPoint(x: bl + r + 4, y: bottom), control: CGPoint(x: bl, y: bottom))
        p.addLine(to: CGPoint(x: br - r - 4, y: bottom))
        p.addQuadCurve(to: CGPoint(x: br - 2, y: bottom - r - 2), control: CGPoint(x: br, y: bottom))
        p.addLine(to: CGPoint(x: nr, y: 96))
        p.addLine(to: CGPoint(x: nr, y: 30))
        p.closeSubpath()
        return p
    }

    // Each silhouette is a function of a wall inset, so the inside of the
    // glass is the same curve pulled in by the wall thickness.

    private static func classic(_ w: CGFloat) -> Path {
        var p = Path()
        let nl = 36 + w, nr = 64 - w
        let bl = 8 + w, br = 92 - w
        let bottom = 218 - w
        let r = 22 - w * 0.5
        p.move(to: CGPoint(x: nl, y: 26))
        p.addLine(to: CGPoint(x: nl, y: 44))
        p.addCurve(to: CGPoint(x: bl, y: 84), control1: CGPoint(x: nl, y: 60), control2: CGPoint(x: bl, y: 58))
        p.addLine(to: CGPoint(x: bl, y: bottom - r))
        p.addQuadCurve(to: CGPoint(x: bl + r, y: bottom), control: CGPoint(x: bl, y: bottom))
        p.addLine(to: CGPoint(x: br - r, y: bottom))
        p.addQuadCurve(to: CGPoint(x: br, y: bottom - r), control: CGPoint(x: br, y: bottom))
        p.addLine(to: CGPoint(x: br, y: 84))
        p.addCurve(to: CGPoint(x: nr, y: 44), control1: CGPoint(x: br, y: 58), control2: CGPoint(x: nr, y: 60))
        p.addLine(to: CGPoint(x: nr, y: 26))
        p.closeSubpath()
        return p
    }

    private static func sport(_ w: CGFloat) -> Path {
        var p = Path()
        let cl = 30 + w, cr = 70 - w
        let bl = 12 + w, br = 88 - w
        let bottom = 218 - w
        let r = 14 - w * 0.5
        let pinch: CGFloat = 7
        p.move(to: CGPoint(x: cl, y: 34))
        p.addLine(to: CGPoint(x: cl, y: 46))
        p.addQuadCurve(to: CGPoint(x: bl, y: 64), control: CGPoint(x: bl, y: 46))
        p.addLine(to: CGPoint(x: bl, y: 112))
        p.addCurve(to: CGPoint(x: bl + pinch, y: 134), control1: CGPoint(x: bl, y: 122), control2: CGPoint(x: bl + pinch, y: 126))
        p.addCurve(to: CGPoint(x: bl, y: 156), control1: CGPoint(x: bl + pinch, y: 142), control2: CGPoint(x: bl, y: 146))
        p.addLine(to: CGPoint(x: bl, y: bottom - r))
        p.addQuadCurve(to: CGPoint(x: bl + r, y: bottom), control: CGPoint(x: bl, y: bottom))
        p.addLine(to: CGPoint(x: br - r, y: bottom))
        p.addQuadCurve(to: CGPoint(x: br, y: bottom - r), control: CGPoint(x: br, y: bottom))
        p.addLine(to: CGPoint(x: br, y: 156))
        p.addCurve(to: CGPoint(x: br - pinch, y: 134), control1: CGPoint(x: br, y: 146), control2: CGPoint(x: br - pinch, y: 142))
        p.addCurve(to: CGPoint(x: br, y: 112), control1: CGPoint(x: br - pinch, y: 126), control2: CGPoint(x: br, y: 122))
        p.addLine(to: CGPoint(x: br, y: 64))
        p.addQuadCurve(to: CGPoint(x: cr, y: 46), control: CGPoint(x: br, y: 46))
        p.addLine(to: CGPoint(x: cr, y: 34))
        p.closeSubpath()
        return p
    }

    private static func carafe(_ w: CGFloat) -> Path {
        var p = Path()
        let nl = 40 + w, nr = 60 - w
        let sl = 4 + w, sr = 96 - w
        let bottom = 216 - w
        p.move(to: CGPoint(x: nl, y: 22))
        p.addLine(to: CGPoint(x: nl, y: 96))
        p.addCurve(to: CGPoint(x: sl, y: 166), control1: CGPoint(x: nl, y: 118), control2: CGPoint(x: sl, y: 126))
        p.addCurve(to: CGPoint(x: 50, y: bottom), control1: CGPoint(x: sl, y: 194), control2: CGPoint(x: 24, y: bottom))
        p.addCurve(to: CGPoint(x: sr, y: 166), control1: CGPoint(x: 76, y: bottom), control2: CGPoint(x: sr, y: 194))
        p.addCurve(to: CGPoint(x: nr, y: 96), control1: CGPoint(x: sr, y: 126), control2: CGPoint(x: nr, y: 118))
        p.addLine(to: CGPoint(x: nr, y: 22))
        p.closeSubpath()
        return p
    }

    private static func tumbler(_ w: CGFloat) -> Path {
        var p = Path()
        let top: CGFloat = 34
        // The base is thick glass, so the inside floor sits well above the
        // outside bottom.
        let bottom: CGFloat = w > 0 ? 204 : 218
        let tl = 6 + w, tr = 94 - w
        let bl = 16 + w * 1.3, br = 84 - w * 1.3
        let r: CGFloat = 10
        p.move(to: CGPoint(x: tl, y: top))
        p.addLine(to: CGPoint(x: bl, y: bottom - r))
        p.addQuadCurve(to: CGPoint(x: bl + r, y: bottom), control: CGPoint(x: bl + 0.6, y: bottom))
        p.addLine(to: CGPoint(x: br - r, y: bottom))
        p.addQuadCurve(to: CGPoint(x: br, y: bottom - r), control: CGPoint(x: br - 0.6, y: bottom))
        p.addLine(to: CGPoint(x: tr, y: top))
        p.closeSubpath()
        return p
    }

    /// Flattens the path and keeps the right-hand half, ordered top to bottom,
    /// so the inner width at any height can be looked up.
    private static func rightWall(of path: Path) -> [CGPoint] {
        var points: [CGPoint] = []
        var current = CGPoint.zero
        var start = CGPoint.zero
        let steps = 14
        path.forEach { element in
            switch element {
            case .move(let to):
                current = to; start = to
                points.append(to)
            case .line(let to):
                points.append(to); current = to
            case .quadCurve(let to, let c):
                for i in 1...steps {
                    let t = CGFloat(i) / CGFloat(steps), u = 1 - t
                    points.append(CGPoint(x: u * u * current.x + 2 * u * t * c.x + t * t * to.x,
                                          y: u * u * current.y + 2 * u * t * c.y + t * t * to.y))
                }
                current = to
            case .curve(let to, let c1, let c2):
                for i in 1...steps {
                    let t = CGFloat(i) / CGFloat(steps), u = 1 - t
                    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                    points.append(CGPoint(x: a * current.x + b * c1.x + c * c2.x + d * to.x,
                                          y: a * current.y + b * c1.y + c * c2.y + d * to.y))
                }
                current = to
            case .closeSubpath:
                points.append(start); current = start
            }
        }
        // Keep the widest x at each height on the right of centre.
        var byRow: [Int: CGFloat] = [:]
        for p in points where p.x >= centerX {
            let row = Int((p.y * 2).rounded())
            byRow[row] = max(byRow[row] ?? 0, p.x)
        }
        return byRow.keys.sorted().map { CGPoint(x: byRow[$0]!, y: CGFloat($0) / 2) }
    }
}

/// Maps the design space into a view of a given size: the bottle is fitted to
/// the height, centred horizontally and rested on the bottom edge.
struct BottleLayout {
    let scale: CGFloat
    let origin: CGPoint

    /// `bleed` is extra room on every side that the bottle itself doesn't use,
    /// so glows, rings and confetti can spill past the bottle's frame.
    init(size: CGSize, inset: CGFloat = 4, bleed: CGFloat = 0) {
        let design = BottleGeometry.designSize
        let topRoom: CGFloat = 16   // room for the cap to lift
        let width = size.width - bleed * 2
        let height = size.height - bleed * 2 - inset
        let s = min(width / design.width, height / (design.height + topRoom))
        scale = max(s, 0.01)
        origin = CGPoint(x: (size.width - design.width * scale) / 2,
                         y: size.height - bleed - inset - design.height * scale)
    }

    func toDesign(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - origin.x) / scale, y: (p.y - origin.y) / scale)
    }

    func toView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale)
    }
}
