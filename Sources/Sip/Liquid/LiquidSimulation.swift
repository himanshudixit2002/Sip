import SwiftUI
import SipCore

/// The water's physical state, advanced once per rendered frame. All positions
/// are in the bottle's 100 × 220 design space, all times in seconds.
///
/// Nothing here is observable: the renderer steps it from inside a `Canvas`
/// closure, and actions arrive from event handlers. Keeping it out of SwiftUI's
/// dependency graph means a frame never triggers a view update.
final class LiquidSimulation {
    struct Bubble {
        var x0: CGFloat
        var y: CGFloat
        var r: CGFloat
        var phase: Double
        var freq: Double
        var age: Double = 0
        var x: CGFloat { x0 + CGFloat(sin(age * freq + phase)) * (0.8 + r * 0.5) }
    }

    struct Drop {
        var x: CGFloat
        var y: CGFloat
        var vy: CGFloat
        var share: Double
        var color: Color
    }

    struct Particle {
        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat
        var vy: CGFloat
        var size: CGFloat
        var life: Double
        var age: Double = 0
        var color: Color
        var spin: Double = 0
    }

    struct Ripple {
        var x: CGFloat
        var amplitude: CGFloat
        var age: Double = 0
    }

    struct Bead {
        var x: CGFloat
        var y: CGFloat
        var r: CGFloat
    }

    // MARK: Inputs, set by the view every frame

    var geometry = BottleGeometry.of(.classic) {
        didSet { if geometry.id != oldValue.id { slidingBead = nil } }
    }
    var motion: MotionLevel = .full
    var bubblesEnabled = true
    /// Multiplies the idle bubble rate: higher for sparkling drinks.
    var fizz: Double = 1
    var confettiColors: [Color] = [.white]
    /// Humid air: beads of condensation run down the glass more often.
    var condensationRate: Double = 1
    /// The level the store says the bottle should be at, as a fraction of the goal.
    var committedLevel: Double = 0

    // MARK: State

    private(set) var level: Double = 0
    private var levelVelocity: Double = 0
    /// Surface slope, dy per unit x. Positive tips the right side down.
    private(set) var tilt: Double = 0
    private var tiltVelocity: Double = 0
    private(set) var energy: Double = 0
    private(set) var time: Double = 0
    private(set) var bubbles: [Bubble] = []
    private(set) var drops: [Drop] = []
    private(set) var splashes: [Particle] = []
    private(set) var ripples: [Ripple] = []
    private(set) var confetti: [Particle] = []
    /// A drop of condensation running down the glass, and how far it's gone.
    private(set) var slidingBead: (bead: Bead, offset: CGFloat)?
    private(set) var capOpen: Double = 0
    private var capVelocity: Double = 0
    private var capTarget: Double = 0
    private(set) var glow: Double = 0
    private(set) var ringAge: Double?

    private var pourDeficit: Double = 0
    private var scheduled: [(at: Double, share: Double, color: Color)] = []
    private var capCloseAt: Double?
    private var lastDate: Date?
    private var bubbleDebt: Double = 0
    private var nextSlideAt: Double = 6
    private var initialised = false

    init() {}

    // MARK: Derived

    /// Where the drawn level is heading: the store's level minus whatever is
    /// still in the air as droplets.
    private var visualTarget: Double { max(committedLevel - pourDeficit, 0) }

    /// The level used for drawing: past 100% the bottle just stays full.
    var drawnLevel: Double { min(max(level, 0), 1.0) }

    var isOverflowing: Bool { level >= 0.995 }

    /// True while something is visibly moving and the frame rate should stay up.
    var isBusy: Bool {
        !drops.isEmpty || !splashes.isEmpty || !confetti.isEmpty || !scheduled.isEmpty
            || abs(levelVelocity) > 0.003 || abs(level - visualTarget) > 0.002
            || abs(tiltVelocity) > 0.01 || abs(tilt) > 0.004
            || energy > 0.06 || capOpen > 0.01 || glow > 0.02 || ringAge != nil
    }

