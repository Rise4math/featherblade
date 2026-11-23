import Foundation

/// Metres in court space. The net is z = 0, y is elevation, the near player uses +z.
struct ShuttleVector: Equatable {
    var x: Double
    var y: Double
    var z: Double

    static let zero = ShuttleVector(x: 0, y: 0, z: 0)
    var length: Double { sqrt(x * x + y * y + z * z) }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        Self(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    static func * (value: Self, scale: Double) -> Self {
        Self(x: value.x * scale, y: value.y * scale, z: value.z * scale)
    }
}

enum ShuttleShot: CaseIterable { case serve, clear, drop, drive, smash }
enum ShuttleContact: Equatable { case net, floor }

struct ShuttleFlight: Equatable {
    var position: ShuttleVector
    var velocity: ShuttleVector
    private(set) var contact: ShuttleContact?

    init(position: ShuttleVector, velocity: ShuttleVector) {
        self.position = position
        self.velocity = velocity
    }

    /// Advances to the first collision, including the contact position within a substep.
    @discardableResult
    mutating func advance(by seconds: Double) -> ShuttleContact? {
        guard contact == nil, seconds.isFinite, seconds > 0 else { return contact }
        var remaining = seconds
        while remaining > 0 {
            let dt = min(remaining, ShuttlePhysics.step)
            let start = position
            integrate(dt)
            var fraction = 1.0
            if position.y <= 0 {
                fraction = max(0, start.y / max(0.000001, start.y - position.y))
                contact = .floor
            }
            if start.z * position.z <= 0, start.z != position.z {
                let f = start.z / (start.z - position.z)
                let crossing = start + (position - start) * f
                if f <= fraction, abs(crossing.x) <= 3.05, crossing.y <= ShuttlePhysics.netHeight(at: crossing.x) {
                    fraction = f
                    contact = .net
                }
            }
            if contact != nil {
                position = start + (position - start) * fraction
                if contact == .floor { position.y = 0 }
                if contact == .net { position.z = 0 }
                velocity = .zero
                break
            }
            remaining -= dt
        }
        return contact
    }

    /// Explicit midpoint integration of coupled position and velocity.
    fileprivate mutating func integrate(_ dt: Double) {
        let midVelocity = velocity + ShuttlePhysics.acceleration(velocity) * (dt * 0.5)
        position = position + midVelocity * dt
        velocity = velocity + ShuttlePhysics.acceleration(midVelocity) * dt
    }
}

enum ShuttlePhysics {
    static let halfWidth = 2.59
    static let halfLength = 6.70
    static let shortServiceLine = 1.98
    fileprivate static let step = 1.0 / 180.0

    /// Effective feather drag divided by mass, in inverse metres. At terminal
    /// speed gravity balances drag at about 6.9 m/s. The same physical law
    /// drives clears, low serves and the rapid deceleration after a smash.
    private static let drag = 0.205
    fileprivate static func acceleration(_ velocity: ShuttleVector) -> ShuttleVector {
        var force = velocity * (-drag * velocity.length)
        force.y -= 9.81
        return force
    }

    static func netHeight(at x: Double) -> Double {
        let t = min(1, abs(x) / 3.05)
        return 1.524 + 0.026 * t * t
    }

    static func inSinglesCourt(_ p: ShuttleVector) -> Bool {
        abs(p.x) <= halfWidth && abs(p.z) <= halfLength
    }

