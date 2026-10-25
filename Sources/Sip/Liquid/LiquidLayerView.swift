import AppKit
import QuartzCore
import SwiftUI
import SipCore

/// Draws a bottle with Core Animation, driven by the display's refresh.
///
/// SwiftUI's `TimelineView` + `Canvas` cost about 4 ms of main-thread time per
/// frame here, almost all of it in view-graph updates rather than drawing.
/// This view skips that machinery: the glass, marks and cap are images drawn
/// once, and each frame only swaps the paths and gradient positions on a
/// handful of layers, about 0.4 ms. The simulation and the look are the same.
///
/// Layers live in the bottle's 100 × 220 design space inside containers whose
/// `sublayerTransform` maps it onto the view, so every path is built in design
/// units.
final class LiquidLayerView: NSView {
    struct Config: Equatable {
        var progress: Double = 0
        var layers: [LiquidLayer] = []
        var look = BottleAppearance()
        var fizz: Double = 1
        var paused = false
        var interactive = false
        var followsWindow = false
        var extras = BottleExtras()
        var life = BottleLife()
    }

    /// Frames drawn by every bottle, for the `bench` hook.
    static var framesDrawn = 0
    /// What the most recent frame decided, for the `bench` hook.
    static var lastDecision = ""

    var onTap: (() -> Void)?
    var onPour: ((Double) -> Void)?
    /// Dragged down from the neck far enough to tip the last drink out.
    var onPourOut: (() -> Void)?

    private var config = Config()
    private let sim = LiquidSimulation()
    private var link: CADisplayLink?
    private var boostUntil: CFTimeInterval = 0
    private var currentRate: Float = 0
    private var tokens: [NSObjectProtocol] = []
    private var imageKey = ""
    private var designLayout = BottleLayout(size: CGSize(width: 100, height: 220))
    private var colorCache: [Color: CGColor] = [:]
    private var bodyColors: [Color] = []
    private var dragOrigin: CGPoint?
    private var dragging = false
    private var ghost: Double?
    /// -1…1 while dragging down from the neck; the sign is the side it tips to.
    private var pourTilt: CGFloat = 0
    private var pourOutDrag = false
    private var tank = FishTank()
    private var fishDrink = false
    private var rainDrops: [(x: CGFloat, y: CGFloat, speed: CGFloat, r: CGFloat)] = []
    private var lastRipple: CFTimeInterval = 0
    private var shakeFlips: [CFTimeInterval] = []
    private var lastShakeSign: Double = 0
    private var lastShake: CFTimeInterval = 0
    private var frostKey = ""
    private var tracking: NSTrackingArea?
    private static var sparkImage: CGImage? = makeSpark()

    // MARK: Layers

    private let stack = CALayer()          // everything, so the goal bounce scales it all
    private let behind = CALayer()         // design space: celebration glow and ring
    private let backImage = CALayer()      // glass behind the water
    private let content = CALayer()        // design space: water, droplets
    private let frontImage = CALayer()     // glass in front, marks, condensation
    private let capImage = CALayer()       // the moving part of the closure
    private let overlay = CALayer()        // design space: sparkles, confetti
    private let ghostLabel = CATextLayer()

    private let glow = CAGradientLayer()
    private let ring = CAShapeLayer()

    private let liquid = CALayer()
    private let liquidMask = CAShapeLayer()
    private let backWave = CAGradientLayer(), backWaveMask = CAShapeLayer()
    private let body = CAGradientLayer(), bodyMask = CAShapeLayer()
    private let shade = CAGradientLayer(), shadeMask = CAShapeLayer()
    private let light = CALayer(), lightMask = CAShapeLayer()
    private let rays = CAGradientLayer(), raysMask = CAShapeLayer()
    private let caustics = [CAGradientLayer(), CAGradientLayer()]
    private let bubbles = CAShapeLayer(), glints = CAShapeLayer()
    private let meniscusGlow = CAShapeLayer(), meniscus = CAShapeLayer()
    private let splashes = CAShapeLayer()

    private let ghostClip = CALayer(), ghostClipMask = CAShapeLayer()
    private let ghostFill = CAShapeLayer(), ghostLine = CAShapeLayer()

    private let stream = CAShapeLayer(), drops = CAShapeLayer(), dropGlints = CAShapeLayer()
    private let slideTrail = CAShapeLayer(), slideBead = CAShapeLayer()

    private let sparkles = CAShapeLayer()
    private let confetti = (0..<4).map { _ in CAShapeLayer() }

    // Bottle life (2.0): fish, weather on the glass, seasons, time markers.
    private let fishBodies = (0..<4).map { _ in CAShapeLayer() }
    private let fishEyes = CAShapeLayer()
    private let glassFX = CALayer()         // design space: between the glass and the cap
    private let frostLayer = CALayer()
    private let rain = CAShapeLayer()
    private let haze = (0..<3).map { _ in CAShapeLayer() }
    private let lightsBright = CAShapeLayer(), lightsDim = CAShapeLayer()
    private let snowCap = CAShapeLayer(), snowflakes = CAShapeLayer()
    private let markGlow = CAShapeLayer()

    // Bottle life: ice, lemon, steam.
    private let ice = CAShapeLayer(), iceGlints = CAShapeLayer()
    private let lemonFlesh = CAShapeLayer(), lemonRind = CAShapeLayer(), lemonSegments = CAShapeLayer()
    private let steamClip = CALayer(), steamClipMask = CAShapeLayer()
    private let steam = (0..<3).map { _ in CAShapeLayer() }