    private var motionScale: Double {
        switch motion {
        case .full: return 1
        case .calm: return 0.55
        case .minimal: return 0
        }
    }

    // MARK: Surface

    /// Height of the liquid surface at `x`, including waves, tilt and ripples.
    func surfaceY(at x: CGFloat) -> CGFloat {
        let base = geometry.levelY(drawnLevel)
        // Near-empty water lies flat; there's not enough of it to slosh.
        let depthDamp = min(drawnLevel * 10, 1)
        let amplitude = (1.1 * motionScale + energy * 5.5) * depthDamp
        var y = base + CGFloat(tilt * depthDamp) * (x - BottleGeometry.centerX)
        let t = time
        y += CGFloat(amplitude) * CGFloat(0.62 * sin(Double(x) * 0.085 + t * 2.1)
                                          + 0.38 * sin(Double(x) * 0.17 - t * 1.45 + 1.3))
        for ripple in ripples {
            let travelled = CGFloat(ripple.age) * 46
            let d = abs(x - ripple.x) - travelled
            let envelope = CGFloat(exp(-ripple.age * 2.4)) * exp(-(d * d) / 70)
            y += ripple.amplitude * envelope * CGFloat(cos(Double(d) * 0.42))
        }
        return y
    }

    /// The darker wave behind the front one: same water, different phase.
    func backSurfaceY(at x: CGFloat) -> CGFloat {
        let base = geometry.levelY(drawnLevel)
        let depthDamp = min(drawnLevel * 10, 1)
        let amplitude = (1.4 * motionScale + energy * 6) * depthDamp
        var y = base - 1.6 + CGFloat(tilt * depthDamp * 0.85) * (x - BottleGeometry.centerX)
        y += CGFloat(amplitude) * CGFloat(0.55 * sin(Double(x) * 0.07 - time * 1.7 + 2.2)
                                          + 0.45 * sin(Double(x) * 0.13 + time * 1.15))
        return y
    }

    // MARK: Actions

    /// Starts a pour of `fraction` of the goal. The level rises as the droplets land.
    func pour(fraction: Double, color: Color, carbonated: Bool) {
        guard fraction > 0 else { return }
        if motion == .minimal {
            energy += 0.1
            return
        }
        pourDeficit += fraction
        let full = motion == .full
        let count = Int(min(max(6 + fraction * 26, 6), 16) * (full ? 1 : 0.6))
        let start = max(time, scheduled.last?.at ?? time) + (capOpen > 0.5 ? 0.02 : 0.16)
        for i in 0..<count {
            scheduled.append((at: start + Double(i) * 0.05, share: fraction / Double(count), color: color))
        }
        capTarget = 1
        capCloseAt = start + Double(count) * 0.05 + 0.4
        if carbonated { spawnBubbles(count: full ? 14 : 6, nearSurface: false) }
    }

    /// Water was taken away (undo, a new day).
    func drain() {
        energy += 0.25 * motionScale
        tiltVelocity += 0.4 * motionScale * (Bool.random() ? 1 : -1)
    }

    func tap() {
        energy += 0.2 * motionScale
        tiltVelocity += Double.random(in: 0.35...0.7) * motionScale * (Bool.random() ? 1 : -1)
        spawnBubbles(count: Int(4 * motionScale), nearSurface: false)
    }

    /// The gentle "have a drink" wobble.
    func wobble() {
        tiltVelocity += 0.9 * motionScale * (Bool.random() ? 1 : -1)
        energy += 0.3 * motionScale
    }

    /// The window moved: a change in horizontal speed tips the water the other way.
    func windowAccelerated(dvx: Double, dvy: Double) {
        let scale = motionScale
        tiltVelocity -= dvx * 0.0016 * scale
        energy += min(abs(dvx) + abs(dvy), 3000) * 0.00018 * scale
        tiltVelocity = min(max(tiltVelocity, -3), 3)
        energy = min(energy, 1.4)
    }