    /// Solves for the launch vector that lands at the requested floor mark.
    /// Strike type sets a clearance preference. Legal reach and timing are
    /// handled by the match controller, so the target may also be out of bounds.
    static func launch(from start: ShuttleVector, toward target: ShuttleVector, shot: ShuttleShot) -> ShuttleFlight {
        let dx = target.x - start.x
        let dz = target.z - start.z
        let distance = max(0.001, hypot(dx, dz))
        let heading = ShuttleVector(x: dx / distance, y: 0, z: dz / distance)
        let crossed = start.z * target.z < 0
        let netFraction = crossed ? abs(start.z / dz) : 0.5
        let netDistance = distance * netFraction
        let netX = start.x + dx * netFraction
        let clearance: Double
        let baseSlope: Double
        let chord = -max(0, start.y) / distance
        switch shot {
        case .serve: (clearance, baseSlope) = (0.30, 0.24)
        case .clear: (clearance, baseSlope) = (1.4, max(0.85, 4.0 / distance))
        case .drop:  (clearance, baseSlope) = (0.22, chord + 0.12)
        case .drive: (clearance, baseSlope) = (0.17, chord + 0.09)
        case .smash: (clearance, baseSlope) = (0.065, chord + 0.022)
        }

        // The net clearance changes smoothly with launch slope for fixed range.
        // Fit the speed at each slope and raise it only when the net blocks the path.
        let desiredHeight = netHeight(at: netX) + clearance
        var slope = baseSlope
        var launch = ShuttleFlight(position: start, velocity: .zero)
        for _ in 0..<5 {
            launch = fitRange(from: start, heading: heading, slope: slope, distance: distance)
            guard crossed else { break }
            let crossing = height(at: netDistance, from: launch, heading: heading)
            let deficit = desiredHeight - crossing
            if deficit <= 0.008 { break }
            let sensitivity = max(0.16, netDistance * (1 - pow(netFraction, 2)))
            slope += min(3.0, deficit / sensitivity)
        }
        return launch
    }

    private static func fitRange(from start: ShuttleVector, heading: ShuttleVector, slope: Double, distance: Double) -> ShuttleFlight {
        // Limit total launch speed. Extremely low contacts or unrealistic
        // targets can then naturally produce a short return or a net fault.
        var low = 0.15
        var high = 100 / sqrt(1 + slope * slope)
        for _ in 0..<14 {
            let horizontal = (low + high) * 0.5
            var velocity = heading * horizontal
            velocity.y = horizontal * slope
            let trial = ShuttleFlight(position: start, velocity: velocity)
            if height(at: distance, from: trial, heading: heading) > 0 {
                high = horizontal
            } else {
                low = horizontal
            }
        }
        let speed = (low + high) * 0.5
        var velocity = heading * speed
        velocity.y = speed * slope
        return ShuttleFlight(position: start, velocity: velocity)
    }

    /// Height at a plane perpendicular to the horizontal shot direction.
    /// Early floor-out suffices to bracket the solution in fitRange.
    private static func height(at distance: Double, from initial: ShuttleFlight, heading: ShuttleVector) -> Double {
        var flight = initial
        var previousDistance = 0.0
        for _ in 0..<1080 {
            let previousY = flight.position.y
            flight.integrate(step)
            let offset = flight.position - initial.position
            let travelled = offset.x * heading.x + offset.z * heading.z
            if travelled >= distance {
                let f = (distance - previousDistance) / max(0.000001, travelled - previousDistance)
                return previousY + f * (flight.position.y - previousY)
            }
            if flight.position.y <= 0 { return -0.001 }
            previousDistance = travelled
        }
        return -0.001
    }

    static func landing(of initial: ShuttleFlight) -> ShuttleVector? {
        var flight = initial
        return flight.advance(by: 8) == .floor ? flight.position : nil
    }

    /// Finds a descending racket-height contact on the requested court half.
    /// A low drive already below that height can be intercepted as it arrives.
    static func intercept(of initial: ShuttleFlight, side: Double, height: Double) -> ShuttleVector? {
        let sign = side < 0 ? -1.0 : 1.0
        var flight = initial
        for _ in 0..<480 {
            let start = flight.position
            let event = flight.advance(by: 1.0 / 90)
            if event == .net { return nil }
            let end = flight.position
            if end.z * sign >= 0.40, end.y < height, end.y <= start.y {
                var f = start.y > height ? (start.y - height) / (start.y - end.y) : 0
                if start.z * sign < 0.40, end.z != start.z {
                    f = max(f, (0.40 * sign - start.z) / (end.z - start.z))
                }
                let point = start + (end - start) * f
                return point.y > 0.15 ? point : nil
            }
            if event != nil { return nil }
        }
        return nil
    }
}
