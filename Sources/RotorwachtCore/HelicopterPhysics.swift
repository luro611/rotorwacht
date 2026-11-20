import Foundation

/// Fixed numbers of the rescue helicopter. Tuned by feel; tests only rely on their relations.
public struct HelicopterSpec: Sendable {
    public var halfWidth = 42.0
    public var maxHorizontalSpeed = 280.0
    public var horizontalAcceleration = 260.0
    public var drag = 0.5
    public var climbSpeed = 120.0
    public var descendSpeed = 140.0
    /// How quickly vertical speed follows the target (1/s).
    public var verticalResponse = 2.6
    public var maxTilt = 0.42
    /// Soft landing limits.
    public var safeVerticalSpeed = 75.0
    public var safeHorizontalSpeed = 80.0
    public var safeTilt = 0.25
    /// Above this vertical speed a touchdown destroys the helicopter.
    public var crashVerticalSpeed = 320.0
    /// Falling speed without fuel (autorotation).
    public var glideFallSpeed = 150.0
    /// Durability lost per second while floating in water.
    public var waterDamagePerSecond = 14.0
    public var maxDurability = 100.0

    public init() {}
    public static let standard = HelicopterSpec()
}

public struct PilotInput: Equatable, Sendable {
    public var left = false, right = false, up = false, down = false
    /// Release the extinguishing water.
    public var drop = false
    /// Analog stick values (-1...1), only set by a gamepad. nil = keyboard: the four flags decide.
    public var axisX: Double? = nil, axisY: Double? = nil
    public init(left: Bool = false, right: Bool = false, up: Bool = false, down: Bool = false, drop: Bool = false) {
        self.left = left; self.right = right; self.up = up; self.down = down; self.drop = drop
    }
    /// -1...1: -1, 0 or 1 on the keyboard, any value in between on a gamepad stick.
    public var horizontal: Double { axisX ?? ((right ? 1 : 0) - (left ? 1 : 0)) }
    /// Vertical demand -1...1 (positive = climb).
    public var vertical: Double { axisY ?? ((up ? 1 : 0) - (down ? 1 : 0)) }
}

public struct HelicopterState: Equatable, Sendable {
    /// Centre x and the height of the skids above the world's zero line.
    public var x: Double
    public var y: Double
    public var vx = 0.0
    public var vy = 0.0
    /// Signed in world direction: positive means nose down towards the right.
    public var tilt = 0.0
    /// -1 faces left, +1 faces right, 0 faces the viewer. Changes continuously while turning.
    public var facing = 1.0
    public var fuel: Double
    public var durability: Double
    /// Extinguishing water in the tank.
    public var water = 0.0
    public var onGround = true
    public var inWater = false
    /// Last non-zero horizontal direction the pilot asked for.
    public var heading = 1.0

    public init(x: Double, y: Double, fuel: Double, durability: Double = 100) {
        self.x = x; self.y = y; self.fuel = fuel; self.durability = durability
    }

    public var speed: Double { (vx * vx + vy * vy).squareRoot() }
}

public enum PhysicsEvent: Equatable, Sendable {
    /// Touched down; `damage` is 0 for a soft landing.
    case touchdown(verticalSpeed: Double, damage: Double)
    case collision(damage: Double)
    case splash(speed: Double)
    case liftoff
    case outOfFuel
}