    func celebrate() {
        glow = 1
        ringAge = 0
        guard motion != .minimal else { return }
        energy += 0.5 * motionScale
        tiltVelocity += 0.7 * motionScale * (Bool.random() ? 1 : -1)
        let count = motion == .full ? 44 : 20
        let mouth = CGPoint(x: BottleGeometry.centerX, y: max(geometry.mouthY, 6))
        for _ in 0..<count {
            let angle = Double.random(in: (-Double.pi * 0.92)...(-Double.pi * 0.08))
            let speed = CGFloat(Double.random(in: 150...390))
            confetti.append(Particle(x: mouth.x + CGFloat.random(in: -6...6), y: mouth.y,
                                     vx: CGFloat(cos(angle)) * speed, vy: CGFloat(sin(angle)) * speed,
                                     size: CGFloat.random(in: 2.2...4.6), life: Double.random(in: 1.4...2.2),
                                     color: confettiColors.randomElement() ?? .white,
                                     spin: Double.random(in: -6...6)))
        }
    }

    /// The cursor brushed the surface.
    func ripple(at x: CGFloat, amplitude: CGFloat) {
        ripples.append(Ripple(x: x, amplitude: amplitude * CGFloat(max(motionScale, 0.4))))
        if ripples.count > 8 { ripples.removeFirst(ripples.count - 8) }
        energy = min(energy + 0.03, 1.2)
    }

    /// Shaken back and forth: everything churns and fizzes.
    func shake() {
        energy = min(energy + 0.6, 1.6)
        tiltVelocity += 1.4 * (Bool.random() ? 1 : -1)
        spawnBubbles(count: 24, nearSurface: false)
    }

    /// A crown of droplets thrown up from the middle of the surface.
    func crown(color: Color) {
        let surface = surfaceY(at: BottleGeometry.centerX)
        for i in 0..<28 {
            let a = Double(i) / 28 * .pi * 2
            splashes.append(Particle(x: BottleGeometry.centerX + CGFloat(cos(a)) * 8, y: surface - 1,
                                     vx: CGFloat(cos(a)) * CGFloat.random(in: 40...90),
                                     vy: -CGFloat.random(in: 220...330),
                                     size: CGFloat.random(in: 1.4...2.6), life: 1.4, color: color))
        }
        if splashes.count > 90 { splashes.removeFirst(splashes.count - 90) }
        energy = min(energy + 0.5, 1.4)
    }

    /// Bubbles everywhere.
    func bubbleStorm() {
        let old = bubblesEnabled
        bubblesEnabled = true
        spawnBubbles(count: 55, nearSurface: false)
        bubblesEnabled = old
        energy = min(energy + 0.4, 1.4)
    }

    /// Pour-out: droplets tip out of the mouth to one side.
    func spill(color: Color, toLeft: Bool) {
        let mouth = CGPoint(x: BottleGeometry.centerX + (toLeft ? -8 : 8), y: max(geometry.mouthY, 4))
        for _ in 0..<26 {
            confetti.append(Particle(x: mouth.x + CGFloat.random(in: -3...3), y: mouth.y + CGFloat.random(in: -2...2),
                                     vx: CGFloat(toLeft ? -1 : 1) * CGFloat.random(in: 60...160),
                                     vy: CGFloat.random(in: -120 ... -20),
                                     size: CGFloat.random(in: 2...3.6), life: Double.random(in: 0.9...1.4), color: color))
        }
        tiltVelocity += toLeft ? -1.6 : 1.6
        energy = min(energy + 0.4, 1.4)
    }

    /// Jumps straight to the committed level, for the first frame and after
    /// long pauses where animating the catch-up would only look like lag.
    func settleImmediately() {
        level = visualTarget
        levelVelocity = 0
    }

    // MARK: Stepping

