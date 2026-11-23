import SceneKit
import simd
import UIKit

/// A main-thread singles match. The view drives the clock so suspension and pause never fast-forward a rally.
final class MatchScene {
    enum Stroke: Equatable { case clear, drop, smash }
    enum Phase: Equatable { case ready, rally, point, finished }
    enum Event { case strike(player: Bool, shot: Stroke), serve(player: Bool), point(player: Bool), fault }

    struct Status: Equatable {
        let phase: Phase
        let playerScore: Int
        let opponentScore: Int
        let rally: Int
        let playerServing: Bool
        let message: String
        let playerWon: Bool?
        let canHit: Bool
    }

    let scene: SCNScene
    let camera: SCNNode
    let targetScore: Int
    let scoreCap: Int
    var onUpdate: ((Status) -> Void)?
    var onEvent: ((Event) -> Void)?
    var status: Status {
        Status(phase: phase, playerScore: scores[0], opponentScore: scores[1], rally: contacts,
               playerServing: server == .near, message: caption,
               playerWon: winner.map { $0 == .near }, canHit: phase == .rally && hitter == .far && withinReach(.near))
    }

    private enum Side: Int {
        case near, far
        var sign: Double { self == .near ? 1 : -1 }
        var other: Side { self == .near ? .far : .near }
    }

    private let arena: Arena
    private let near = Athlete(isOpponent: false)
    private let far = Athlete(isOpponent: true)
    private var scores = [0, 0]
    private var server = Side.near
    private var hitter = Side.near
    private var phase = Phase.ready
    private var winner: Side?
    private var caption = "我方发球"
    private var contacts = 0
    private var flight: ShuttleFlight?
    private var receiveAt: ShuttleVector?
    private var projectedLanding: ShuttleVector?
    private var pending: (shot: Stroke, aim: Float, until: Double)?
    private var movement = SIMD2<Float>.zero
    private var paused = false
    private var clock = 0.0
    private var phaseAge = 0.0
    private var ageSinceHit = 0.0
    private var reactionDelay = 0.0
    private var cpuHitHeight = 1.8
    private var manualUntil = 0.0
    private var lastSent: Status?
    private var trail: [SCNNode] = []
    private var trailClock = 0.0
    private var rng: UInt64

    init(targetScore: Int = 11, scoreCap: Int = 15, seed: UInt64 = .random(in: 1 ... UInt64.max)) {
        self.targetScore = max(1, targetScore)
        self.scoreCap = max(self.targetScore, scoreCap)
        rng = seed
        let scene = SCNScene()
        self.scene = scene
        let arena = Arena(scene: scene)
        self.arena = arena
        camera = arena.cameraNode
        scene.rootNode.addChildNode(near.node)
        scene.rootNode.addChildNode(far.node)
        buildTrail()
        ready()
    }

    func resize(aspect: Float) { arena.updateCamera(aspect: max(0.1, aspect)) }

    func start() {
        scores = [0, 0]
        winner = nil
        server = .near
        paused = false
        clock = 0
        lastSent = nil
        ready()
        publish()
    }

    func setPaused(_ paused: Bool) {
        self.paused = paused
        if paused {
            movement = .zero
            pending = nil
        }
    }

    func serve() {
        guard !paused else { return }
        if phase == .point { ready() }
        guard phase == .ready else { return }
        let origin = heldShuttle()
        let target = ShuttleVector(x: -serviceX(for: server), y: 0, z: -server.sign * 4.25)
        athlete(server).swing(overhead: false, toward: scenePoint(origin))
        phase = .rally
        phaseAge = 0
        contacts = 1
        launch(from: origin, toward: target, by: server, shot: .serve)
        onEvent?(.serve(player: server == .near))
        publish()
    }

    /// A tap may arrive just before the shuttle. Keep one short-lived intent, replaced by the latest choice.
    func strike(_ shot: Stroke, aim: Float = 0) {
        guard !paused else { return }
        if phase == .ready { serve(); return }
        guard phase == .rally, hitter == .far else { return }
        pending = (shot, min(1, max(-1, aim)), clock + 0.62)
        tryPlayerReturn()
        publish()
    }

    /// Continuous court-relative input. Positive depth moves toward the net.
    func setMovement(_ lateral: Float, depth: Float) {
        movement = SIMD2(min(1, max(-1, lateral)), min(1, max(-1, depth)))
        if movement != .zero { manualUntil = clock + 0.15 }
    }

    /// A discrete drag/nudge, expressed in court metres. Continuous controls should use setMovement.
    func move(_ lateral: Float, depth: Float) {
        guard !paused, phase == .rally else { return }
        var p = near.node.position
        p.x += lateral
        p.z -= depth
        bound(&p, to: .near)
        near.node.position = p
        manualUntil = clock + 0.28
    }

