import SwiftUI
import SipCore

/// What's alive in and on the widget's bottle: fish, weather on the glass,
/// seasonal touches and night mode. Only the desktop widget sets any of this;
/// previews and the popover leave it empty and pay nothing for it.
struct BottleLife: Equatable {
    var fish = 0
    var fishSleeping = false
    var fishSluggish = false
    /// 0–1: frost creeping in from the edges of the glass.
    var frost: Double = 0
    var rain = false
    /// 0–1: more condensation running down the glass.
    var humid: Double = 0
    /// 0–1: heat haze rising off the bottle.
    var heat: Double = 0
    var night = false
    /// A festival or season pack's raw value (`SeasonPack`), if one is showing.
    var season: String?
    /// Where the next time marker sits, as a fraction of the goal.
    var nextMark: Double?
    var playful = false
    var pourOut = false
}

/// A time marker on the glass: by `label` you'd ideally be at `fraction`.
struct TimeMarkSpec: Equatable {
    var fraction: Double
    var label: String
}

/// How the goal is celebrated.
enum CelebrationStyle: String, CaseIterable, Identifiable, Codable {
    case surprise, confetti, fireworks, crown, bubbles, rainbow
    var id: String { rawValue }

    var title: String {
        switch self {
        case .surprise: return "Surprise me"
        case .confetti: return "Confetti"
        case .fireworks: return "Fireworks"
        case .crown: return "Crown splash"
        case .bubbles: return "Bubble storm"
        case .rainbow: return "Rainbow wave"
        }
    }

    /// A concrete style for this celebration.
    func resolved() -> CelebrationStyle {
        guard self == .surprise else { return self }
        return [CelebrationStyle.confetti, .fireworks, .crown, .bubbles, .rainbow].randomElement() ?? .confetti
    }
}

/// One fish swimming in the bottle. Positions in design units.
struct Fish {
    var position: CGPoint
    var velocity: CGVector = .zero
    var target: CGPoint
    var phase: Double
    var size: CGFloat
    var hue: Int
    /// Seconds until it picks a new spot to swim to.
    var retarget: Double = 0
    var drinkUntil: Double = 0

    static let colors: [(body: CGColor, fin: CGColor)] = [
        (CGColor(red: 1.0, green: 0.55, blue: 0.16, alpha: 1), CGColor(red: 1.0, green: 0.82, blue: 0.5, alpha: 0.95)),
        (CGColor(red: 1.0, green: 0.84, blue: 0.24, alpha: 1), CGColor(red: 1.0, green: 0.95, blue: 0.7, alpha: 0.95)),
        (CGColor(red: 0.97, green: 0.36, blue: 0.48, alpha: 1), CGColor(red: 1.0, green: 0.75, blue: 0.82, alpha: 0.95)),
        (CGColor(red: 0.62, green: 0.48, blue: 1.0, alpha: 1), CGColor(red: 0.86, green: 0.8, blue: 1.0, alpha: 0.95)),
    ]

    /// The body (with tail) as a path, facing the way it swims.
    func path(time: Double, speed: CGFloat) -> CGPath {
        let facingLeft = velocity.dx < 0
        let wag = CGFloat(sin(time * Double(6 + speed * 0.6) + phase)) * (0.22 + min(speed, 20) * 0.012)
        let l = size, h = size * 0.48
        let body = CGMutablePath()
        // Body: a fat teardrop with the head at +x.
        body.move(to: CGPoint(x: l * 0.5, y: 0))
        body.addCurve(to: CGPoint(x: -l * 0.32, y: 0), control1: CGPoint(x: l * 0.42, y: -h * 0.95),
                      control2: CGPoint(x: -l * 0.18, y: -h * 0.7))
        body.addCurve(to: CGPoint(x: l * 0.5, y: 0), control1: CGPoint(x: -l * 0.18, y: h * 0.7),
                      control2: CGPoint(x: l * 0.42, y: h * 0.95))
        body.closeSubpath()
        // Tail: a forked fin that wags.
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: -l * 0.28, y: 0))
        tail.addLine(to: CGPoint(x: -l * 0.62, y: -h * 0.7))
        tail.addQuadCurve(to: CGPoint(x: -l * 0.62, y: h * 0.7), control: CGPoint(x: -l * 0.48, y: 0))
        tail.closeSubpath()
        let all = CGMutablePath()
        all.addPath(body)
        all.addPath(tail, transform: CGAffineTransform(translationX: -l * 0.28, y: 0).rotated(by: wag)
            .translatedBy(x: l * 0.28, y: 0))
        var t = CGAffineTransform(translationX: position.x, y: position.y)
        let tilt = max(min(velocity.dy / max(abs(velocity.dx), 1), 0.6), -0.6)
        t = t.rotated(by: (facingLeft ? -1 : 1) * tilt * 0.6)
        if facingLeft { t = t.scaledBy(x: -1, y: 1) }
        return all.copy(using: &t) ?? all
    }

    /// The eye: a dot, or a closed line when asleep.
    func eye(asleep: Bool) -> (point: CGPoint, radius: CGFloat) {
        let facingLeft = velocity.dx < 0
        let x = position.x + (facingLeft ? -1 : 1) * size * 0.27
        return (CGPoint(x: x, y: position.y - size * 0.07), asleep ? 0 : size * 0.075)
    }
}