    func step(to date: Date) {
        guard let last = lastDate else {
            lastDate = date
            if !initialised { settleImmediately(); initialised = true }
            return
        }
        lastDate = date
        var dt = date.timeIntervalSince(last)
        if dt <= 0 { return }
        if dt > 0.5 {
            // Back from a pause: don't replay the missed time.
            dt = 1.0 / 30
        }
        dt = min(dt, 1.0 / 20)
        time += dt

        // Level: slightly underdamped, so the water overshoots and settles.
        spring(&level, &levelVelocity, target: visualTarget, stiffness: 26, damping: 7.6, dt: dt)
        // Slosh: lightly damped, so it rocks a few times.
        spring(&tilt, &tiltVelocity, target: 0, stiffness: 32, damping: 2.4, dt: dt)
        tilt = min(max(tilt, -0.4), 0.4)
        energy *= exp(-dt * 1.15)
        spring(&capOpen, &capVelocity, target: capTarget, stiffness: 160, damping: 15, dt: dt)
        glow *= exp(-dt * 1.6)
        if glow < 0.01 { glow = 0 }
        if let age = ringAge { ringAge = age + dt > 1.1 ? nil : age + dt }

        if let close = capCloseAt, time >= close, scheduled.isEmpty {
            capTarget = 0
            capCloseAt = nil
        }

        releaseScheduledDrops()
        stepDrops(dt)
        stepParticles(&splashes, dt: dt, gravity: 620, dieBelowSurface: true)
        stepParticles(&confetti, dt: dt, gravity: 420, dieBelowSurface: false)
        for i in ripples.indices { ripples[i].age += dt }
        ripples.removeAll { $0.age > 2.2 }
        stepBubbles(dt)
        stepCondensation(dt)
    }

    private func spring(_ x: inout Double, _ v: inout Double, target: Double, stiffness: Double, damping: Double, dt: Double) {
        // Semi-implicit Euler: stable at these stiffnesses for dt ≤ 1/20.
        v += (-stiffness * (x - target) - damping * v) * dt
        x += v * dt
    }

    private func releaseScheduledDrops() {
        while let next = scheduled.first, next.at <= time {
            scheduled.removeFirst()
            let jitter = CGFloat.random(in: -1.6...1.6)
            let startY = geometry.mouthY + (geometry.cap == .none ? 0 : 2)
            drops.append(Drop(x: BottleGeometry.centerX + jitter, y: startY,
                              vy: CGFloat.random(in: 40...90), share: next.share, color: next.color))
        }
    }

    private func stepDrops(_ dt: Double) {
        guard !drops.isEmpty else { return }
        let g: CGFloat = 900
        var landed: [Drop] = []
        drops = drops.compactMap { d in
            var d = d
            d.vy += g * CGFloat(dt)
            d.y += d.vy * CGFloat(dt)
            if d.y >= surfaceY(at: d.x) - 1 {
                landed.append(d)
                return nil
            }
            return d
        }
        for d in landed { impact(d) }
    }

    private func impact(_ d: Drop) {
        pourDeficit = max(pourDeficit - d.share, 0)
        if scheduled.isEmpty && drops.isEmpty { pourDeficit = 0 }
        let full = motion == .full
        ripples.append(Ripple(x: d.x, amplitude: CGFloat(-2.2 - d.share * 18) * (full ? 1 : 0.6)))
        if ripples.count > 8 { ripples.removeFirst(ripples.count - 8) }
        energy = min(energy + 0.07, 1.2)
        tiltVelocity += Double.random(in: -0.12...0.12)
        let surface = surfaceY(at: d.x)
        let splashCount = full ? Int.random(in: 3...6) : 2
        for _ in 0..<splashCount {
            splashes.append(Particle(x: d.x, y: surface - 1,
                                     vx: CGFloat.random(in: -85...85), vy: CGFloat.random(in: -190 ... -70),
                                     size: CGFloat.random(in: 0.9...2.0), life: 0.9, color: d.color))
        }
        if splashes.count > 60 { splashes.removeFirst(splashes.count - 60) }
        // Air dragged under by the drop comes back up as a few bubbles.
        if bubblesEnabled {
            for _ in 0..<(full ? Int.random(in: 1...3) : 1) {
                let depth = CGFloat.random(in: 8...30)
                let y = min(surface + depth, geometry.emptyY - 3)
                if y > surface + 3 {
                    bubbles.append(Bubble(x0: d.x + CGFloat.random(in: -6...6), y: y,
                                          r: CGFloat.random(in: 0.7...1.8), phase: Double.random(in: 0...6.28),
                                          freq: Double.random(in: 3...6)))
                }
            }
        }
    }