public enum HelicopterPhysics {
    /// Advances the helicopter by `dt` seconds.
    /// - Parameters:
    ///   - wind: horizontal wind acceleration
    ///   - waterLevel: current flood level
    @discardableResult
    public static func step(
        _ s: inout HelicopterState,
        input: PilotInput,
        dt: Double,
        wind: Double,
        waterLevel: Double,
        mission: Mission,
        fuelBurnPerSecond: Double,
        spec: HelicopterSpec = .standard
    ) -> [PhysicsEvent] {
        var events: [PhysicsEvent] = []
        let hadFuel = s.fuel > 0
        let dir = input.horizontal
        if dir != 0 { s.heading = dir }

        // Fuel
        let burn = s.onGround
            ? fuelBurnPerSecond * 0.25
            : fuelBurnPerSecond * (1.0 + (input.up ? 0.35 : 0) + (dir != 0 ? 0.15 : 0))
        s.fuel = max(0, s.fuel - burn * dt)
        let engine = s.fuel > 0
        if hadFuel && !engine { events.append(.outOfFuel) }

        // Lift-off from the ground
        if s.onGround {
            s.vx = 0
            s.vy = 0
            if input.up && engine {
                s.onGround = false
                s.vy = 20
                events.append(.liftoff)
            }
        }

        if !s.onGround {
            // Horizontal: acceleration, drag, wind. Without engine the pilot has no authority.
            let accel = engine ? dir * spec.horizontalAcceleration : 0
            s.vx += (accel + wind - s.vx * spec.drag) * dt
            s.vx = min(max(s.vx, -spec.maxHorizontalSpeed * 1.15), spec.maxHorizontalSpeed * 1.15)

            // Vertical: speed follows a target set by the pilot.
            var target = 0.0
            var response = spec.verticalResponse
            if engine {
                let v = input.vertical
                if v > 0 { target = spec.climbSpeed * v } else if v < 0 { target = spec.descendSpeed * v }
            } else {
                target = -spec.glideFallSpeed
                response = 0.8
            }
            s.vy += (target - s.vy) * min(1, response * dt)
        }

        // Vertical movement and contact with the floor (terrain, roof or water).
        let halfW = spec.halfWidth
        let preY = s.y
        let preVy = s.vy
        if !s.onGround { s.y += s.vy * dt }
        if s.y > mission.world.ceiling { s.y = mission.world.ceiling; s.vy = min(0, s.vy) }

        let surface = mission.maxSurface(from: s.x - halfW, to: s.x + halfW)
        let wet = waterLevel > surface
        let floor = max(surface, waterLevel)
        s.inWater = false

        if s.y <= floor {
            let impact = max(0, -preVy)
            if preY > floor + 0.01 || !s.onGround {
                if wet {
                    // Ditching in the flood: soft floor, but wet.
                    s.inWater = true
                    if impact > 150 {
                        let d = (impact - 150) * 0.3
                        s.durability -= d
                        events.append(.collision(damage: d))
                    }
                    if impact > 30 { events.append(.splash(speed: impact)) }
                    s.y = floor
                    s.vy = 0
                    s.vx *= 0.5
                    s.onGround = true
                    s.tilt = 0
                } else {
                    let tiltExcess = max(0, abs(s.tilt) - spec.safeTilt)
                    let vExcess = max(0, impact - spec.safeVerticalSpeed)
                    let hExcess = max(0, abs(s.vx) - spec.safeHorizontalSpeed)
                    var damage = vExcess * 0.3 + hExcess * 0.15 + tiltExcess * 60
                    if impact > spec.crashVerticalSpeed { damage = s.durability + 1 }
                    if !s.onGround {
                        s.durability -= damage
                        events.append(.touchdown(verticalSpeed: impact, damage: damage))
                    }
                    s.y = floor
                    s.vy = 0
                    s.vx = damage > 0 ? s.vx * 0.3 : 0
                    s.onGround = true
                }
            } else {
                s.y = floor
                s.vy = 0
                s.inWater = wet
            }
        } else if s.onGround && s.y > floor + 0.01 {
            // Ground fell away (should not happen) – drop.
            s.onGround = false
        }

        if s.onGround && wet { s.inWater = true }
        if s.inWater {
            s.durability -= spec.waterDamagePerSecond * dt
        }

        // Horizontal movement and wall contact.
        if !s.onGround {
            let oldX = s.x
            s.x += s.vx * dt
            let ahead = mission.maxSurface(from: s.x - halfW, to: s.x + halfW)
            if ahead > s.y + 0.5 && mission.maxSurface(from: oldX - halfW, to: oldX + halfW) <= s.y + 0.5 {
                // Hit a wall or a rooftop edge: bounce back, hurt a little when fast.
                let damage = max(0, abs(s.vx) - 50) * 0.2
                s.x = oldX
                s.vx = -s.vx * 0.25
                s.durability -= damage
                events.append(.collision(damage: damage))
            }
        }
        // Edges of the mission area.
        let minX = halfW + 10, maxX = mission.world.width - halfW - 10
        if s.x < minX { s.x = minX; s.vx = max(0, s.vx) }
        if s.x > maxX { s.x = maxX; s.vx = min(0, s.vx) }

        // Tilt follows speed and pilot input.
        let tiltTarget: Double = s.onGround
            ? 0
            : min(max(s.vx / spec.maxHorizontalSpeed * spec.maxTilt + dir * 0.10, -spec.maxTilt), spec.maxTilt)
        s.tilt += (tiltTarget - s.tilt) * min(1, 5 * dt)

        // Facing: turns towards the pilot's direction, faces the viewer when standing still.
        let facingTarget: Double
        if dir != 0 { facingTarget = dir }
        else if abs(s.vx) < 18 { facingTarget = 0 }
        else { facingTarget = s.vx > 0 ? 1 : -1 }
        let turn = 3.2 * dt
        if abs(facingTarget - s.facing) <= turn { s.facing = facingTarget }
        else { s.facing += (facingTarget > s.facing ? 1 : -1) * turn }

        s.durability = max(0, s.durability)
        return events
    }
}