/// Moves fish about inside the water.
struct FishTank {
    var fish: [Fish] = []
    private var lastTime: Double?

    mutating func sync(count: Int, geo: BottleGeometry, surface: CGFloat) {
        guard fish.count != count else { return }
        if fish.count > count { fish.removeLast(fish.count - count); return }
        while fish.count < count {
            let i = fish.count
            // Spread out through the water, the first one the biggest.
            let depth = max(geo.emptyY - surface, 20)
            let y = min(geo.emptyY - 12, surface + depth * (0.3 + 0.18 * CGFloat(i)))
            fish.append(Fish(position: CGPoint(x: 32 + CGFloat(i % 3) * 16, y: y),
                             target: CGPoint(x: 50, y: y), phase: Double(i) * 1.7,
                             size: 21 - CGFloat(i) * 1.5, hue: i % Fish.colors.count,
                             retarget: Double(i) * 0.7))
        }
    }

    /// Advances every fish. `surface` and `halfWidth` describe the water;
    /// `drink` sends them up to the surface as a drink is poured in.
    mutating func step(time: Double, geo: BottleGeometry, surfaceY: (CGFloat) -> CGFloat,
                       sleeping: Bool, sluggish: Bool, drink: Bool) {
        let dt = min(max(time - (lastTime ?? time), 0), 0.1)
        lastTime = time
        guard dt > 0 else { return }
        let floor = geo.emptyY - 5
        for i in fish.indices {
            var f = fish[i]
            let surface = surfaceY(f.position.x)
            let top = min(surface + f.size * 0.6, floor)
            if drink { f.drinkUntil = time + 2.2; f.retarget = 0 }
            f.retarget -= dt
            if f.retarget <= 0 {
                let half = max(geo.halfWidth(at: (top + floor) / 2) - f.size * 0.7, 4)
                if time < f.drinkUntil {
                    f.target = CGPoint(x: 50 + CGFloat.random(in: -8...8), y: top + 1)
                } else if sleeping {
                    f.target = CGPoint(x: 50 + CGFloat.random(in: -half...half) * 0.6, y: floor - f.size * 0.4)
                } else {
                    f.target = CGPoint(x: 50 + CGFloat.random(in: -half...half),
                                       y: CGFloat.random(in: top...max(top, floor - f.size * 0.5)))
                }
                f.retarget = sleeping ? 6 : Double.random(in: 2.5...5.5)
            }
            let maxSpeed: CGFloat = time < f.drinkUntil ? 26 : (sleeping ? 2 : (sluggish ? 5 : 11))
            let dx = f.target.x - f.position.x, dy = f.target.y - f.position.y
            let distance = max(hypot(dx, dy), 0.001)
            let desired = CGVector(dx: dx / distance * min(maxSpeed, distance * 1.4),
                                   dy: dy / distance * min(maxSpeed, distance * 1.4))
            let steer: CGFloat = 2.2 * CGFloat(dt)
            f.velocity.dx += (desired.dx - f.velocity.dx) * steer
            f.velocity.dy += (desired.dy - f.velocity.dy) * steer
            f.position.x += f.velocity.dx * CGFloat(dt)
            f.position.y += f.velocity.dy * CGFloat(dt)
            // Stay in the water and inside the glass.
            let surfaceHere = surfaceY(f.position.x)
            f.position.y = min(max(f.position.y, min(surfaceHere + f.size * 0.45, floor)), floor)
            let half = max(geo.halfWidth(at: f.position.y) - f.size * 0.55, 2)
            f.position.x = min(max(f.position.x, 50 - half), 50 + half)
            fish[i] = f
        }
    }
}