    private func stepParticles(_ particles: inout [Particle], dt: Double, gravity: CGFloat, dieBelowSurface: Bool) {
        guard !particles.isEmpty else { return }
        particles = particles.compactMap { p in
            var p = p
            p.age += dt
            p.vy += gravity * CGFloat(dt)
            p.x += p.vx * CGFloat(dt)
            p.y += p.vy * CGFloat(dt)
            p.vx *= CGFloat(exp(-dt * 0.6))
            if p.age >= p.life { return nil }
            if dieBelowSurface, p.vy > 0, p.y >= surfaceY(at: p.x) { return nil }
            return p
        }
    }

    private func stepBubbles(_ dt: Double) {
        let hasWater = drawnLevel > 0.035
        if bubblesEnabled, hasWater, motion != .minimal {
            let rate = (motion == .full ? 0.9 : 0.35) * fizz
            bubbleDebt += rate * dt
            while bubbleDebt >= 1 {
                bubbleDebt -= 1
                spawnBubbles(count: 1, nearSurface: false)
            }
        }
        guard !bubbles.isEmpty else { return }
        bubbles = bubbles.compactMap { b in
            var b = b
            b.age += dt
            b.y -= (13 + b.r * 13) * CGFloat(dt) * (motion == .calm ? 0.7 : 1)
            if !hasWater || b.y - b.r <= surfaceY(at: b.x) { return nil }
            return b
        }
    }

    private func spawnBubbles(count: Int, nearSurface: Bool) {
        guard bubblesEnabled, count > 0, drawnLevel > 0.035 else { return }
        for _ in 0..<count where bubbles.count < 55 {
            let y = geometry.emptyY - CGFloat.random(in: 2...10)
            let half = max(geometry.halfWidth(at: y) - 5, 2)
            let r = CGFloat.random(in: 0.7...2.5)
            bubbles.append(Bubble(x0: BottleGeometry.centerX + CGFloat.random(in: -half...half), y: y, r: r,
                                  phase: Double.random(in: 0...6.28), freq: Double.random(in: 2.5...5.5)))
        }
    }

    // MARK: Condensation

    private static var beadCache: [String: [Bead]] = [:]

    /// Condensation beads, seeded so they sit in the same places every launch.
    static func beads(for geometry: BottleGeometry) -> [Bead] {
        if let cached = beadCache[geometry.id] { return cached }
        var seed: UInt64 = 0x5EED_B07 &+ UInt64(geometry.style.rawValue.count)
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Double(seed >> 33) / Double(1 << 31))
        }
        let body = geometry.bodyRect.insetBy(dx: 6, dy: 6)
        let beads = (0..<14).map { _ -> Bead in
            let y = body.minY + next() * body.height
            let half = max(geometry.halfWidth(at: y) - 2, 4)
            let x = BottleGeometry.centerX - half + next() * half * 2
            return Bead(x: x, y: y, r: 0.8 + next() * 1.7)
        }
        if beadCache.count > 24 { beadCache.removeAll() }
        beadCache[geometry.id] = beads
        return beads
    }

    private func stepCondensation(_ dt: Double) {
        guard motion == .full else { slidingBead = nil; return }
        if var sliding = slidingBead {
            sliding.offset += CGFloat(dt) * 9
            if sliding.bead.y + sliding.offset > geometry.bodyRect.maxY - 2 {
                slidingBead = nil
                nextSlideAt = time + Double.random(in: 8...16) / max(condensationRate, 0.2)
            } else {
                slidingBead = sliding
            }
        } else if time >= nextSlideAt {
            let body = geometry.bodyRect.insetBy(dx: 8, dy: 6)
            let y = body.minY + CGFloat.random(in: 0...(body.height * 0.5))
            let half = max(geometry.halfWidth(at: y) - 4, 4)
            slidingBead = (Bead(x: BottleGeometry.centerX + CGFloat.random(in: -half...half), y: y,
                                r: CGFloat.random(in: 1.4...2.2)), 0)
        }
    }
}