    func tick(_ dt: TimeInterval) {
        guard !paused, dt.isFinite, dt > 0 else { return }
        var remaining = min(dt, 0.075)
        // Substeps keep contact windows and running speeds stable at both 30 and 120 fps.
        while remaining > 0.000_001 {
            let step = min(remaining, 1.0 / 120)
            clock += step
            phaseAge += step
            advance(step)
            remaining -= step
        }
        publish()
    }

    private func ready() {
        phase = .ready
        phaseAge = 0
        manualUntil = 0
        pending = nil
        flight = nil
        movement = .zero
        contacts = 0
        caption = server == .near ? "我方发球" : "对手发球"
        let x = serviceX(for: server)
        for side in [Side.near, .far] {
            let sign = side.sign
            let serving = side == server
            let contactX = serving ? x : -x
            athlete(side).node.position = SCNVector3(Float(contactX - 0.44 * sign), 0,
                                                     Float((serving ? 3.35 : 4.05) * sign))
        }
        clearTrail()
        arena.presentLanding(at: nil)
        drawShuttle(at: heldShuttle(), velocity: nil)
    }

    private func serviceX(for side: Side) -> Double {
        (scores[side.rawValue].isMultiple(of: 2) ? 1 : -1) * 1.05 * side.sign
    }

    private func heldShuttle() -> ShuttleVector {
        let p = athlete(server).node.position
        return ShuttleVector(x: Double(p.x) + 0.44 * server.sign, y: 1.08,
                             z: Double(p.z) - 0.30 * server.sign)
    }

    private func advance(_ dt: Double) {
        switch phase {
        case .ready:
            animateIdle()
            if server == .far, phaseAge >= 1.15 { serve() }
        case .rally:
            guard var airborne = flight else { return }
            ageSinceHit += dt
            let contact = airborne.advance(by: dt)
            flight = airborne
            drawShuttle(at: airborne.position, velocity: airborne.velocity)
            sampleTrail(dt)
            if let contact {
                switch contact {
                case .net:
                    onEvent?(.fault)
                    award(hitter.other, reason: hitter == .near ? "我方下网" : "对手下网")
                case .floor:
                    adjudicateLanding(airborne.position)
                }
                return
            }
            moveAthlete(.near, dt: dt)
            moveAthlete(.far, dt: dt)
            if hitter == .near {
                if ageSinceHit >= reactionDelay, Double(airborne.position.y) <= cpuHitHeight, withinReach(.far), shouldPlay {
                    computerReturn()
                }
            } else {
                tryPlayerReturn()
                if hitter == .far { caption = withinReach(.near) ? "击球时机" : "准备接球" }
            }
        case .point:
            animateIdle()
            if phaseAge >= 1.85 { ready() }
        case .finished:
            animateIdle()
        }
    }

    private func animateIdle() {
        near.update(time: clock, speed: 0)
        far.update(time: clock, speed: 0)
    }

    private func launch(from origin: ShuttleVector, toward target: ShuttleVector, by side: Side, shot: ShuttleShot) {
        hitter = side
        ageSinceHit = 0
        pending = nil
        let incoming = ShuttlePhysics.launch(from: origin, toward: target, shot: shot)
        flight = incoming
        projectedLanding = ShuttlePhysics.landing(of: incoming)
        let recipient = side.other
        cpuHitHeight = 1.55 + random() * 0.65
        reactionDelay = side == .near ? 0.11 + 0.12 * random() : 0.035
        receiveAt = planFootwork(for: recipient, incoming: incoming) ?? projectedLanding
        caption = side == .near ? "对手接球" : "准备接球"
        arena.presentLanding(at: recipient == .near ? projectedLanding.map(scenePoint) : nil)
        clearTrail()
        drawShuttle(at: origin, velocity: incoming.velocity)
    }

    /// Compare reachable contacts along the flight. A flat shot may offer a later
    /// interception in midcourt even when the player cannot reach the tape in time.
    private func planFootwork(for side: Side, incoming: ShuttleFlight) -> ShuttleVector? {
        let start = athlete(side).node.position
        let speed = side == .near ? 5.5 : 4.9
        let desiredHeight = side == .near ? 1.80 : cpuHitHeight
        let step = 1.0 / 48.0
        var trajectory = incoming
        var best: ShuttleVector?
        var cost = Double.infinity
        for frame in 1...220 {
            if trajectory.advance(by: step) != nil { break }
            let p = trajectory.position
            guard p.z * side.sign >= 0.25, (0.32...2.50).contains(p.y) else { continue }
            let dx = p.x - 0.44 * side.sign - Double(start.x)
            let dz = p.z + 0.30 * side.sign - Double(start.z)
            let distance = hypot(dx, dz)
            let available = max(0, Double(frame) * step - reactionDelay) * speed
            let shortfall = max(0, distance - available - 0.50)
            let value = 5.0 * shortfall + abs(p.y - desiredHeight) + 0.24 * distance
            if value < cost { best = p; cost = value }
        }
        return best
    }