    private var designLayers: [CALayer] {
        [backWave, body, shade, light, rays, bubbles, glints, meniscusGlow, meniscus, splashes,
         ghostClip, ghostFill, ghostLine, stream, drops, dropGlints, slideTrail, slideBead,
         liquid, ring, sparkles, ice, iceGlints, lemonFlesh, lemonRind, lemonSegments, steamClip,
         fishEyes, rain, lightsBright, lightsDim, snowCap, snowflakes, markGlow] + confetti + steam + fishBodies + haze
    }

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        let root = CALayer()
        root.isGeometryFlipped = true
        layer = root
        wantsLayer = true
        buildLayers()
        observeEvents()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        tokens.forEach(NotificationCenter.default.removeObserver)
        link?.invalidate()
    }

    private func buildLayers() {
        guard let root = layer else { return }
        root.addSublayer(stack)
        stack.anchorPoint = CGPoint(x: 0.5, y: 1)
        for l in [behind, backImage, content, frontImage, glassFX, capImage, overlay] { stack.addSublayer(l) }
        root.addSublayer(ghostLabel)

        for l in [behind, content, overlay, backImage, frontImage, capImage, glassFX] {
            l.anchorPoint = .zero
        }
        frontImage.addSublayer(frostLayer)
        frostLayer.anchorPoint = .zero
        frostLayer.contentsGravity = .resize
        frostLayer.opacity = 0
        for l in [rain, lightsDim, lightsBright] + haze as [CALayer] { glassFX.addSublayer(l) }
        rain.fillColor = CGColor(gray: 1, alpha: 0.22)
        rain.strokeColor = CGColor(gray: 1, alpha: 0.55)
        for wisp in haze {
            wisp.fillColor = nil
            wisp.strokeColor = CGColor(red: 1, green: 0.85, blue: 0.6, alpha: 0.16)
            wisp.lineCap = .round
        }
        lightsBright.fillColor = CGColor(red: 1, green: 0.82, blue: 0.35, alpha: 1)
        lightsBright.shadowColor = CGColor(red: 1, green: 0.7, blue: 0.2, alpha: 1)
        lightsBright.shadowRadius = 3
        lightsBright.shadowOpacity = 1
        lightsBright.shadowOffset = .zero
        lightsDim.fillColor = CGColor(red: 1, green: 0.6, blue: 0.2, alpha: 0.45)
        snowCap.fillColor = CGColor(gray: 1, alpha: 0.95)
        snowCap.shadowColor = CGColor(gray: 0, alpha: 0.3)
        snowCap.shadowOpacity = 0.5
        snowCap.shadowRadius = 1
        snowCap.shadowOffset = .zero
        // Snow sits on top of the cap, so it goes above it.
        overlay.addSublayer(snowCap)
        overlay.addSublayer(snowflakes)
        snowflakes.fillColor = CGColor(gray: 1, alpha: 0.85)
        overlay.addSublayer(markGlow)
        markGlow.fillColor = nil
        markGlow.lineCap = .round
        markGlow.shadowOpacity = 1
        markGlow.shadowRadius = 2.5
        markGlow.shadowOffset = .zero
        for l in [backImage, frontImage, capImage] { l.contentsGravity = .resize }

        behind.addSublayer(glow)
        behind.addSublayer(ring)
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        ring.fillColor = nil

        content.addSublayer(liquid)
        liquid.mask = liquidMask
        backWave.mask = backWaveMask
        body.mask = bodyMask
        shade.mask = shadeMask
        light.mask = lightMask
        rays.mask = raysMask
        for l in [backWave, body, shade, light] as [CALayer] { liquid.addSublayer(l) }
        light.addSublayer(rays)
        rays.colors = [CGColor(gray: 1, alpha: 0.10), CGColor(gray: 1, alpha: 0)]
        for c in caustics {
            c.type = .radial
            c.startPoint = CGPoint(x: 0.5, y: 0.5)
            c.endPoint = CGPoint(x: 1, y: 1)
            c.colors = [CGColor(gray: 1, alpha: 0.11), CGColor(gray: 1, alpha: 0)]
            light.addSublayer(c)
        }
        shade.colors = [CGColor(gray: 1, alpha: 0.26), CGColor(gray: 1, alpha: 0),
                        CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.3)]

        for l in [bubbles, glints] { liquid.addSublayer(l) }
        for fish in fishBodies {
            fish.lineWidth = 0
            liquid.addSublayer(fish)
        }
        liquid.addSublayer(fishEyes)
        fishEyes.fillColor = CGColor(gray: 0.05, alpha: 0.9)
        fishEyes.strokeColor = CGColor(gray: 0.05, alpha: 0.9)
        for l in [meniscusGlow, meniscus, splashes, lemonFlesh, lemonRind, lemonSegments, ice, iceGlints] {
            liquid.addSublayer(l)
        }
        ice.fillColor = CGColor(gray: 1, alpha: 0.22)
        ice.strokeColor = CGColor(gray: 1, alpha: 0.7)
        iceGlints.fillColor = CGColor(gray: 1, alpha: 0.6)
        lemonFlesh.fillColor = CGColor(red: 1, green: 0.92, blue: 0.5, alpha: 0.95)
        lemonRind.fillColor = nil
        lemonRind.strokeColor = CGColor(red: 0.96, green: 0.77, blue: 0.05, alpha: 1)
        lemonSegments.fillColor = nil
        lemonSegments.strokeColor = CGColor(gray: 1, alpha: 0.75)
        content.addSublayer(steamClip)
        steamClip.mask = steamClipMask
        for wisp in steam {
            wisp.fillColor = nil
            wisp.strokeColor = CGColor(gray: 1, alpha: 0.28)
            wisp.lineCap = .round
            steamClip.addSublayer(wisp)
        }
        bubbles.fillColor = CGColor(gray: 1, alpha: 0.13)
        bubbles.strokeColor = CGColor(gray: 1, alpha: 0.6)
        glints.fillColor = CGColor(gray: 1, alpha: 0.85)
        meniscusGlow.fillColor = nil
        meniscusGlow.strokeColor = CGColor(gray: 1, alpha: 0.2)
        meniscus.fillColor = nil
        meniscus.strokeColor = CGColor(gray: 1, alpha: 0.7)
        for l in [meniscusGlow, meniscus] { l.lineJoin = .round; l.lineCap = .round }

        content.addSublayer(ghostClip)
        ghostClip.mask = ghostClipMask
        ghostClip.addSublayer(ghostFill)
        ghostClip.addSublayer(ghostLine)
        ghostLine.fillColor = nil
        ghostLine.strokeColor = CGColor(gray: 1, alpha: 0.95)
        ghostLine.lineCap = .round

        for l in [stream, drops, dropGlints, slideTrail, slideBead] { content.addSublayer(l) }
        stream.fillColor = nil
        stream.lineCap = .round
        stream.lineWidth = 2.6
        dropGlints.fillColor = CGColor(gray: 1, alpha: 0.75)
        slideTrail.fillColor = CGColor(gray: 1, alpha: 0.09)
        slideBead.fillColor = CGColor(gray: 1, alpha: 0.12)
        slideBead.strokeColor = CGColor(gray: 1, alpha: 0.35)

        overlay.addSublayer(sparkles)
        sparkles.fillColor = CGColor(gray: 1, alpha: 0.85)
        confetti.forEach { overlay.addSublayer($0) }

        ghostLabel.alignmentMode = .center
        ghostLabel.foregroundColor = CGColor(gray: 1, alpha: 1)
        ghostLabel.cornerRadius = 9
        ghostLabel.borderWidth = 0.5
        ghostLabel.borderColor = CGColor(gray: 1, alpha: 0.35)
        ghostLabel.isHidden = true

        // Nothing should animate implicitly: every change is a new frame.
        let none: [String: CAAction] = ["position": NSNull(), "bounds": NSNull(), "path": NSNull(),
                                         "contents": NSNull(), "hidden": NSNull(), "opacity": NSNull(),
                                         "transform": NSNull(), "colors": NSNull(), "locations": NSNull(),
                                         "startPoint": NSNull(), "endPoint": NSNull(), "string": NSNull()]
        for l in designLayers + [ghostLabel, glow, capImage, backImage, frontImage, frostLayer, liquid] + caustics { l.actions = none }
    }

    // MARK: Configuration

    func apply(_ new: Config) {
        let old = config
        config = new
        if new.progress != old.progress {
            sim.committedLevel = new.progress
            wake(2.5)
        }
        if new.look != old.look {
            sim.geometry = BottleGeometry.of(new.look)
            sim.motion = new.look.motion
            sim.bubblesEnabled = new.look.showBubbles
            sim.confettiColors = [new.look.theme.surface, new.look.theme.mid, .white, Color(hex: 0xFFE27A)]
            bodyColors = []
            needsLayout = true
            wake(1)
        }
        sim.fizz = new.fizz
        if new.life != old.life {
            sim.condensationRate = 1 + new.life.humid * 3
            if new.life.season == "holi" {
                sim.confettiColors = [Color(hex: 0xFF3EA5), Color(hex: 0xFFD23F), Color(hex: 0x3BCEAC), Color(hex: 0x5B8CFF)]
            } else if old.life.season == "holi" {
                sim.confettiColors = [new.look.theme.surface, new.look.theme.mid, .white, Color(hex: 0xFFE27A)]
            }
            if new.life.frost != old.life.frost || new.life.season != old.life.season { needsLayout = true }
            updateTracking()
            wake(1)
        }
        if new.layers != old.layers || new.extras != old.extras { wake(1) }
        if new.paused != old.paused { updateRate() }
        if new.paused { renderFrame() }   // keep the still image current
    }

    // MARK: Geometry and static images

    override func layout() {
        super.layout()
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stack.bounds = CGRect(origin: .zero, size: size)
        stack.position = CGPoint(x: size.width / 2, y: size.height)
        designLayout = BottleLayout(size: size, bleed: config.look.bleed)
        let design = CATransform3DScale(CATransform3DMakeTranslation(designLayout.origin.x, designLayout.origin.y, 0),
                                        designLayout.scale, designLayout.scale, 1)
        for container in [behind, content, overlay, glassFX] {
            container.frame = CGRect(origin: .zero, size: size)
            container.sublayerTransform = design
        }
        let designRect = CGRect(origin: .zero, size: BottleGeometry.designSize)
        let backing = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let contentScale = backing * max(1, designLayout.scale)
        for l in designLayers + caustics + [glow] {
            if l !== glow && !caustics.contains(where: { $0 === l }) { l.frame = designRect }
            l.contentsScale = contentScale
        }
        for mask in [liquidMask, backWaveMask, bodyMask, shadeMask, lightMask, raysMask, ghostClipMask, steamClipMask] {
            mask.frame = designRect
            mask.contentsScale = contentScale
        }
        let geo = BottleGeometry.of(config.look)
        liquidMask.path = geo.inner.cgPath
        ghostClipMask.path = geo.inner.cgPath
        // Steam stays inside a closed bottle but rises out of an open glass.
        steamClipMask.path = geo.cap == .none ? CGPath(rect: CGRect(x: -50, y: -80, width: 200, height: 400), transform: nil)
                                              : geo.inner.cgPath
        for l in [backImage, frontImage, capImage] {
            l.frame = CGRect(origin: .zero, size: size)
            l.contentsScale = backing
        }
        ghostLabel.contentsScale = backing
        frostLayer.frame = CGRect(origin: .zero, size: size)
        frostLayer.contentsScale = backing
        snowCap.path = config.life.season == "christmas" && geo.cap != .none ? Self.snowCapPath(geo) : nil
        CATransaction.commit()
        renderImagesIfNeeded(scale: backing)
        renderFrostIfNeeded(scale: backing)
        renderFrame()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        imageKey = ""
        needsLayout = true
    }

    private func renderImagesIfNeeded(scale: CGFloat) {
        let look = config.look
        let size = bounds.size
        let key = "\(look.imageKey)|\(size)|\(scale)"
        guard key != imageKey else { return }
        if DebugHooks.has("timing") { print("render images: \(key.prefix(120))"); fflush(stdout) }
        imageKey = key
        backImage.contents = render(size: size, scale: scale) { BottleRenderer.drawBack($0, size: $1, look: look) }
        frontImage.contents = render(size: size, scale: scale) { BottleRenderer.drawFront($0, size: $1, look: look) }
        capImage.contents = render(size: size, scale: scale) { BottleRenderer.drawCapMoving($0, size: $1, look: look) }
    }

    /// Frost is one image, faded in and out with the temperature.
    private func renderFrostIfNeeded(scale: CGFloat) {
        let wanted = config.life.frost > 0.02
        let key = wanted ? "\(config.look.imageKey)|\(bounds.size)|\(scale)" : ""
        guard key != frostKey else { return }
        frostKey = key
        guard wanted else { frostLayer.contents = nil; return }
        let look = config.look
        frostLayer.contents = render(size: bounds.size, scale: scale) { BottleRenderer.drawFrost($0, size: $1, look: look) }
    }

    /// Drawn by Core Graphics on the CPU, not by `ImageRenderer.cgImage`:
    /// that renders on the GPU and briefly took about 50 MB of graphics
    /// buffers every time a bottle appeared (the widget, the panel, Settings).
    /// The result matches to within antialiasing.
    private func render(size: CGSize, scale: CGFloat, _ draw: @escaping (GraphicsContext, CGSize) -> Void) -> CGImage? {
        let renderer = ImageRenderer(content: Canvas { context, s in draw(context, s) }
            .frame(width: size.width, height: size.height))
        let width = Int((size.width * scale).rounded(.up)), height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        renderer.render { _, draw in draw(context) }
        return context.makeImage()
    }

    // MARK: Frame pacing

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, link == nil {
            let link = displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
            currentRate = 0
            updateRate()
        } else if window == nil {
            link?.invalidate()
            link = nil
        }
    }

    /// Raise the frame rate for at least `seconds`, and for as long after that
    /// as the water is still visibly moving.
    private func wake(_ seconds: Double) {
        boostUntil = max(boostUntil, CACurrentMediaTime() + seconds)
        updateRate()
    }

    private func updateRate() {
        guard let link else { return }
        if config.paused {
            link.isPaused = true
            return
        }
        let look = config.look
        let busy = sim.isBusy || CACurrentMediaTime() < boostUntil || ghost != nil
        let rate: Float
        if busy {
            rate = Float(max(look.maxFPS, 15))
        } else if look.motion == .minimal {
            link.isPaused = true    // still water: nothing to draw until something happens
            return
        } else if let forced = DebugHooks.value("idlefps").flatMap(Float.init) {
            rate = forced
        } else if AnimationPolicy.shared.userAway || config.life.night {
            rate = 10
        } else {
            // At rest the waves move slowly enough that 20 fps reads as smooth.
            // Rates are divisors of 60 and 120 Hz: asking for 24 got 30.
            rate = look.motion == .full ? 20 : 15
        }
        link.isPaused = false
        if DebugHooks.bench { Self.lastDecision = "rate=\(rate) busy=\(busy)" }
        if rate != currentRate {
            currentRate = rate
            link.preferredFrameRateRange = CAFrameRateRange(minimum: min(rate, 8), maximum: rate, preferred: rate)
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        renderFrame()
        updateRate()
    }

    // MARK: Drawing a frame

    private func cg(_ color: Color) -> CGColor {
        if let cached = colorCache[color] { return cached }
        let value = NSColor(color).cgColor
        colorCache[color] = value
        return value
    }

    private func renderFrame() {
        guard bounds.width > 1 else { return }
        sim.step(to: Date())
        Self.framesDrawn += 1
        if DebugHooks.has("nodraw") { return }
        let geo = sim.geometry
        let look = config.look
        let px = 1 / designLayout.scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateLiquid(geo: geo, look: look, px: px)
        updateGhost(geo: geo, look: look, px: px)
        updateDrops()
        updateCondensation(px: px)
        updateCap(geo: geo)
        updateCelebration(geo: geo, look: look, px: px)
        updateExtras(geo: geo, px: px)
        updateLife(geo: geo, px: px)
        CATransaction.commit()
    }

    // MARK: Life: fish, glass weather, seasons, markers

    private func updateLife(geo: BottleGeometry, px: CGFloat) {
        let life = config.life
        let t = sim.time
        let dim: Float = life.night ? 0.72 : 1
        if liquid.opacity != dim { liquid.opacity = dim }

        // Fish, only while there's water to swim in.
        let count = sim.drawnLevel > 0.1 ? life.fish : 0
        if count == 0 {
            if !tank.fish.isEmpty { tank.fish.removeAll() }
            fishBodies.forEach { $0.path = nil }
            fishEyes.path = nil
        } else {
            tank.sync(count: count, geo: geo, surface: sim.surfaceY(at: 50))
            tank.step(time: t, geo: geo, surfaceY: { [sim] in sim.surfaceY(at: $0) },
                      sleeping: life.fishSleeping, sluggish: life.fishSluggish, drink: fishDrink)
            fishDrink = false
            let eyes = CGMutablePath()
            for (i, layer) in fishBodies.enumerated() {
                guard i < tank.fish.count else { layer.path = nil; continue }
                let fish = tank.fish[i]
                let speed = hypot(fish.velocity.dx, fish.velocity.dy)
                layer.path = fish.path(time: t, speed: speed)
                let colors = Fish.colors[fish.hue]
                layer.fillColor = colors.body
                let eye = fish.eye(asleep: life.fishSleeping)
                if eye.radius > 0 {
                    eyes.addEllipse(in: CGRect(x: eye.point.x - eye.radius, y: eye.point.y - eye.radius,
                                               width: eye.radius * 2, height: eye.radius * 2))
                } else {
                    eyes.move(to: CGPoint(x: eye.point.x - fish.size * 0.07, y: eye.point.y))
                    eyes.addLine(to: CGPoint(x: eye.point.x + fish.size * 0.07, y: eye.point.y))
                }
            }
            fishEyes.path = eyes
            fishEyes.lineWidth = 0.8 * px
        }

        // Rain running down the outside of the glass.
        if life.rain || life.season == "monsoon" {
            let body = geo.bodyRect
            if rainDrops.count < 9, Double.random(in: 0...1) < 0.06 {
                let y = body.minY + CGFloat.random(in: 0...(body.height * 0.4))
                let half = max(geo.halfWidth(at: y) - 3, 4)
                rainDrops.append((50 + CGFloat.random(in: -half...half), y, CGFloat.random(in: 4...14), CGFloat.random(in: 1.2...2.4)))
            }
            let dt: CGFloat = 1 / 20
            rainDrops = rainDrops.compactMap { d in
                var d = d
                // Stick, then slip: drops on glass move in jerks.
                d.y += d.speed * dt * (sin(Double(d.x) + t * 3) > 0.2 ? 1.8 : 0.25)
                return d.y > body.maxY ? nil : d
            }
            let path = CGMutablePath()
            for d in rainDrops {
                path.addEllipse(in: CGRect(x: d.x - d.r * 0.8, y: d.y - d.r * 1.2, width: d.r * 1.6, height: d.r * 2.2))
                path.addRoundedRect(in: CGRect(x: d.x - 0.3, y: d.y - 12, width: 0.6, height: 10),
                                    cornerWidth: 0.3, cornerHeight: 0.3)
            }
            rain.path = path
            rain.lineWidth = 0.5 * px
        } else if rain.path != nil {
            rainDrops.removeAll()
            rain.path = nil
        }

        // Frost fades in with the cold (winter adds a little anyway).
        let frost = Float(max(life.frost, life.season == "winter" ? 0.3 : 0))
        if frostLayer.opacity != frost { frostLayer.opacity = frost }

        // Heat haze above the bottle.
        if life.heat > 0.05 {
            for (i, wisp) in haze.enumerated() {
                let di = Double(i)
                let phase = (t * 0.25 + di / 3).truncatingRemainder(dividingBy: 1)
                let path = CGMutablePath()
                let x0 = 30 + CGFloat(i) * 20
                for step in 0...10 {
                    let f = CGFloat(step) / 10
                    let y = geo.mouthY - 2 - f * 40 * CGFloat(0.6 + phase * 0.4)
                    let x = x0 + CGFloat(sin(Double(f) * 6 + t * 2 + di)) * 3
                    step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                }
                wisp.path = path
                wisp.lineWidth = 3
                wisp.opacity = Float(sin(phase * .pi) * life.heat)
            }
        } else if haze[0].path != nil {
            haze.forEach { $0.path = nil }
        }

        // Diwali: a string of lights across the shoulder, twinkling.
        if life.season == "diwali" {
            let bright = CGMutablePath(), dim = CGMutablePath()
            let y0 = geo.bodyRect.minY + 4
            for i in 0..<9 {
                let f = CGFloat(i) / 8
                let half = max(geo.halfWidth(at: y0) + 1, 6)
                let x = 50 - half + f * half * 2
                let y = y0 + sin(f * .pi) * 7
                let on = sin(t * 2.2 + Double(i) * 1.3) > -0.2
                let r: CGFloat = on ? 1.7 : 1.3
                (on ? bright : dim).addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
            lightsBright.path = bright
            lightsDim.path = dim
        } else if lightsBright.path != nil {
            lightsBright.path = nil
            lightsDim.path = nil
        }

        // Christmas: a few flakes drifting past.
        if life.season == "christmas" {
            let flakes = CGMutablePath()
            for i in 0..<10 {
                let di = Double(i)
                let fall = (t * (6 + di) + di * 37).truncatingRemainder(dividingBy: 250)
                let x = CGFloat(8 + (di * 9.7).truncatingRemainder(dividingBy: 84)) + CGFloat(sin(t + di)) * 3
                let y = CGFloat(fall) - 20
                let r: CGFloat = i % 3 == 0 ? 1.4 : 0.9
                flakes.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
            snowflakes.path = flakes
        } else if snowflakes.path != nil {
            snowflakes.path = nil
        }

        // The next time marker, lit.
        if let next = life.nextMark, config.look.showTicks || !config.look.timeMarks.isEmpty, next > 0, next <= 1 {
            let y = geo.levelY(next)
            let left = 50 - geo.halfWidth(at: y)
            let line = CGMutablePath()
            line.move(to: CGPoint(x: left + 1.5, y: y))
            line.addLine(to: CGPoint(x: left + 11, y: y))
            markGlow.path = line
            markGlow.lineWidth = 1.6 * px
            let ahead = sim.drawnLevel >= next
            let color = ahead ? cg(Palette.goal) : cg(config.look.theme.surface)
            markGlow.strokeColor = color
            markGlow.shadowColor = color
        } else if markGlow.path != nil {
            markGlow.path = nil
        }
    }

    private static func snowCapPath(_ geo: BottleGeometry) -> CGPath {
        let r = geo.capRect
        let path = CGMutablePath()
        path.move(to: CGPoint(x: r.minX - 1.5, y: r.minY + 3))
        path.addCurve(to: CGPoint(x: r.maxX + 1.5, y: r.minY + 3), control1: CGPoint(x: r.minX + 2, y: r.minY - 7),
                      control2: CGPoint(x: r.maxX - 2, y: r.minY - 7))
        path.addCurve(to: CGPoint(x: r.minX - 1.5, y: r.minY + 3), control1: CGPoint(x: r.midX + 6, y: r.minY + 6),
                      control2: CGPoint(x: r.midX - 6, y: r.minY + 2))
        path.closeSubpath()
        return path
    }

    /// Ice cubes and a lemon slice bob at the surface; steam drifts up from a
    /// hot drink. Each costs nothing when it's off.
    private func updateExtras(geo: BottleGeometry, px: CGFloat) {
        let extras = config.extras
        let level = sim.drawnLevel
        let t = sim.time
        let hasWater = level > 0.06

        if extras.iceCubes > 0, hasWater {
            let cubes = CGMutablePath(), shine = CGMutablePath()
            let spots: [CGFloat] = [40, 58, 49]
            for i in 0..<min(extras.iceCubes, spots.count) {
                let di = Double(i)
                let size: CGFloat = 10 - CGFloat(i)
                let x = spots[i] + CGFloat(sin(t * 0.5 + di * 2)) * 2
                let y = sim.surfaceY(at: x) - size * 0.25 + CGFloat(sin(t * 1.3 + di)) * 0.7
                let angle = CGFloat(atan(sim.tilt)) + CGFloat(sin(t * 0.7 + di * 1.7)) * 0.18
                let turn = CGAffineTransform(translationX: x, y: y).rotated(by: angle)
                cubes.addRoundedRect(in: CGRect(x: -size / 2, y: -size / 2, width: size, height: size),
                                     cornerWidth: 2, cornerHeight: 2, transform: turn)
                shine.addRoundedRect(in: CGRect(x: -size / 2 + 1.5, y: -size / 2 + 1.5, width: size * 0.35, height: size * 0.18),
                                     cornerWidth: 0.6, cornerHeight: 0.6, transform: turn)
            }
            ice.path = cubes
            ice.lineWidth = 0.7 * px
            iceGlints.path = shine
        } else {
            ice.path = nil
            iceGlints.path = nil
        }

        if extras.lemon, hasWater {
            // A slice floating edge-on: an ellipse with rind and segments.
            let x: CGFloat = extras.iceCubes > 0 ? 66 : 56
            let y = sim.surfaceY(at: x) - 0.5
            let angle = CGFloat(atan(Double(sim.surfaceY(at: x + 4) - sim.surfaceY(at: x - 4)) / 8))
            let turn = CGAffineTransform(translationX: x, y: y).rotated(by: angle)
            let w: CGFloat = 20, h: CGFloat = 6.5
            lemonFlesh.path = CGPath(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), transform: [turn])
            lemonRind.path = lemonFlesh.path
            lemonRind.lineWidth = 1.3 * px
            let segments = CGMutablePath()
            for k in 0..<6 {
                let a = CGFloat(k) / 6 * .pi * 2
                segments.move(to: .zero, transform: turn)
                segments.addLine(to: CGPoint(x: cos(a) * w * 0.42, y: sin(a) * h * 0.42), transform: turn)
            }
            lemonSegments.path = segments
            lemonSegments.lineWidth = 0.5 * px
        } else {
            lemonFlesh.path = nil
            lemonRind.path = nil
            lemonSegments.path = nil
        }

        if extras.steam, hasWater {
            let surface = sim.surfaceY(at: 50)
            let top = geo.cap == .none ? surface - 60 : max(geo.mouthY + 6, surface - 46)
            let height = max(surface - top, 8)
            for (i, wisp) in steam.enumerated() {
                let di = Double(i)
                let x0 = 42 + CGFloat(i) * 8
                // Each wisp rises and fades on its own cycle.
                let phase = (t * 0.35 + di / 3).truncatingRemainder(dividingBy: 1)
                let path = CGMutablePath()
                for step in 0...12 {
                    let f = CGFloat(step) / 12
                    let y = surface - 2 - f * height * CGFloat(0.55 + 0.45 * phase)
                    let x = x0 + CGFloat(sin(Double(f) * 5 + t * 1.4 + di * 2)) * (2 + f * 4)
                    step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                }
                wisp.path = path
                wisp.lineWidth = 2.4
                wisp.opacity = Float(sin(phase * .pi) * 0.9)
            }
        } else {
            steam.forEach { $0.path = nil }
        }
    }

    private static let designHeight = BottleGeometry.designSize.height

    private func unitY(_ y: CGFloat) -> CGFloat { y / Self.designHeight }

    private func wavePath(geo: BottleGeometry, front: Bool, bottom: CGFloat) -> CGPath {
        let bounds = geo.inner.boundingRect
        let minX = bounds.minX - 1, maxX = bounds.maxX + 1
        let path = CGMutablePath()
        let steps = 34
        for i in 0...steps {
            let x = minX + (maxX - minX) * CGFloat(i) / CGFloat(steps)
            let y = front ? sim.surfaceY(at: x) : sim.backSurfaceY(at: x)
            i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: maxX, y: bottom))
        path.addLine(to: CGPoint(x: minX, y: bottom))
        path.closeSubpath()
        return path
    }

    private func updateLiquid(geo: BottleGeometry, look: BottleAppearance, px: CGFloat) {
        let level = sim.drawnLevel
        liquid.isHidden = level <= 0.002
        guard !liquid.isHidden else { return }
        let theme = look.theme
        let topY = geo.levelY(level) - 7
        let bottom = geo.emptyY + 6
        let front = wavePath(geo: geo, front: true, bottom: bottom)
        backWaveMask.path = wavePath(geo: geo, front: false, bottom: bottom)
        bodyMask.path = front
        shadeMask.path = front
        lightMask.path = front

        let top = CGPoint(x: 0.5, y: unitY(topY))
        let base = CGPoint(x: 0.5, y: unitY(geo.emptyY))

        // The back wave peeks over the front one at its crests.
        backWave.colors = [cg(theme.surface.opacity(0.55)), cg(theme.mid.opacity(0.5))]
        backWave.startPoint = top
        backWave.endPoint = CGPoint(x: 0.5, y: unitY(topY + 30))

        let stops = BottleRenderer.liquidStops(geo: geo, level: level, theme: theme,
                                               layers: look.layered ? config.layers : [], topY: topY)
        // Compared as colours, not strings: describing a Color every frame
        // showed up in profiles.
        let colors = stops.map(\.color)
        if colors != bodyColors {
            bodyColors = colors
            body.colors = colors.map(cg)
        }
        body.locations = stops.map { NSNumber(value: $0.location) }
        body.startPoint = top
        body.endPoint = base

        // Light just under the surface, darker toward the base.
        let span = max(geo.emptyY - topY, 1)
        let lightEnd = min(20 / span, 0.45)
        shade.locations = [0, NSNumber(value: Double(lightEnd)),
                           NSNumber(value: Double(max(lightEnd, min(10 / span + 0.05, 0.5)))), 1]
        shade.startPoint = top
        shade.endPoint = base

        light.isHidden = look.motion == .minimal
        if !light.isHidden {
            let t = sim.time
            let shafts = CGMutablePath()
            for i in 0..<2 {
                let x = 28 + CGFloat(i) * 34 + CGFloat(sin(t * 0.21 + Double(i) * 1.8)) * 9
                shafts.move(to: CGPoint(x: x - 3, y: topY))
                shafts.addLine(to: CGPoint(x: x + 7, y: topY))
                shafts.addLine(to: CGPoint(x: x + 20, y: geo.emptyY))
                shafts.addLine(to: CGPoint(x: x + 4, y: geo.emptyY))
                shafts.closeSubpath()
            }
            raysMask.path = shafts
            rays.startPoint = top
            rays.endPoint = base
            for (i, c) in caustics.enumerated() {
                let di = Double(i)
                let cx = 50 + CGFloat(sin(t * 0.37 + di * 2.1)) * 26
                let cy = topY + (geo.emptyY - topY) * CGFloat(0.32 + 0.22 * sin(t * 0.29 + di * 1.7))
                let r: CGFloat = 16 + CGFloat(i) * 5
                c.frame = CGRect(x: cx - r, y: cy - r * 0.7, width: r * 2, height: r * 1.4)
            }
        }

        if sim.bubbles.isEmpty {
            bubbles.path = nil
            glints.path = nil
        } else {
            let circles = CGMutablePath(), sparks = CGMutablePath()
            for b in sim.bubbles {
                let r = b.r
                circles.addEllipse(in: CGRect(x: b.x - r, y: b.y - r, width: r * 2, height: r * 2))
                let hr = r * 0.32
                sparks.addEllipse(in: CGRect(x: b.x - r * 0.4 - hr, y: b.y - r * 0.4 - hr, width: hr * 2, height: hr * 2))
            }
            bubbles.path = circles
            bubbles.lineWidth = 0.55 * px
            glints.path = sparks
        }

        // Meniscus: a bright line with a soft glow.
        let y0 = geo.levelY(level)
        let half = geo.halfWidth(at: y0) + 2
        let line = CGMutablePath()
        for i in 0...26 {
            let x = 50 - half + half * 2 * CGFloat(i) / 26
            let p = CGPoint(x: x, y: sim.surfaceY(at: x))
            i == 0 ? line.move(to: p) : line.addLine(to: p)
        }
        meniscusGlow.path = line
        meniscusGlow.lineWidth = 3.4 * px
        meniscus.path = line
        meniscus.lineWidth = 1.1 * px

        if sim.splashes.isEmpty {
            splashes.path = nil
        } else {
            let path = CGMutablePath()
            for p in sim.splashes {
                let r = p.size * CGFloat(max(0.2, 1 - p.age / p.life))
                path.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
            splashes.path = path
            splashes.fillColor = cg((sim.splashes.first?.color ?? theme.surface).opacity(0.9))
        }
    }

    private func updateDrops() {
        guard !sim.drops.isEmpty else {
            stream.path = nil
            drops.path = nil
            dropGlints.path = nil
            return
        }
        let sorted = sim.drops.sorted { $0.y < $1.y }
        // A thin stream joins droplets that are close together, so a big pour
        // reads as a stream rather than a dotted line.
        let joins = CGMutablePath()
        for (a, b) in zip(sorted, sorted.dropFirst()) where b.y - a.y < 26 {
            joins.move(to: CGPoint(x: a.x, y: a.y))
            joins.addLine(to: CGPoint(x: b.x, y: b.y))
        }
        let shapes = CGMutablePath(), shine = CGMutablePath()
        for d in sorted {
            let w: CGFloat = 4.2
            let h = w + min(d.vy * 0.013, 10)
            let rect = CGRect(x: d.x - w / 2, y: d.y - h, width: w, height: h)
            shapes.addRoundedRect(in: rect, cornerWidth: w / 2, cornerHeight: w / 2)
            shine.addRoundedRect(in: CGRect(x: rect.minX + 0.7, y: rect.minY + 0.8, width: 1, height: h * 0.55),
                                 cornerWidth: 0.5, cornerHeight: 0.5)
        }
        let color = sorted[0].color
        stream.path = joins
        stream.strokeColor = cg(color.opacity(0.75))
        drops.path = shapes
        drops.fillColor = cg(color)
        dropGlints.path = shine
    }

    private func updateCondensation(px: CGFloat) {
        guard config.look.showCondensation, let slide = sim.slidingBead else {
            slideTrail.path = nil
            slideBead.path = nil
            return
        }
        let b = slide.bead
        slideTrail.path = CGPath(roundedRect: CGRect(x: b.x - b.r * 0.5, y: b.y, width: b.r, height: slide.offset),
                                 cornerWidth: b.r * 0.5, cornerHeight: b.r * 0.5, transform: nil)
        slideBead.path = CGPath(ellipseIn: CGRect(x: b.x - b.r, y: b.y + slide.offset - b.r, width: b.r * 2, height: b.r * 2),
                                transform: nil)
        slideBead.lineWidth = 0.5 * px
        let fade = Float(min(slide.offset / 4, 1))
        slideTrail.opacity = fade
        slideBead.opacity = fade
    }

    private func updateCap(geo: BottleGeometry) {
        capImage.isHidden = geo.cap == .none
        let motion = BottleRenderer.capMotion(geo, open: CGFloat(sim.capOpen))
        guard motion.angle != 0 || motion.lift != 0 else {
            capImage.setAffineTransform(.identity)
            return
        }
        // Lift, then turn about the hinge, all in view coordinates.
        let s = designLayout.scale
        let hinge = designLayout.toView(motion.hinge)
        let transform = CGAffineTransform(translationX: 0, y: -motion.lift * s)
            .concatenating(CGAffineTransform(translationX: -hinge.x, y: -hinge.y))
            .concatenating(CGAffineTransform(rotationAngle: motion.angle))
            .concatenating(CGAffineTransform(translationX: hinge.x, y: hinge.y))
        capImage.setAffineTransform(transform)
    }

    private func updateCelebration(geo: BottleGeometry, look: BottleAppearance, px: CGFloat) {
        let theme = look.theme
        let center = CGPoint(x: 50, y: geo.levelY(0.55))

        glow.isHidden = sim.glow <= 0
        if !glow.isHidden {
            // An upright oval that fades out before the edge of the view.
            let maxRadius = bounds.width / designLayout.scale / 2 - 2
            let r = min(70 + CGFloat(1 - sim.glow) * 30, maxRadius / 0.7)
            glow.frame = CGRect(x: center.x - r * 0.7, y: center.y - r * 1.15, width: r * 1.4, height: r * 2.3)
            glow.colors = [cg(theme.mid.opacity(0.6 * sim.glow)), cg(theme.mid.opacity(0.2 * sim.glow)), CGColor(gray: 0, alpha: 0)]
            glow.locations = [0, 0.5, 1]
        }

        if let age = sim.ringAge {
            let r = 34 + CGFloat(age) * 150
            let alpha = max(0, 1 - age / 1.1)
            ring.isHidden = false
            ring.path = CGPath(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2), transform: nil)
            ring.strokeColor = cg(theme.surface.opacity(0.85 * alpha))
            ring.lineWidth = (1 + 3 * CGFloat(alpha)) * px * 1.5
        } else {
            ring.isHidden = true
        }

        if sim.isOverflowing, look.motion != .minimal {
            let t = sim.time
            let stars = CGMutablePath()
            for i in 0..<6 {
                let di = Double(i)
                let s = CGFloat(max(0, sin(t * 2.6 + di * 1.9)))
                guard s > 0.05 else { continue }
                let x = 50 + CGFloat(sin(di * 12.9898) * 0.5) * 56
                let y = geo.fullY - 4 + CGFloat(abs(sin(di * 78.233))) * 18
                let r = 3.4 * s
                stars.move(to: CGPoint(x: x, y: y - r))
                stars.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x, y: y))
                stars.addQuadCurve(to: CGPoint(x: x, y: y + r), control: CGPoint(x: x, y: y))
                stars.addQuadCurve(to: CGPoint(x: x - r, y: y), control: CGPoint(x: x, y: y))
                stars.addQuadCurve(to: CGPoint(x: x, y: y - r), control: CGPoint(x: x, y: y))
            }
            sparkles.path = stars
        } else {
            sparkles.path = nil
        }

        if sim.confetti.isEmpty {
            confetti.forEach { $0.path = nil }
        } else {
            let colors = sim.confettiColors
            let paths = colors.map { _ in CGMutablePath() }
            for p in sim.confetti {
                let index = colors.firstIndex(of: p.color) ?? 0
                let life = p.age / p.life
                let scale = CGFloat(max(0.15, 1 - life * life))
                let w = p.size * scale, h = p.size * 1.55 * scale
                let turn = CGAffineTransform(translationX: p.x, y: p.y)
                    .rotated(by: CGFloat(atan2(Double(p.vy), Double(p.vx)) + .pi / 2))
                let drop = CGMutablePath()
                drop.move(to: CGPoint(x: 0, y: -h / 2))
                drop.addQuadCurve(to: CGPoint(x: w / 2, y: h * 0.15), control: CGPoint(x: w / 2, y: -h * 0.1))
                drop.addQuadCurve(to: CGPoint(x: -w / 2, y: h * 0.15), control: CGPoint(x: 0, y: h * 0.62))
                drop.addQuadCurve(to: CGPoint(x: 0, y: -h / 2), control: CGPoint(x: -w / 2, y: -h * 0.1))
                paths[index % paths.count].addPath(drop, transform: turn)
            }
            for (i, layer) in confetti.enumerated() {
                layer.path = i < paths.count ? paths[i] : nil
                if i < colors.count { layer.fillColor = cg(colors[i]) }
            }
        }
    }

    private func updateGhost(geo: BottleGeometry, look: BottleAppearance, px: CGFloat) {
        guard let ghost else {
            ghostFill.path = nil
            ghostLine.path = nil
            ghostLabel.isHidden = true
            return
        }
        let y = geo.levelY(min(ghost, 1))
        let current = geo.levelY(sim.drawnLevel)
        ghostFill.path = y < current ? CGPath(rect: CGRect(x: 0, y: y, width: 100, height: current - y), transform: nil) : nil
        ghostFill.fillColor = cg(look.theme.surface.opacity(0.3))
        let half = geo.halfWidth(at: y)
        let line = CGMutablePath()
        line.move(to: CGPoint(x: 50 - half, y: y))
        line.addLine(to: CGPoint(x: 50 + half, y: y))
        ghostLine.path = line
        ghostLine.lineWidth = 1.4 * px
        ghostLine.lineDashPattern = [NSNumber(value: Double(3.5 * px)), NSNumber(value: Double(2.5 * px))]

        let ml = Volume.snap(max(ghost - config.progress, 0) * look.goalML, look.unit)
        let text = "+" + Volume.format(ml, look.unit)
        let font = NSFont.systemFont(ofSize: 11, weight: .bold)
        let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 11) } ?? font
        let width = (text as NSString).size(withAttributes: [.font: rounded]).width + 14
        let anchor = designLayout.toView(CGPoint(x: 50, y: y))
        ghostLabel.isHidden = false
        ghostLabel.string = text
        ghostLabel.font = rounded
        ghostLabel.fontSize = 11
        ghostLabel.backgroundColor = cg(look.theme.deep.opacity(0.88))
        ghostLabel.frame = CGRect(x: anchor.x - width / 2, y: anchor.y - 24, width: width, height: 18)
    }

    // MARK: Events

    private func observeEvents() {
        let center = NotificationCenter.default
        func observe(_ name: Notification.Name, _ handler: @escaping (LiquidLayerView, Notification) -> Void) {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                MainActor.assumeIsolated { handler(self, note) }
            })
        }
        observe(SipEvents.pour) { view, note in
            let fraction = note.userInfo?["fraction"] as? Double ?? 0
            let drink = DrinkKind(rawValue: note.userInfo?["drink"] as? String ?? "") ?? .water
            view.sim.pour(fraction: fraction, color: view.config.look.theme.color(for: drink), carbonated: drink.isCarbonated)
            view.fishDrink = true
            view.wake(3.5)
        }
        observe(SipEvents.celebrate) { view, note in
            let named = (note.userInfo?["style"] as? String).flatMap(CelebrationStyle.init(rawValue:))
            view.celebrate(named ?? view.config.look.celebration.resolved())
        }
        observe(SipEvents.wobble) { view, _ in
            view.sim.wobble()
            view.wake(3)
        }
        observe(SipEvents.drain) { view, _ in
            view.sim.drain()
            view.wake(2.5)
        }
        observe(SipEvents.windowMoved) { view, note in
            guard view.config.followsWindow else { return }
            let dvx = note.userInfo?["dvx"] as? Double ?? 0
            view.sim.windowAccelerated(dvx: dvx, dvy: note.userInfo?["dvy"] as? Double ?? 0)
            view.detectShake(dvx: dvx)
            view.wake(2)
        }
    }

    /// Three sharp changes of direction within a second: a shake.
    private func detectShake(dvx: Double) {
        guard config.life.playful, abs(dvx) > 500 else { return }
        let sign = dvx > 0 ? 1.0 : -1.0
        guard sign != lastShakeSign else { return }
        lastShakeSign = sign
        let now = CACurrentMediaTime()
        shakeFlips = shakeFlips.filter { now - $0 < 1.0 } + [now]
        if shakeFlips.count >= 3, now - lastShake > 2 {
            lastShake = now
            shakeFlips.removeAll()
            sim.shake()
            wake(3)
        }
    }

    // MARK: Celebrations

    private func celebrate(_ style: CelebrationStyle) {
        sim.celebrate()
        wake(4)
        bounce()
        guard config.look.motion != .minimal else { return }
        let geo = sim.geometry
        switch style {
        case .confetti, .surprise:
            break
        case .crown:
            sim.crown(color: config.look.theme.surface)
        case .bubbles:
            sim.bubbleStorm()
        case .fireworks:
            for (i, point) in [CGPoint(x: 26, y: geo.mouthY - 22), CGPoint(x: 74, y: geo.mouthY - 34),
                               CGPoint(x: 50, y: geo.mouthY - 50)].enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.35) { [weak self] in
                    self?.burst(at: point)
                }
            }
        case .rainbow:
            rainbowSweep(geo: geo)
        }
    }

    /// One firework burst. The emitter runs in the render server, then goes.
    private func burst(at point: CGPoint) {
        guard let spark = Self.sparkImage else { return }
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = point
        emitter.emitterShape = .point
        emitter.renderMode = .additive
        let theme = config.look.theme
        emitter.emitterCells = [theme.surface, Color(hex: 0xFFE27A), Color(hex: 0xFF7EB6)].map { color in
            let cell = CAEmitterCell()
            cell.contents = spark
            cell.color = cg(color)
            cell.birthRate = 260
            cell.lifetime = 1.1
            cell.lifetimeRange = 0.3
            cell.velocity = 62
            cell.velocityRange = 18
            cell.emissionRange = .pi * 2
            cell.yAcceleration = 70
            cell.scale = 0.09
            cell.scaleSpeed = -0.06
            cell.alphaSpeed = -0.9
            return cell
        }
        emitter.frame = CGRect(origin: .zero, size: BottleGeometry.designSize)
        emitter.beginTime = CACurrentMediaTime()
        overlay.addSublayer(emitter)
        // A burst, not a fountain.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { emitter.birthRate = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { emitter.removeFromSuperlayer() }
    }

    private func rainbowSweep(geo: BottleGeometry) {
        let band = CAGradientLayer()
        band.frame = CGRect(x: 0, y: 0, width: 100, height: 220)
        band.colors = [Color(hex: 0xFF5E7E), Color(hex: 0xFFB347), Color(hex: 0xFFF275), Color(hex: 0x6BF178),
                       Color(hex: 0x56C7FF), Color(hex: 0xB28DFF)].map { cg($0.opacity(0.55)) }
        band.startPoint = CGPoint(x: 0, y: 1)
        band.endPoint = CGPoint(x: 1, y: 0)
        band.opacity = 0
        liquid.addSublayer(band)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.2, 0.7, 1]
        let slide = CABasicAnimation(keyPath: "position.y")
        slide.fromValue = 220 + 110
        slide.toValue = -110
        let group = CAAnimationGroup()
        group.animations = [fade, slide]
        group.duration = 2.4
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        band.add(group, forKey: "sweep")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { band.removeFromSuperlayer() }
    }

    private static func makeSpark() -> CGImage? {
        let size = 24
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return nil }
        let c = CGPoint(x: size / 2, y: size / 2)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(size) / 2, options: [])
        return ctx.makeImage()
    }

    private func applyTilt(_ angle: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stack.setAffineTransform(CGAffineTransform(rotationAngle: angle))
        CATransaction.commit()
    }

    private func springUpright() {
        let current = stack.affineTransform()
        stack.setAffineTransform(.identity)
        let spring = CASpringAnimation(keyPath: "transform.rotation.z")
        spring.fromValue = atan2(current.b, current.a)
        spring.toValue = 0
        spring.stiffness = 220
        spring.damping = 12
        spring.duration = spring.settlingDuration
        stack.add(spring, forKey: "upright")
    }

    /// Tips all the way, pours out the last drink, then rights itself.
    private func tipOut(toLeft: Bool) {
        let angle: CGFloat = toLeft ? -0.62 : 0.62
        applyTilt(angle)
        sim.spill(color: config.look.theme.surface, toLeft: toLeft)
        wake(3)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.onPourOut?()
            self?.springUpright()
        }
    }

    /// The whole bottle bounces when the goal is reached.
    private func bounce() {
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 1.07
        spring.toValue = 1
        spring.stiffness = 260
        spring.damping = 7
        spring.duration = spring.settlingDuration
        stack.add(spring, forKey: "bounce")
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Only interactive bottles take clicks; previews let them fall through
    /// to the button around them.
    override func hitTest(_ point: NSPoint) -> NSView? {
        config.interactive ? super.hitTest(point) : nil
    }

    private func updateTracking() {
        let wanted = config.interactive && config.life.playful
        if wanted, tracking == nil {
            let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
            addTrackingArea(area)
            tracking = area
        } else if !wanted, let tracking {
            removeTrackingArea(tracking)
            self.tracking = nil
        }
    }

    /// The cursor brushing the surface leaves a ripple.
    override func mouseMoved(with event: NSEvent) {
        let now = CACurrentMediaTime()
        guard config.life.playful, now - lastRipple > 0.14, sim.drawnLevel > 0.05 else { return }
        let point = designLayout.toDesign(convert(event.locationInWindow, from: nil))
        guard abs(point.y - sim.surfaceY(at: point.x)) < 9, abs(point.x - 50) < sim.geometry.halfWidth(at: point.y) else { return }
        lastRipple = now
        sim.ripple(at: point.x, amplitude: -1.8)
        wake(1.5)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragOrigin = point
        dragging = false
        // Grabbing the neck (above the full line) can tip the bottle out.
        pourOutDrag = config.life.pourOut && designLayout.toDesign(point).y < sim.geometry.fullY - 2
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        let point = convert(event.locationInWindow, from: nil)
        if !dragging, hypot(point.x - origin.x, point.y - origin.y) > 6 { dragging = true }
        if dragging, pourOutDrag {
            // Down and to a side tips the bottle that way.
            let down = max(point.y - origin.y, 0)
            let side: CGFloat = point.x < origin.x ? -1 : 1
            pourTilt = side * min(down / 90, 1)
            applyTilt(pourTilt * 0.45)
            return
        }
        guard dragging, config.progress < 1 else { return }
        let design = designLayout.toDesign(point)
        let fraction = BottleGeometry.of(config.look).fraction(atY: design.y)
        ghost = min(max(fraction, config.progress), 1)
        wake(1)
        renderFrame()
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragOrigin = nil
            dragging = false
            pourOutDrag = false
            pourTilt = 0
        }
        if pourOutDrag {
            if abs(pourTilt) > 0.55 {
                tipOut(toLeft: pourTilt < 0)
            } else {
                springUpright()
            }
            return
        }
        if let ghost {
            self.ghost = nil
            let ml = Volume.snap((ghost - config.progress) * config.look.goalML, config.look.unit)
            renderFrame()
            if ml >= 10 { onPour?(ml) }
        } else if !dragging {
            sim.tap()
            wake(2)
            onTap?()
        }
    }
}
