import SceneKit
import UIKit
import simd

/// A metre-scale right-handed player. The root is at floor level between the feet.
/// The caller owns court translation. Animation is evaluated from the game clock.
final class Athlete {
    let node = SCNNode()
    private let body = SCNNode()
    private let chest = SCNNode()
    private let neck = SCNNode()
    private let hips = [SCNNode(), SCNNode()]
    private let knees = [SCNNode(), SCNNode()]
    private let feet = [SCNNode(), SCNNode()]
    private let shoulders = [SCNNode(), SCNNode()]
    private let elbows = [SCNNode(), SCNNode()]
    private let wrists = [SCNNode(), SCNNode()]
    private let opponent: Bool
    private var previousTime: TimeInterval?
    private var hitTime: TimeInterval?
    private var hitQueued = false
    private var contactTarget: SIMD3<Float>?
    private var overheadHit = false
    private var stride: Float = 0
    private var run: Float = 0

    private typealias Material = SCNMaterial
    private struct Ring {
        let y, width, depth, z: Float
        init(_ y: Float, _ width: Float, _ depth: Float, _ z: Float = 0) {
            self.y = y
            self.width = width
            self.depth = depth
            self.z = z
        }
    }

    private static func material(_ rgb: Int, roughness: CGFloat = 0.78, metal: CGFloat = 0) -> Material {
        let m = Material()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
                                     green: CGFloat((rgb >> 8) & 255) / 255,
                                     blue: CGFloat(rgb & 255) / 255, alpha: 1)
        m.roughness.contents = roughness
        m.metalness.contents = metal
        return m
    }

    private let ink = Athlete.material(0x17282B)
    private let hair = Athlete.material(0x252323)
    private let hairLight = Athlete.material(0x392F2C)
    private let white = Athlete.material(0xF5F0DF)
    private let teal = Athlete.material(0x116B66)
    private let orange = Athlete.material(0xFF633E)
    private let coral = Athlete.material(0xD74931)
    private let oxblood = Athlete.material(0x782F33)
    private let pants = Athlete.material(0x223436)
    private let sole = Athlete.material(0x36424A)
    private let shaft = Athlete.material(0x333D46, roughness: 0.33, metal: 0.52)
    private let string = Athlete.material(0xC7D6C8)
    private let skin: Material
    private let lip: Material

    init(isOpponent: Bool) {
        opponent = isOpponent
        skin = Athlete.material(isOpponent ? 0xB97750 : 0x965B43)
        lip = Athlete.material(isOpponent ? 0x91503B : 0x734235)
        node.name = isOpponent ? "Far athlete" : "Near athlete"
        node.eulerAngles.y = isOpponent ? .pi : 0
        node.addChildNode(body)
        attach(chest, to: body, x: 0, y: 0.94, z: 0)
        makeTorso()
        attach(neck, to: chest, x: 0, y: 0.505, z: -0.012)
        makeHead()
        for index in 0..<2 {
            makeLeg(index)
            makeArm(index)
        }
        if isOpponent { body.scale = SCNVector3(0.975, 0.985, 0.975) }
        animate(at: 0, speed: 0, delta: 0)
    }

    func swing(overhead: Bool, toward worldContact: SCNVector3? = nil) {
        contactTarget = worldContact.map {
            node.simdConvertPosition(SIMD3<Float>($0.x, $0.y, $0.z), from: nil)
        }
        overheadHit = overhead
        hitQueued = true
    }

    func update(time: TimeInterval, speed: Float) {
        if let previousTime, time < previousTime {
            hitTime = nil
            hitQueued = false
            contactTarget = nil
            overheadHit = false
            stride = 0
            run = 0
        }
        let dt = Float(min(0.05, max(0, time - (previousTime ?? time))))
        if hitQueued {
            hitTime = time
            hitQueued = false
        }
        previousTime = time
        animate(at: time, speed: speed, delta: dt)
    }

    private func animate(at time: TimeInterval, speed: Float, delta: Float) {
        let t = Float(time.truncatingRemainder(dividingBy: 120))
        let target = min(1, max(0, speed / 3.8))
        run += (target - run) * min(1, delta * 14)
        stride = (stride + delta * (7 + run * 6)).truncatingRemainder(dividingBy: 2 * .pi)
        let breath = sin(t * 2.7 + (opponent ? 1.6 : 0))
        let gait = sin(stride)
        let age = hitTime.map { Float(max(0, time - $0)) } ?? 10
        let end: Float = overheadHit ? 0.53 : 0.41
        let fraction = min(1, age / end)
        let fade = 1 - fraction * fraction * (3 - 2 * fraction)
        let follow = sin(min(1, age / 0.22) * .pi * 0.5)

        body.position = SCNVector3(gait * 0.027 * run,
                                   -0.015 + 0.009 * breath + 0.046 * abs(gait) * run
                                   + (overheadHit ? 0.067 : -0.045) * fade, 0)
        let torsoPitch = -0.105 - 0.10 * run - 0.04 * breath - 0.07 * fade
        let torsoYaw = gait * 0.095 * run + (0.24 - 0.70 * follow) * fade
        let torsoRoll = gait * 0.047 * run + (overheadHit ? 0.085 : -0.08) * fade
        chest.position = SCNVector3(0, 0.94, 0)
        rotate(chest, pitch: torsoPitch, yaw: torsoYaw, roll: torsoRoll)
        neck.eulerAngles = SCNVector3(0.08 + breath * 0.017, -torsoYaw * 0.72, -torsoRoll * 0.4)

        for i in 0..<2 {
            let side: Float = i == 0 ? -1 : 1
            let cycle = side * gait
            hips[i].eulerAngles = SCNVector3(0.14 + cycle * run * 0.57 + side * fade * 0.12,
                                              side * 0.06, side * (0.16 - 0.055 * run))
            knees[i].eulerAngles.x = -0.31 - run * (0.14 + max(0, cycle) * 0.60)
            feet[i].eulerAngles.x = -hips[i].eulerAngles.x - knees[i].eulerAngles.x + 0.12 * run * cycle
        }
        shoulders[0].eulerAngles = SCNVector3(0.25 + gait * 0.41 * run + fade * 0.55, 0.05, -0.24 - fade * 0.50)
        elbows[0].eulerAngles.x = 0.62 + 0.13 * run + fade * 0.18
        wrists[0].eulerAngles.z = 0.06

        let ready: Float = 0.40 - gait * 0.34 * run + breath * 0.025
        let arm: Float = overheadHit ? 2.44 - follow * 1.72 : -0.10 + follow * 1.32
        let elbow: Float = overheadHit ? 0.22 + follow * 0.50 : 0.29 + follow * 0.19
        let wrist: Float = overheadHit ? 1.12 + follow * 0.40 : 2.36 - follow * 0.47
        let armYaw: Float = overheadHit ? -0.19 : -0.67
        let armRoll: Float = overheadHit ? -0.56 : -0.18
        rotate(shoulders[1], pitch: ready + (arm - ready) * fade,
               yaw: -0.10 + fade * (armYaw + 0.10 - follow * 0.27),
               roll: 0.24 + fade * (armRoll - 0.24 + follow * 0.43))
        elbows[1].eulerAngles = SCNVector3(0.81 + fade * (elbow - 0.81), 0, 0)
        rotate(wrists[1], pitch: 1.71 + fade * (wrist - 1.71), yaw: 0,
               roll: -0.16 + (overheadHit ? 0.02 : -0.25) * fade)
        if let contactTarget, age < 0.23 {
            let influence = pow(max(0, 1 - age / 0.23), 2)
            reach(toward: contactTarget, influence: influence)
        }
    }

    /// Bounded cyclic coordinate descent brings the strings to the shuttle on off-centre hits.
    /// The legs stay planted while the torso shifts and the three right-arm joints adjust.
    private func reach(toward target: SIMD3<Float>, influence: Float) {
        let strings = SIMD3<Float>(-0.004, -0.536, -0.018)
        let wrist = wrists[1]
        let base = node.simdConvertPosition(strings, from: wrist)
        let offset = target - base
        chest.simdPosition += SIMD3<Float>(min(0.17, max(-0.17, offset.x * 0.30)),
                                           min(0.06, max(-0.12, offset.y * 0.20)),
                                           min(0.12, max(-0.12, offset.z * 0.24))) * influence
        let goal = base + offset * influence
        for _ in 0..<3 {
            for joint in [wrist, elbows[1], shoulders[1]] {
                let from = joint.simdConvertPosition(strings, from: wrist)
                let to = joint.simdConvertPosition(goal, from: node)
                let lengths = simd_length(from) * simd_length(to)
                guard lengths > 0.0001 else { continue }
                let axis = simd_cross(from, to)
                let size = simd_length(axis)
                guard size > 0.00005 else { continue }
                let angle = acos(min(1, max(-1, simd_dot(from, to) / lengths)))
                let correction = simd_quatf(angle: min(angle, 0.20 * influence), axis: axis / size)
                joint.simdOrientation = joint.simdOrientation * correction
            }
        }
    }

    // Use a fixed rotation order for the calibrated wrist-to-string-bed contact point.
    private func rotate(_ joint: SCNNode, pitch: Float, yaw: Float, roll: Float) {
        let x = simd_quatf(angle: pitch, axis: [1, 0, 0])
        let y = simd_quatf(angle: yaw, axis: [0, 1, 0])
        let z = simd_quatf(angle: roll, axis: [0, 0, 1])
        joint.simdOrientation = z * y * x
    }

    private func attach(_ child: SCNNode, to parent: SCNNode, x: Float, y: Float, z: Float) {
        child.position = SCNVector3(x, y, z)
        parent.addChildNode(child)
    }

    /// Smooth elliptical cross-sections allow separate profiles for the jaw, muscles and clothing.
    private func loft(_ rings: [Ring], _ materials: [Material], slices: Int = 24,
                      panel: ((Int, Float) -> Int)? = nil) -> SCNNode {
        var positions = [SCNVector3]()
        var normals = [SCNVector3]()
        var faces = Array(repeating: [Int32](), count: materials.count)
        for (j, r) in rings.enumerated() {
            let prev = rings[max(0, j - 1)]
            let next = rings[min(rings.count - 1, j + 1)]
            for i in 0..<slices {
                let angle = Float(i) / Float(slices) * 2 * .pi
                let x = cos(angle), z = sin(angle)
                positions.append(SCNVector3(x * r.width, r.y, z * r.depth + r.z))
                let tangent = SIMD3<Float>(-r.width * z, 0, r.depth * x)
                let vertical = SIMD3<Float>((next.width - prev.width) * x, next.y - prev.y,
                                           (next.depth - prev.depth) * z + next.z - prev.z)
                let n = simd_normalize(simd_cross(vertical, tangent))
                normals.append(SCNVector3(n.x, n.y, n.z))
                if j + 1 < rings.count {
                    let a = Int32(j * slices + i), b = Int32(j * slices + (i + 1) % slices)
                    let c = a + Int32(slices), d = b + Int32(slices)
                    let mat = panel?(j, angle + .pi / Float(slices)) ?? 0
                    faces[mat].append(contentsOf: [a, c, b, b, c, d])
                }
            }
        }
        for end in [0, rings.count - 1] {
            let ring = rings[end]
            let center = Int32(positions.count)
            let normal = SCNVector3(0, end == 0 ? -1 : 1, 0)
            positions.append(SCNVector3(0, ring.y, ring.z))
            normals.append(normal)
            for i in 0..<slices {
                positions.append(positions[end * slices + i])
                normals.append(normal)
            }
            for i in 0..<slices {
                let a = center + 1 + Int32(i), b = center + 1 + Int32((i + 1) % slices)
                faces[0].append(contentsOf: end == 0 ? [center, a, b] : [center, b, a])
            }
        }
        let elements = faces.map { SCNGeometryElement(indices: $0, primitiveType: .triangles) }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals)], elements: elements)
        geometry.materials = materials
        return SCNNode(geometry: geometry)
    }

    @discardableResult
    private func oval(_ parent: SCNNode, _ material: Material, _ x: Float, _ y: Float, _ z: Float,
                      _ rx: Float, _ ry: Float, _ rz: Float) -> SCNNode {
        let shape = SCNSphere(radius: 1)
        shape.segmentCount = 16
        shape.firstMaterial = material
        let n = SCNNode(geometry: shape)
        n.scale = SCNVector3(rx, ry, rz)
        attach(n, to: parent, x: x, y: y, z: z)
        return n
    }

    private func rod(_ parent: SCNNode, _ material: Material, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ radius: Float) {
        let d = b - a
        let length = simd_length(d)
        let geo = SCNCylinder(radius: CGFloat(radius), height: CGFloat(length))
        geo.radialSegmentCount = 7
        geo.firstMaterial = material
        let n = SCNNode(geometry: geo)
        n.simdPosition = (a + b) * 0.5
        n.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: d / length)
        parent.addChildNode(n)
    }

    /// Merge rigid pieces, keeping only the articulated joints live during gameplay.
    private func finish(_ rigid: SCNNode, on joint: SCNNode) {
        joint.addChildNode(rigid.flattenedClone())
    }

    private func makeTorso() {
        let g = SCNNode()
        let jersey = opponent ? coral : white
        let trim = opponent ? oxblood : teal
        let sleeve = opponent ? orange : ink
        let bodyRings: [Ring] = [Ring(0, 0.153, 0.103), Ring(0.024, 0.163, 0.109),
            Ring(0.12, 0.153, 0.107), Ring(0.25, 0.171, 0.115, -0.004),
            Ring(0.34, 0.198, 0.126, -0.009), Ring(0.408, 0.217, 0.117),
            Ring(0.461, 0.204, 0.093), Ring(0.493, 0.103, 0.069)]
        let top = loft(bodyRings, [jersey, trim, sleeve], slices: 36) { band, angle in
            let side = abs(cos(angle))
            if band > 4 && side > 0.64 { return 1 }
            if side > 0.93 && band > 0 { return 1 }
            if band == 0 && side > 0.76 { return 2 }
            return 0
        }
        g.addChildNode(top)
        let collar = loft([Ring(0.486, 0.103, 0.069), Ring(0.505, 0.091, 0.063)], [trim])
        g.addChildNode(collar)
        // Court crest on the chest and a two-stroke original team mark on the shoulder.
        oval(g, trim, 0.091, 0.349, -0.122, 0.023, 0.026, 0.003)
        rod(g, white, [0.083, 0.35, -0.127], [0.094, 0.36, -0.127], 0.0028)
        rod(g, sleeve, [-0.117, 0.356, -0.111], [-0.085, 0.368, -0.122], 0.0045)
        rod(g, trim, [-0.112, 0.345, -0.114], [-0.081, 0.357, -0.124], 0.003)
        // Sewn racing stripe and squad number on the player's back, visible from the chase camera.
        let mark = opponent ? white : teal
        let number: Float = opponent ? -0.032 : -0.036
        rod(g, mark, [number, 0.337, 0.118], [number + 0.05, 0.337, 0.118], 0.009)
        rod(g, mark, [number + 0.05, 0.337, 0.118], [number + 0.012, 0.253, 0.118], 0.009)
        for i in 0..<3 {
            let dx: Float = Float(i) * 0.017
            rod(g, opponent ? white : orange, [-0.055 + dx, 0.396, 0.114],
                [-0.042 + dx, 0.409, 0.115], 0.003)
        }
        finish(g, on: chest)

        let belt = SCNNode()
        belt.addChildNode(loft([Ring(0.83, 0.151, 0.098), Ring(0.89, 0.168, 0.111), Ring(0.959, 0.152, 0.103)], [pants]))
        belt.addChildNode(loft([Ring(0.933, 0.158, 0.107), Ring(0.958, 0.154, 0.106)], [ink]))
        finish(belt, on: body)
    }

    private func makeHead() {
        let g = SCNNode()
        g.addChildNode(loft([Ring(-0.01, 0.064, 0.059), Ring(0.068, 0.055, 0.058), Ring(0.13, 0.064, 0.063)], [skin]))
        let face = loft([Ring(0.065, 0.038, 0.044, -0.017), Ring(0.088, 0.064, 0.071, -0.013),
                         Ring(0.128, 0.077, 0.081, -0.006), Ring(0.174, 0.084, 0.086),
                         Ring(0.208, 0.082, 0.085, 0.005), Ring(0.248, 0.072, 0.071, 0.009),
                         Ring(0.269, 0.038, 0.038, 0.012)], [skin])
        g.addChildNode(face)
        for s: Float in [-1, 1] {
            oval(g, skin, s * 0.083, 0.153, 0.009, 0.015, 0.023, 0.013)
            oval(g, lip, s * 0.091, 0.154, 0.009, 0.004, 0.012, 0.007)
            oval(g, ink, s * 0.033, 0.164, -0.080, 0.012, 0.0046, 0.0038)
            rod(g, hair, [s * 0.017, 0.178, -0.084], [s * 0.054, 0.183, -0.07], 0.0037)
        }
        oval(g, skin, 0, 0.15, -0.083, 0.012, 0.022, 0.015)
        oval(g, skin, 0, 0.139, -0.092, 0.016, 0.010, 0.011)
        oval(g, lip, 0, 0.112, -0.087, 0.021, 0.004, 0.003)
        // Shaped hairline follows the nape and temple while leaving the face exposed.
        let cap = SCNNode()
        oval(cap, hair, 0, 0.207, 0.032, 0.088, 0.079, 0.073)
        oval(cap, hair, 0, 0.238, 0.001, 0.087, 0.060, 0.086)
        if opponent {
            oval(cap, hair, 0, 0.238, 0.096, 0.046, 0.044, 0.053)
            oval(cap, orange, 0, 0.237, 0.122, 0.039, 0.040, 0.020)
            let ponytail = oval(cap, hairLight, 0, 0.189, 0.154, 0.048, 0.091, 0.045)
            ponytail.eulerAngles.x = -0.47
            for i in 0..<5 {
                let x = Float(i - 2) * 0.018
                rod(cap, hairLight, [x, 0.253, -0.066], [x * 0.55, 0.276, 0.031], 0.004)
            }
        } else {
            for i in 0..<6 {
                let x = Float(i - 3) * 0.021
                let lock = oval(cap, i % 3 == 0 ? hairLight : hair, x, 0.264 - abs(x) * 0.18,
                                -0.038 + Float(i % 2) * 0.008, 0.023, 0.035, 0.053)
                lock.eulerAngles.z = -0.46
            }
            let band = loft([Ring(0.201, 0.088, 0.088, 0.006), Ring(0.215, 0.088, 0.089, 0.006)], [teal])
            cap.addChildNode(band)
        }
        g.addChildNode(cap)
        finish(g, on: neck)
    }

    private func makeLeg(_ i: Int) {
        let s: Float = i == 0 ? -1 : 1
        attach(hips[i], to: body, x: s * 0.094, y: 0.872, z: s * 0.018)
        attach(knees[i], to: hips[i], x: 0, y: -0.391, z: 0)
        attach(feet[i], to: knees[i], x: 0, y: -0.394, z: 0)
        let thigh = SCNNode()
        thigh.addChildNode(loft([Ring(-0.409, 0.050, 0.055), Ring(-0.325, 0.058, 0.061),
                                  Ring(-0.203, 0.077, 0.078), Ring(-0.102, 0.081, 0.083)], [skin]))
        let shorts = loft([Ring(-0.191, 0.092, 0.094), Ring(-0.165, 0.094, 0.096), Ring(0.012, 0.089, 0.100)],
                          [pants, opponent ? orange : teal], slices: 24) { _, a in s * cos(a) > 0.89 ? 1 : 0 }
        thigh.addChildNode(shorts)
        finish(thigh, on: hips[i])
        let shin = SCNNode()
        oval(shin, skin, 0, 0, -0.004, 0.052, 0.057, 0.054)
        shin.addChildNode(loft([Ring(-0.378, 0.035, 0.039), Ring(-0.282, 0.039, 0.043),
                               Ring(-0.155, 0.056, 0.063, 0.009), Ring(-0.079, 0.054, 0.061, 0.006),
                               Ring(-0.008, 0.049, 0.050)], [skin]))
        shin.addChildNode(loft([Ring(-0.403, 0.041, 0.046), Ring(-0.272, 0.045, 0.049), Ring(-0.237, 0.049, 0.052)],
                               [white]))
        for j in 0..<2 {
            let y = Float(j) * 0.013 - 0.266
            shin.addChildNode(loft([Ring(y, 0.048, 0.052), Ring(y + 0.006, 0.049, 0.053)], [teal]))
        }
        finish(shin, on: knees[i])

        let shoe = SCNNode()
        let rubber = opponent ? teal : orange
        shoe.addChildNode(loft([Ring(-0.074, 0.056, 0.131, -0.046), Ring(-0.062, 0.059, 0.137, -0.046),
                                Ring(-0.047, 0.058, 0.134, -0.046)], [rubber]))
        shoe.addChildNode(loft([Ring(-0.061, 0.058, 0.136, -0.046), Ring(-0.036, 0.060, 0.133, -0.047),
                                Ring(-0.017, 0.055, 0.122, -0.045), Ring(0.021, 0.046, 0.075, -0.013),
                                Ring(0.033, 0.043, 0.054, 0.003)], [white]))
        rod(shoe, sole, [s * 0.055, -0.035, -0.087], [s * 0.051, 0.001, -0.022], 0.0055)
        rod(shoe, rubber, [s * 0.057, -0.040, -0.055], [s * 0.052, -0.007, 0.009], 0.006)
        for j in 0..<3 {
            let z = -0.108 + Float(j) * 0.020
            let y = -0.009 + Float(j) * 0.009
            rod(shoe, string, [-0.021, y, z], [0.023, y + 0.004, z + 0.010], 0.003)
        }
        finish(shoe, on: feet[i])
    }

    private func makeArm(_ i: Int) {
        let s: Float = i == 0 ? -1 : 1
        attach(shoulders[i], to: chest, x: s * 0.196, y: 0.422, z: 0)
        attach(elbows[i], to: shoulders[i], x: 0, y: -0.276, z: 0)
        attach(wrists[i], to: elbows[i], x: 0, y: -0.238, z: 0)
        let upper = SCNNode()
        upper.addChildNode(loft([Ring(-0.281, 0.037, 0.040), Ring(-0.201, 0.045, 0.050),
                                Ring(-0.120, 0.052, 0.060), Ring(-0.043, 0.060, 0.064)], [skin]))
        let trim = opponent ? oxblood : teal
        upper.addChildNode(loft([Ring(-0.131, 0.062, 0.067), Ring(-0.119, 0.064, 0.069),
                                Ring(-0.042, 0.070, 0.075), Ring(0.018, 0.063, 0.071),
                                Ring(0.048, 0.035, 0.045)], [trim, opponent ? coral : white]) { j, _ in j == 0 ? 1 : 0 })
        finish(upper, on: shoulders[i])

        let forearm = SCNNode()
        oval(forearm, skin, 0, 0, 0, 0.038, 0.045, 0.041)
        forearm.addChildNode(loft([Ring(-0.247, 0.027, 0.030), Ring(-0.18, 0.029, 0.033),
                                  Ring(-0.091, 0.040, 0.044), Ring(-0.038, 0.042, 0.046), Ring(0, 0.036, 0.038)], [skin]))
        if i == 1 {
            forearm.addChildNode(loft([Ring(-0.225, 0.031, 0.034), Ring(-0.188, 0.033, 0.035)], [opponent ? white : orange]))
        }
        finish(forearm, on: elbows[i])
        let hand = SCNNode()
        oval(hand, skin, 0, -0.034, 0, 0.032, 0.051, 0.027)
        for j in 0..<4 {
            let x = Float(j) * 0.012 - 0.018
            oval(hand, skin, x, -0.063 - (j % 2 == 0 ? 0.002 : 0), -0.004, 0.009, i == 1 ? 0.016 : 0.024, 0.012)
        }
        oval(hand, skin, -s * 0.026, -0.039, -0.014, 0.015, 0.031, 0.016)
        if i == 1 { makeRacket(on: hand) }
        finish(hand, on: wrists[i])
    }

    private func makeRacket(on hand: SCNNode) {
        let racket = SCNNode()
        attach(racket, to: hand, x: -0.004, y: -0.043, z: -0.018)
        let grip = opponent ? oxblood : ink
        let rim = opponent ? teal : orange
        rod(racket, grip, [0, 0.044, 0], [0, -0.109, 0], 0.016)
        for j in 0..<8 {
            let y = 0.04 - Float(j) * 0.020
            rod(racket, sole, [0, y, 0], [0, y - 0.003, 0], 0.0168)
        }
        rod(racket, shaft, [0, -0.109, 0], [0, -0.353, 0], 0.0058)
        rod(racket, rim, [0, -0.111, 0], [0, -0.132, 0], 0.009)
        let cy: Float = -0.493, rx: Float = 0.099, ry: Float = 0.143
        // Elliptical tubular rim with a real open string bed.
        let tube = SCNTorus(ringRadius: CGFloat(rx), pipeRadius: 0.006)
        tube.ringSegmentCount = 42
        tube.pipeSegmentCount = 8
        tube.firstMaterial = rim
        let ring = SCNNode(geometry: tube)
        ring.eulerAngles.x = .pi / 2
        ring.scale = SCNVector3(1, 1, ry / rx)
        attach(ring, to: racket, x: 0, y: cy, z: 0)
        for i in -5...5 {
            let u = Float(i) / 6
            let half = sqrt(1 - u * u)
            rod(racket, string, [rx * u, cy - ry * half, 0], [rx * u, cy + ry * half, 0], 0.00105)
        }
        for j in -7...7 {
            let v = Float(j) / 8
            let half = sqrt(1 - v * v)
            rod(racket, string, [-rx * half, cy + ry * v, 0.0005], [rx * half, cy + ry * v, 0.0005], 0.00105)
        }
        racket.eulerAngles.y = -0.38
    }
}
