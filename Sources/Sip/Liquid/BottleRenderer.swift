import SwiftUI
import SipCore

/// The parts of a bottle that don't move: the glass behind the water, the
/// glass in front of it with its marks and condensation, and the cap. Each is
/// drawn once into an image and handed to a layer; only the water is updated
/// every frame (`LiquidLayerView`).
///
/// Everything works in the 100 × 220 design space; `px` is one screen point in
/// design units, used for hairlines and text so they stay crisp at any size.
enum BottleRenderer {
    private static func designContext(_ base: GraphicsContext, size: CGSize, bleed: CGFloat) -> (GraphicsContext, BottleLayout) {
        let layout = BottleLayout(size: size, bleed: bleed)
        var ctx = base
        ctx.translateBy(x: layout.origin.x, y: layout.origin.y)
        ctx.scaleBy(x: layout.scale, y: layout.scale)
        return (ctx, layout)
    }

    /// Contact shadow and the glass behind the water.
    static func drawBack(_ base: GraphicsContext, size: CGSize, look: BottleAppearance) {
        let (ctx, _) = designContext(base, size: size, bleed: look.bleed)
        drawContactShadow(ctx)
        drawGlassBack(ctx, geo: BottleGeometry.of(look), theme: look.theme, tint: look.tint)
    }

    /// Highlights, outline, measuring marks, condensation and the parts of the
    /// closure that stay put when the cap comes off.
    static func drawFront(_ base: GraphicsContext, size: CGSize, look: BottleAppearance) {
        let (ctx, layout) = designContext(base, size: size, bleed: look.bleed)
        let geo = BottleGeometry.of(look)
        let px = 1 / layout.scale
        if geo.window != nil { drawSteel(ctx, geo: geo, theme: look.theme, px: px) }
        drawGlassFront(ctx, geo: geo, tint: look.tint, px: px)
        drawStyleDetails(ctx, geo: geo, look: look, px: px)
        if look.showTicks { drawTicks(ctx, geo: geo, look: look, scale: layout.scale, px: px) }
        if !look.timeMarks.isEmpty { drawTimeMarks(ctx, geo: geo, marks: look.timeMarks, scale: layout.scale, px: px) }
        if look.showCondensation, geo.window == nil { drawBeads(ctx, geo: geo, px: px) }
        if !look.label.isEmpty { drawLabel(ctx, geo: geo, look: look, px: px) }
        drawCapFixed(ctx, geo: geo, theme: look.theme, px: px)
    }