    private func moveAthlete(_ side: Side, dt: Double) {
        let character = athlete(side)
        let current = character.node.position
        var target = current
        var maxSpeed: Float = side == .near ? 5.5 : 4.9
        if side == .near, movement != .zero {
            let length = max(1, sqrt(movement.x * movement.x + movement.y * movement.y))
            target.x += movement.x / length
            target.z -= movement.y / length
            manualUntil = clock + 0.15
        } else if side == .near, clock < manualUntil {
            // A brief manual correction takes precedence over assisted footwork.
        } else if side != hitter, ageSinceHit >= reactionDelay, let receiveAt, side == .near || shouldPlay {
            target.x = Float(receiveAt.x - 0.44 * side.sign)
            target.z = Float(receiveAt.z + 0.30 * side.sign)
        } else if side == hitter, ageSinceHit >= 0.20 {
            target = SCNVector3(Float(-0.2 * side.sign), 0, Float(3.55 * side.sign))
            maxSpeed = 2.55
        }
        bound(&target, to: side)
        let dx = target.x - current.x, dz = target.z - current.z
        let distance = sqrt(dx * dx + dz * dz)
        let travelled = min(maxSpeed * Float(dt), distance)
        if distance > 0.0001 {
            character.node.position = SCNVector3(current.x + dx / distance * travelled, 0,
                                                  current.z + dz / distance * travelled)
        }
        character.update(time: clock, speed: travelled / Float(dt))
    }

    private func bound(_ point: inout SCNVector3, to side: Side) {
        point.x = min(3.06, max(-3.06, point.x))
        point.z = Float(side.sign * min(7.05, max(0.36, Double(point.z) * side.sign)))
    }

    private func withinReach(_ side: Side) -> Bool {
        guard let flight, hitter != side else { return false }
        let p = flight.position
        guard side.sign * p.z > 0.09, p.y >= 0.27, p.y <= 2.62 else { return false }
        let actor = athlete(side).node.position
        let dx = p.x - Double(actor.x) - 0.44 * side.sign
        let dz = p.z - Double(actor.z) + 0.30 * side.sign
        let reach = side == .near ? 1.16 : 0.92
        return dx * dx + dz * dz <= reach * reach
    }

    private var shouldPlay: Bool {
        guard let p = projectedLanding else { return false }
        // Line judgment includes a marginal-uncertainty zone around the boundary.
        return abs(p.x) < 2.74 && abs(p.z) < 6.88 && p.z * hitter.other.sign > -0.1
    }

    private func tryPlayerReturn() {
        guard let intent = pending else { return }
        if clock > intent.until { pending = nil; return }
        guard withinReach(.near), let p = flight?.position else { return }
        let stroke: Stroke = intent.shot == .smash && p.y < 1.45 ? .clear : intent.shot
        let depth: Double
        switch stroke {
        case .clear: depth = 5.45 + 0.60 * random()
        case .drop: depth = 1.15 + 0.65 * random()
        case .smash: depth = 3.85 + 0.75 * random()
        }
        let target = ShuttleVector(x: 2.22 * Double(intent.aim), y: 0, z: -depth)
        play(stroke, by: .near, from: p, toward: target)
    }

    private func computerReturn() {
        guard let p = flight?.position else { return }
        let opponent = near.node.position
        let choice = random()
        let attacking = p.y > 1.85 && p.z > -4.8
        let stroke: Stroke
        if attacking, choice < 0.36 { stroke = .smash }
        else if (opponent.z > 4.25 && choice < 0.78) || choice < 0.23 { stroke = .drop }
        else { stroke = .clear }
        let side: Double = abs(opponent.x) > 0.42 ? (opponent.x > 0 ? -1 : 1) : (random() < 0.5 ? 1 : -1)
        let pressure = min(1.0, max(0.0, (1.4 - p.y) / 0.95))
        let spread = 0.25 + 0.75 * pressure
        let width = side * (1.15 + 0.95 * random()) + (2 * random() - 1) * spread
        let depth: Double
        switch stroke {
        case .drop: depth = 1.1 + 0.85 * random()
        case .smash: depth = 3.6 + 1.4 * random()
        case .clear: depth = 5.3 + (1.05 + pressure * 0.80) * random()
        }
        play(stroke, by: .far, from: p, toward: ShuttleVector(x: width, y: 0, z: depth))
    }

    private func play(_ stroke: Stroke, by side: Side, from: ShuttleVector, toward: ShuttleVector) {
        let shot: ShuttleShot
        switch stroke { case .clear: shot = .clear; case .drop: shot = .drop; case .smash: shot = .smash }
        athlete(side).swing(overhead: from.y >= 1.56, toward: scenePoint(from))
        contacts += 1
        launch(from: from, toward: toward, by: side, shot: shot)
        onEvent?(.strike(player: side == .near, shot: stroke))
    }

    private func adjudicateLanding(_ p: ShuttleVector) {
        let inCourt = ShuttlePhysics.inSinglesCourt(p) && p.z * hitter.other.sign > 0
        if !inCourt {
            onEvent?(.fault)
            award(hitter.other, reason: hitter == .near ? "我方回球出界" : "对手回球出界")
        } else if contacts == 1 && (abs(p.z) < ShuttlePhysics.shortServiceLine || p.x * serviceX(for: server) > 0) {
            onEvent?(.fault)
            award(server.other, reason: "发球落点违例")
        } else {
            award(hitter, reason: hitter == .near ? "我方得分" : "对手得分")
        }
    }

    private func award(_ side: Side, reason: String) {
        scores[side.rawValue] += 1
        server = side
        phaseAge = 0
        flight = nil
        receiveAt = nil
        projectedLanding = nil
        pending = nil
        movement = .zero
        arena.presentLanding(at: nil)
        clearTrail()
        let own = scores[side.rawValue], other = scores[side.other.rawValue]
        if own >= targetScore && (own - other >= 2 || own >= scoreCap) {
            winner = side
            phase = .finished
            caption = side == .near ? "我方获胜" : "对手获胜"
        } else {
            phase = .point
            caption = reason
        }
        onEvent?(.point(player: side == .near))
    }

    private func athlete(_ side: Side) -> Athlete { side == .near ? near : far }
    private func scenePoint(_ p: ShuttleVector) -> SCNVector3 { SCNVector3(Float(p.x), Float(p.y), Float(p.z)) }

    private func drawShuttle(at p: ShuttleVector, velocity v: ShuttleVector?) {
        arena.shuttleNode.position = scenePoint(p)
        arena.shadowNode.position = SCNVector3(Float(p.x), 0.016, Float(p.z))
        let scale = Float(1 + min(0.63, 0.09 * max(0, p.y)))
        arena.shadowNode.scale = SCNVector3(scale, 1, scale)
        arena.shadowNode.opacity = CGFloat(max(0.25, 0.77 - 0.08 * p.y))
        if let v {
            let direction = SIMD3<Float>(Float(v.x), Float(v.y), Float(v.z))
            if simd_length_squared(direction) > 0.0001 {
                arena.shuttleNode.simdOrientation = simd_quatf(from: SIMD3(0,-1,0), to: simd_normalize(direction))
            }
        } else { arena.shuttleNode.eulerAngles = SCNVector3Zero }
    }

    private func buildTrail() {
        for i in 0 ..< 7 {
            let bead = SCNSphere(radius: CGFloat(0.041 - Double(i) * 0.0044))
            bead.segmentCount = 6
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = UIColor(red: 0.82, green: 1, blue: 0.60, alpha: 1)
            material.writesToDepthBuffer = false
            bead.materials = [material]
            let node = SCNNode(geometry: bead)
            node.opacity = CGFloat(0.82 - Double(i) * 0.10)
            node.isHidden = true
            scene.rootNode.addChildNode(node)
            trail.append(node)
        }
    }

    private func clearTrail() {
        trailClock = 0
        for node in trail { node.isHidden = true }
    }

    private func sampleTrail(_ dt: Double) {
        trailClock += dt
        guard trailClock >= 0.019, let first = trail.first else { return }
        trailClock.formTruncatingRemainder(dividingBy: 0.019)
        for i in (1 ..< trail.count).reversed() {
            trail[i].position = trail[i - 1].position
            trail[i].isHidden = trail[i - 1].isHidden
        }
        first.position = arena.shuttleNode.position
        first.isHidden = false
    }

    private func random() -> Double {
        rng = rng &* 6364136223846793005 &+ 1442695040888963407
        return Double(rng >> 11) / 9_007_199_254_740_992
    }

    private func publish() {
        let next = status
        guard next != lastSent else { return }
        lastSent = next
        onUpdate?(next)
    }
}