    /// Frost on the glass: a pale rim and fern-like crystals reaching in from
    /// the edges. Drawn once; its layer fades with the temperature.
    static func drawFrost(_ base: GraphicsContext, size: CGSize, look: BottleAppearance) {
        let (ctx, layout) = designContext(base, size: size, bleed: look.bleed)
        let geo = BottleGeometry.of(look)
        let px = 1 / layout.scale
        var c = ctx
        c.clip(to: geo.outer)
        var haze = c
        haze.addFilter(.blur(radius: 4 * layout.scale))
        haze.stroke(geo.outer, with: .color(.white.opacity(0.55)), lineWidth: 12)
        var seed: UInt64 = 0xF205_7A11
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Double(seed >> 33) / Double(1 << 31))
        }
        var crystals = Path()
        for i in 0..<34 {
            let y = 30 + CGFloat(i) / 34 * 186 + next() * 4
            let half = geo.halfWidth(at: y) + 3
            let leftSide = i % 2 == 0
            let x = 50 + (leftSide ? -half : half)
            let dir: CGFloat = leftSide ? 1 : -1
            let length = 5 + next() * 9
            let angle = (next() - 0.5) * 0.9
            let end = CGPoint(x: x + dir * cos(angle) * length, y: y + sin(angle) * length)
            crystals.move(to: CGPoint(x: x, y: y))
            crystals.addLine(to: end)
            // Side branches, like a fern.
            for k in 1...3 {
                let f = CGFloat(k) / 4
                let p = CGPoint(x: x + (end.x - x) * f, y: y + (end.y - y) * f)
                let b = length * 0.3 * (1 - f)
                crystals.move(to: p)
                crystals.addLine(to: CGPoint(x: p.x + dir * b * 0.6, y: p.y - b))
                crystals.move(to: p)
                crystals.addLine(to: CGPoint(x: p.x + dir * b * 0.6, y: p.y + b))
            }
        }
        c.stroke(crystals, with: .color(.white.opacity(0.75)), lineWidth: 0.7 * px)
    }

    /// The piece of the closure that lifts during a pour, at rest.
    static func drawCapMoving(_ base: GraphicsContext, size: CGSize, look: BottleAppearance) {
        let (ctx, layout) = designContext(base, size: size, bleed: look.bleed)
        drawCapPiece(ctx, geo: BottleGeometry.of(look), theme: look.theme, px: 1 / layout.scale)
    }

    /// How the moving piece is displaced when the cap is `open` (0–1): about
    /// which point it turns, by how much, and how far it rises (design units).
    static func capMotion(_ geo: BottleGeometry, open: CGFloat) -> (hinge: CGPoint, angle: CGFloat, lift: CGFloat) {
        let rect = geo.capRect
        switch geo.cap {
        case .screw: return (CGPoint(x: rect.maxX, y: rect.maxY), open * 0.42, open * 15)
        case .flip: return (CGPoint(x: rect.maxX - 2, y: rect.maxY - 9), open * 1.9, 0)
        case .cork: return (CGPoint(x: rect.midX, y: rect.maxY), 0, open * 13)
        case .lid: return (CGPoint(x: rect.maxX, y: rect.maxY), open * 0.3, open * 12)
        case .none: return (.zero, 0, 0)
        }
    }

    // MARK: - Glass

    private static func drawContactShadow(_ base: GraphicsContext) {
        var ctx = base
        ctx.translateBy(x: 50, y: 218.5)
        ctx.scaleBy(x: 1, y: 0.13)
        ctx.fill(Path(ellipseIn: CGRect(x: -44, y: -44, width: 88, height: 88)),
                 with: .radialGradient(Gradient(colors: [.black.opacity(0.38), .black.opacity(0.12), .clear]),
                                       center: .zero, startRadius: 0, endRadius: 44))
    }

    private static func drawGlassBack(_ ctx: GraphicsContext, geo: BottleGeometry, theme: LiquidTheme, tint: GlassTint) {
        if let handle = geo.handle {
            ctx.stroke(handle, with: .color(.black.opacity(0.18)), style: StrokeStyle(lineWidth: 8.5, lineCap: .round))
            ctx.stroke(handle, with: .color(.white.opacity(0.16)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        }
        ctx.fill(geo.outer, with: .linearGradient(
            Gradient(stops: [.init(color: .white.opacity(0.16), location: 0),
                             .init(color: .white.opacity(0.05), location: 0.45),
                             .init(color: .white.opacity(0.11), location: 1)]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 100, y: 0)))
        ctx.fill(geo.outer, with: .color((tint.color ?? theme.surface).opacity(tint.color == nil ? 0.06 : 0.13)))
    }

    /// Brushed steel over everything but the window strip.
    private static func drawSteel(_ ctx: GraphicsContext, geo: BottleGeometry, theme: LiquidTheme, px: CGFloat) {
        guard let window = geo.window else { return }
        var shell = geo.outer
        let hole = Path(roundedRect: window, cornerRadius: window.width / 2)
        shell.addPath(hole)
        let steel = Gradient(stops: [.init(color: Color(hex: 0x5D6675), location: 0),
                                     .init(color: Color(hex: 0xC9D1DC), location: 0.18),
                                     .init(color: Color(hex: 0x8E98A8), location: 0.4),
                                     .init(color: Color(hex: 0x6E7889), location: 0.62),
                                     .init(color: Color(hex: 0xB4BDCA), location: 0.82),
                                     .init(color: Color(hex: 0x4E5665), location: 1)])
        ctx.fill(shell, with: .linearGradient(steel, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 100, y: 0)),
                 style: FillStyle(eoFill: true))
        // A wash of the liquid colour, as if the steel were anodised.
        ctx.fill(shell, with: .color(theme.deep.opacity(0.22)), style: FillStyle(eoFill: true))
        // Fine brushed lines.
        var c = ctx
        c.clip(to: shell, style: FillStyle(eoFill: true))
        var lines = Path()
        for i in 0..<36 {
            let y = 30 + CGFloat(i) * 5.4
            lines.move(to: CGPoint(x: 0, y: y))
            lines.addLine(to: CGPoint(x: 100, y: y + 0.6))
        }
        c.stroke(lines, with: .color(.white.opacity(0.05)), lineWidth: 0.6 * px)
        ctx.stroke(hole, with: .color(.black.opacity(0.35)), lineWidth: 1.6 * px)
        ctx.stroke(hole, with: .color(.white.opacity(0.4)), lineWidth: 0.8 * px)
    }

    /// The jar's embossed name, the lab flask's rim, the jug's handle.
    private static func drawStyleDetails(_ ctx: GraphicsContext, geo: BottleGeometry, look: BottleAppearance, px: CGFloat) {
        switch geo.style {
        case .jar:
            let emboss = Text("Sip").font(.system(size: 26, weight: .heavy, design: .serif)).italic()
            ctx.draw(emboss.foregroundColor(.black.opacity(0.12)), at: CGPoint(x: 50.6, y: 141), anchor: .center)
            ctx.draw(emboss.foregroundColor(.white.opacity(0.2)), at: CGPoint(x: 50, y: 140), anchor: .center)
            var rings = Path()
            for y in [56.0, 198.0] as [CGFloat] {
                rings.move(to: CGPoint(x: 14, y: y))
                rings.addLine(to: CGPoint(x: 86, y: y))
            }
            ctx.stroke(rings, with: .color(.white.opacity(0.16)), lineWidth: 1.2 * px)
        case .lab:
            let rim = CGRect(x: 36, y: 28, width: 28, height: 5)
            ctx.fill(Path(roundedRect: rim, cornerRadius: 2.5), with: .color(.white.opacity(0.28)))
            ctx.stroke(Path(roundedRect: rim, cornerRadius: 2.5), with: .color(.white.opacity(0.6)), lineWidth: 0.8 * px)
        case .jug:
            if let handle = geo.handle {
                ctx.stroke(handle, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 1.2 * px, lineCap: .round))
            }
        default:
            break
        }
    }

    /// A printed label across the body.
    private static func drawLabel(_ ctx: GraphicsContext, geo: BottleGeometry, look: BottleAppearance, px: CGFloat) {
        let body = geo.bodyRect
        let y = geo.window != nil ? body.maxY - 26 : body.midY + body.height * 0.16
        let width = min(body.width - 10, 84)
        let rect = CGRect(x: 50 - width / 2, y: y, width: width, height: 20)
        var c = ctx
        c.clip(to: geo.outer)
        c.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(.white.opacity(0.88)))
        c.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 2.2)), with: .color(look.theme.mid))
        let text = Text(look.label)
            .font(.system(size: 9.5, weight: .heavy, design: .rounded))
            .foregroundColor(look.theme.deep)
        c.draw(text, in: rect.insetBy(dx: 4, dy: 3))
    }

    private static func drawGlassFront(_ ctx: GraphicsContext, geo: BottleGeometry, tint: GlassTint, px: CGFloat) {
        var g = ctx
        g.clip(to: geo.outer)
        let body = geo.bodyRect
        let band = CGRect(x: body.minX + 5, y: body.minY + 4, width: 7.5, height: body.height - 18)
        g.fill(Path(roundedRect: band, cornerRadius: 3.7), with: .linearGradient(
            Gradient(stops: [.init(color: .white.opacity(0), location: 0),
                             .init(color: .white.opacity(0.42), location: 0.45),
                             .init(color: .white.opacity(0.04), location: 1)]),
            startPoint: CGPoint(x: band.minX, y: 0), endPoint: CGPoint(x: band.maxX, y: 0)))
        g.fill(Path(roundedRect: CGRect(x: body.minX + 15.5, y: body.minY + 10, width: 1.6, height: body.height * 0.42),
                    cornerRadius: 0.8), with: .color(.white.opacity(0.24)))
        g.fill(Path(roundedRect: CGRect(x: body.maxX - 8.5, y: body.minY + 12, width: 3, height: max(body.height - 38, 4)),
                    cornerRadius: 1.5), with: .color(.white.opacity(0.14)))
        g.fill(Path(ellipseIn: CGRect(x: body.minX + 9, y: body.minY - 5, width: 15, height: 6)),
               with: .color(.white.opacity(0.2)))

        // A dark hairline outside the light one keeps the edge visible on a
        // light wallpaper.
        ctx.stroke(geo.outer, with: .color(.black.opacity(0.2)), lineWidth: 2.6 * px)
        ctx.stroke(geo.outer, with: .linearGradient(
            Gradient(colors: [.white.opacity(0.85), .white.opacity(0.28), .white.opacity(0.55)]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 100, y: 220)), lineWidth: 1.4 * px)
        if let color = tint.color {
            ctx.stroke(geo.outer, with: .color(color.opacity(0.45)), lineWidth: 1 * px)
        }
        ctx.stroke(geo.inner, with: .color(.white.opacity(0.12)), lineWidth: 0.8 * px)
    }

    /// Measuring marks at round amounts (every 250 ml, 500 ml, 1 L…, or
    /// 8/16/32 oz), with half-step minor marks and the goal at the top.
    private static func drawTicks(_ ctx: GraphicsContext, geo: BottleGeometry, look: BottleAppearance,
                                  scale: CGFloat, px: CGFloat) {
        let showLabels = scale > 0.6
        let goal = max(look.goalML, 1)
        let steps: [Double] = look.unit == .milliliters
            ? [250, 500, 1000, 2000]
            : [8, 16, 32, 64].map { Volume.fromDisplay($0, .fluidOunces) }
        let step = steps.first { goal / $0 <= 5.5 } ?? steps.last!
        var marks: [(ml: Double, major: Bool)] = []
        var ml = step / 2
        while ml < goal - step * 0.2 {
            let major = abs((ml / step).rounded() - ml / step) < 0.01
            if major || scale >= 0.45 { marks.append((ml, major)) }
            ml += step / 2
        }
        marks.append((goal, true))
        for mark in marks {
            let y = geo.levelY(mark.ml / goal)
            let label = Text(Volume.tickLabel(mark.ml, look.unit))
                .font(.system(size: 7.5 * px, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.78))
            var tick = Path()
            if let window = geo.window {
                // Steel: engraved beside the window, reading outward.
                let x0 = window.maxX + 1.5
                tick.move(to: CGPoint(x: x0, y: y))
                tick.addLine(to: CGPoint(x: x0 + (mark.major ? 7 : 3.5), y: y))
                ctx.stroke(tick, with: .color(.white.opacity(mark.major ? 0.7 : 0.4)), lineWidth: (mark.major ? 1 : 0.8) * px)
                if showLabels && mark.major { ctx.draw(label, at: CGPoint(x: x0 + 9.5, y: y), anchor: .leading) }
                continue
            }
            let xr = 50 + geo.halfWidth(at: y) - 1.2
            tick.move(to: CGPoint(x: xr - (mark.major ? 8 : 4), y: y))
            tick.addLine(to: CGPoint(x: xr, y: y))
            ctx.stroke(tick, with: .color(.white.opacity(mark.major ? 0.6 : 0.35)), lineWidth: (mark.major ? 1 : 0.8) * px)
            if showLabels && mark.major {
                ctx.draw(label, at: CGPoint(x: xr - 10.5, y: y), anchor: .trailing)
            }
        }
    }

    /// Hour marks down the left side: where the water should be by then.
    private static func drawTimeMarks(_ ctx: GraphicsContext, geo: BottleGeometry, marks: [TimeMarkSpec],
                                      scale: CGFloat, px: CGFloat) {
        let showLabels = scale > 0.6
        for mark in marks where mark.fraction > 0.02 && mark.fraction <= 1.001 {
            let y = geo.levelY(mark.fraction)
            let left = geo.window.map { $0.minX - 1.5 } ?? (50 - geo.halfWidth(at: y) + 1.2)
            var tick = Path()
            if geo.window != nil {
                tick.move(to: CGPoint(x: left - 6, y: y))
                tick.addLine(to: CGPoint(x: left, y: y))
            } else {
                tick.move(to: CGPoint(x: left, y: y))
                tick.addLine(to: CGPoint(x: left + 6, y: y))
            }
            ctx.stroke(tick, with: .color(Color(hex: 0xFFE27A).opacity(0.75)), style: StrokeStyle(lineWidth: 1 * px, lineCap: .round))
            if showLabels {
                let text = Text(mark.label)
                    .font(.system(size: 6.5 * px, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: 0xFFE27A).opacity(0.85))
                if geo.window != nil {
                    ctx.draw(text, at: CGPoint(x: left - 7.5, y: y), anchor: .trailing)
                } else {
                    ctx.draw(text, at: CGPoint(x: left + 7.5, y: y), anchor: .leading)
                }
            }
        }
    }

    private static func drawBeads(_ ctx: GraphicsContext, geo: BottleGeometry, px: CGFloat) {
        var c = ctx
        c.clip(to: geo.outer)
        for bead in LiquidSimulation.beads(for: geo) {
            let r = bead.r
            let circle = Path(ellipseIn: CGRect(x: bead.x - r, y: bead.y - r, width: r * 2, height: r * 2))
            c.fill(circle, with: .color(.white.opacity(0.1)))
            c.stroke(circle, with: .color(.white.opacity(0.3)), lineWidth: 0.5 * px)
            let hr = r * 0.34
            c.fill(Path(ellipseIn: CGRect(x: bead.x - r * 0.38 - hr, y: bead.y - r * 0.38 - hr, width: hr * 2, height: hr * 2)),
                   with: .color(.white.opacity(0.8)))
        }
    }

    // MARK: - Cap

    private static func plastic(_ theme: LiquidTheme) -> Gradient {
        Gradient(stops: [.init(color: theme.deep, location: 0),
                         .init(color: theme.mid, location: 0.32),
                         .init(color: theme.surface, location: 0.5),
                         .init(color: theme.mid, location: 0.7),
                         .init(color: theme.deep, location: 1)])
    }

    /// Threads, the sport bottle's collar, the carafe's lip.
    private static func drawCapFixed(_ ctx: GraphicsContext, geo: BottleGeometry, theme: LiquidTheme, px: CGFloat) {
        let rect = geo.capRect
        switch geo.cap {
        case .none:
            return
        case .screw:
            var threads = Path()
            for y in [rect.maxY + 0.5, rect.maxY + 4, rect.maxY + 7.5] {
                threads.move(to: CGPoint(x: rect.minX + 6.5, y: y))
                threads.addLine(to: CGPoint(x: rect.maxX - 6.5, y: y + 1))
            }
            ctx.stroke(threads, with: .color(.white.opacity(0.3)), lineWidth: 0.9 * px)
        case .flip:
            let collar = CGRect(x: rect.minX + 2, y: rect.maxY - 9, width: rect.width - 4, height: 10)
            ctx.fill(Path(roundedRect: collar, cornerRadius: 3), with: .linearGradient(
                plastic(theme), startPoint: CGPoint(x: collar.minX, y: 0), endPoint: CGPoint(x: collar.maxX, y: 0)))
            ctx.stroke(Path(roundedRect: collar, cornerRadius: 3), with: .color(.black.opacity(0.25)), lineWidth: 1 * px)
        case .cork:
            ctx.fill(Path(roundedRect: CGRect(x: rect.minX - 2, y: rect.maxY - 5, width: rect.width + 4, height: 5), cornerRadius: 2.5),
                     with: .color(.white.opacity(0.22)))
        case .lid:
            // Glass threads under the lid.
            var threads = Path()
            for y in [rect.maxY + 2.5, rect.maxY + 6, rect.maxY + 9.5] {
                threads.move(to: CGPoint(x: rect.minX + 5, y: y))
                threads.addLine(to: CGPoint(x: rect.maxX - 5, y: y + 1.2))
            }
            ctx.stroke(threads, with: .color(.white.opacity(0.32)), lineWidth: 1 * px)
        }
    }

    /// The screw cap, the flip lid with its loop, or the cork.
    private static func drawCapPiece(_ ctx: GraphicsContext, geo: BottleGeometry, theme: LiquidTheme, px: CGFloat) {
        let rect = geo.capRect
        switch geo.cap {
        case .none:
            return
        case .screw:
            let path = Path(roundedRect: rect, cornerRadius: 5)
            ctx.fill(path, with: .linearGradient(plastic(theme), startPoint: CGPoint(x: rect.minX, y: 0),
                                                 endPoint: CGPoint(x: rect.maxX, y: 0)))
            var ridges = Path()
            for i in 0..<9 {
                let x = rect.minX + 4 + CGFloat(i) * 3.75
                ridges.move(to: CGPoint(x: x, y: rect.minY + 6))
                ridges.addLine(to: CGPoint(x: x, y: rect.maxY - 3))
            }
            ctx.stroke(ridges, with: .color(.white.opacity(0.17)), lineWidth: 0.8)
            ctx.fill(Path(roundedRect: CGRect(x: rect.minX + 2, y: rect.minY + 1.5, width: rect.width - 4, height: 3),
                          cornerRadius: 1.5), with: .color(.white.opacity(0.35)))
            ctx.stroke(path, with: .color(.black.opacity(0.25)), lineWidth: 1 * px)

        case .flip:
            let collarTop = rect.maxY - 9
            let lidRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: collarTop - rect.minY + 1)
            let loop = Path(roundedRect: CGRect(x: 38, y: rect.minY - 12, width: 24, height: 16), cornerRadius: 8)
            ctx.stroke(loop, with: .color(theme.deep), lineWidth: 3.2)
            ctx.stroke(loop, with: .color(.white.opacity(0.25)), lineWidth: 1 * px)
            ctx.fill(Path(roundedRect: lidRect, cornerRadius: 6), with: .linearGradient(
                plastic(theme), startPoint: CGPoint(x: lidRect.minX, y: 0), endPoint: CGPoint(x: lidRect.maxX, y: 0)))
            ctx.fill(Path(roundedRect: CGRect(x: 44, y: rect.minY - 3, width: 12, height: 5), cornerRadius: 2),
                     with: .color(theme.deep))
            ctx.fill(Path(roundedRect: CGRect(x: lidRect.minX + 3, y: lidRect.minY + 1.5, width: lidRect.width - 6, height: 2.6),
                          cornerRadius: 1.3), with: .color(.white.opacity(0.32)))
            ctx.stroke(Path(roundedRect: lidRect, cornerRadius: 6), with: .color(.black.opacity(0.25)), lineWidth: 1 * px)

        case .lid:
            // A two-piece canning lid: a flat disc inside a threaded band.
            let metal = Gradient(stops: [.init(color: Color(hex: 0x7C6A3A), location: 0),
                                         .init(color: Color(hex: 0xE9D49A), location: 0.3),
                                         .init(color: Color(hex: 0xFFF3C9), location: 0.48),
                                         .init(color: Color(hex: 0xC9AE6A), location: 0.7),
                                         .init(color: Color(hex: 0x6E5C30), location: 1)])
            let band = Path(roundedRect: rect, cornerRadius: 3)
            ctx.fill(band, with: .linearGradient(metal, startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0)))
            var grooves = Path()
            for y in stride(from: rect.minY + 4, to: rect.maxY - 1, by: 3) {
                grooves.move(to: CGPoint(x: rect.minX + 1, y: y))
                grooves.addLine(to: CGPoint(x: rect.maxX - 1, y: y))
            }
            ctx.stroke(grooves, with: .color(.black.opacity(0.18)), lineWidth: 0.7 * px)
            ctx.fill(Path(roundedRect: CGRect(x: rect.minX + 1, y: rect.minY - 1.6, width: rect.width - 2, height: 3), cornerRadius: 1.5),
                     with: .color(Color(hex: 0xFFF3C9).opacity(0.9)))
            ctx.stroke(band, with: .color(.black.opacity(0.3)), lineWidth: 1 * px)

        case .cork:
            let cork = Gradient(stops: [.init(color: Color(hex: 0x9B6B43), location: 0),
                                        .init(color: Color(hex: 0xD9B48C), location: 0.4),
                                        .init(color: Color(hex: 0xE8CBA6), location: 0.55),
                                        .init(color: Color(hex: 0xA77750), location: 1)])
            var shape = Path()
            shape.move(to: CGPoint(x: rect.minX - 1, y: rect.minY))
            shape.addLine(to: CGPoint(x: rect.maxX + 1, y: rect.minY))
            shape.addLine(to: CGPoint(x: rect.maxX - 1.5, y: rect.maxY))
            shape.addLine(to: CGPoint(x: rect.minX + 1.5, y: rect.maxY))
            shape.closeSubpath()
            ctx.fill(shape, with: .linearGradient(cork, startPoint: CGPoint(x: rect.minX, y: 0),
                                                  endPoint: CGPoint(x: rect.maxX, y: 0)))
            var pores = Path()
            for (i, dot) in [(43.0, 7.0), (52.0, 11.0), (47.0, 16.0), (56.0, 6.0), (45.0, 20.0)].enumerated() {
                let r: CGFloat = i % 2 == 0 ? 0.9 : 0.6
                pores.addEllipse(in: CGRect(x: dot.0 - r, y: dot.1 - r, width: r * 2, height: r * 2))
            }
            ctx.fill(pores, with: .color(Color(hex: 0x7A5233).opacity(0.6)))
            ctx.stroke(shape, with: .color(.black.opacity(0.25)), lineWidth: 1 * px)
        }
    }

    // MARK: - Liquid colours

    /// Colour stops for the liquid body, top (0) to bottom (1). In layered mode
    /// each drink gets a band with a short blend at each boundary, so layers
    /// read clearly without hard seams.
    static func liquidStops(geo: BottleGeometry, level: Double, theme: LiquidTheme,
                            layers: [LiquidLayer], topY: CGFloat) -> [(color: Color, location: Double)] {
        let plain: [(color: Color, location: Double)] = [(theme.surface, 0), (theme.mid, 0.32), (theme.deep, 1)]
        let total = layers.reduce(0) { $0 + $1.fraction }
        guard layers.count > 1 || (layers.first.map { $0.drink.rgb != nil } ?? false), total > 0 else {
            return plain
        }
        let span = geo.emptyY - topY
        guard span > 1 else { return plain }
        let scale = level / total
        let soft = Double(2.5 / span)
        func location(_ fraction: Double) -> Double {
            Double((geo.levelY(fraction) - topY) / span)
        }

        // Bottom-up cumulative boundaries, then walked top-down.
        var bounds: [(start: Double, color: Color)] = []
        var acc = 0.0
        for layer in layers {
            bounds.append((acc, theme.color(for: layer.drink)))
            acc += layer.fraction * scale
        }
        var stops: [(color: Color, location: Double)] = []
        var last = 0.0
        func add(_ color: Color, _ loc: Double) {
            let l = min(max(loc, last), 1)
            stops.append((color, l))
            last = l
        }
        let ordered = Array(bounds.reversed())
        add(ordered[0].color, 0)
        for i in 0..<(ordered.count - 1) {
            let boundary = location(ordered[i].start)
            add(ordered[i].color, boundary - soft)
            add(ordered[i + 1].color, boundary + soft)
        }
        add(ordered[ordered.count - 1].color, 1)
        return stops
    }
}
