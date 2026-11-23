// From the project root, compile this executable with BadmintonPhysics.swift:
// swiftc Shuttle/BadmintonPhysics.swift Tests/Physics/main.swift -o /tmp/shuttle-physics
// /tmp/shuttle-physics
import Foundation

func groundDistance(_ a: ShuttleVector, _ b: ShuttleVector) -> Double {
    hypot(a.x - b.x, a.z - b.z)
}

func floorContact(_ launch: ShuttleFlight, fps: Double) -> ShuttleVector {
    var flight = launch
    for _ in 0..<Int(8 * fps) {
        if let event = flight.advance(by: 1 / fps) {
            precondition(event == .floor && flight.position.y == 0, "Expected floor at \(fps) Hz")
            return flight.position
        }
    }
    fatalError("Flight exceeded eight seconds at \(fps) Hz")
}

func testNominalShots() {
    for shot in ShuttleShot.allCases {
        let start = shot == .serve
            ? ShuttleVector(x: -0.84, y: 1.12, z: 3.62)
            : ShuttleVector(x: -0.84, y: 2.6, z: 5)
        let target = ShuttleVector(x: 1.5, y: 0, z: shot == .drop ? -1.4 : -5.6)
        let flight = ShuttlePhysics.launch(from: start, toward: target, shot: shot)
        guard let predicted = ShuttlePhysics.landing(of: flight),
              let reach = ShuttlePhysics.intercept(of: flight, side: -1, height: 2) else {
            fatalError("Missing landing or racket interception for \(shot)")
        }
        precondition(groundDistance(predicted, target) < 0.01, "Target miss for \(shot)")
        precondition(reach.z < 0 && reach.y > 0 && reach.y <= 2.001, "Bad intercept for \(shot)")
        for fps in [30.0, 59, 120] {
            let observed = floorContact(flight, fps: fps)
            precondition(groundDistance(predicted, observed) < 0.005, "Frame-rate drift for \(shot)")
        }
    }
}

func testFaultsAndFreeFall() {
    let lowCrossing = ShuttleVector(x: 0, y: 1.0, z: 0.02)
    let rush = ShuttleVector(x: 0, y: 0, z: -35)
    var net = ShuttleFlight(position: lowCrossing, velocity: rush)
    precondition(ShuttlePhysics.landing(of: net) == nil, "Net fault predicted a landing")
    precondition(net.advance(by: 0.16) == .net && net.position.z == 0, "Skipped net")
    let atImpact = net
    precondition(net.advance(by: 0.5) == .net && net == atImpact, "Fault state moved")
    var over = ShuttleFlight(position: ShuttleVector(x: 0, y: 1.59, z: 0.02), velocity: rush)
    precondition(over.advance(by: 0.16) == nil && over.position.z < 0, "Legal shot hit the tape")
    let line = ShuttleVector(x: 2.59, y: 0, z: 6.70)
    let out = ShuttleVector(x: 2.60, y: 0, z: 6.69)
    precondition(ShuttlePhysics.inSinglesCourt(line) && !ShuttlePhysics.inSinglesCourt(out))

    var freeFall = ShuttleFlight(position: ShuttleVector(x: 0, y: 100, z: 4), velocity: .zero)
    freeFall.advance(by: 6)
    // Terminal speed when the quadratic drag acceleration balances gravity.
    let expectedSpeed = sqrt(9.81 / 0.205)
    precondition(freeFall.position.y > 0 && abs(freeFall.velocity.y + expectedSpeed) < 0.001)
}

func testShotSweep() {
    var trials = 0
    var speedLimitedMisses = 0
    for shot in ShuttleShot.allCases {
        for depth in [0.9, 2.5, 4.5, 6.2] {
            for height in [0.8, 1.4, 2.4, 3.1] {
                for targetDepth in [0.9, 2.2, 3.5, 6.1] {
                    for side in [-1.0, 1.0] {
                        let start = ShuttleVector(x: -1.5, y: height, z: side * depth)
                        let target = ShuttleVector(x: 1, y: 0, z: -side * targetDepth)
                        let flight = ShuttlePhysics.launch(from: start, toward: target, shot: shot)
                        let label = "\(shot), \(start) to \(target)"
                        guard let mark = ShuttlePhysics.landing(of: flight) else {
                            fatalError("Unexpected net fault: \(label)")
                        }
                        trials += 1
                        let speed = flight.velocity.length
                        let error = groundDistance(mark, target)
                        precondition(speed <= 100.001 && error.isFinite, label)
                        precondition(mark.z * side < 0 && ShuttlePhysics.inSinglesCourt(mark), label)
                        if error > 0.12 {
                            // Long, steep smashes can run out of speed before the baseline.
                            precondition(shot == .smash && speed >= 99.9, "Uncapped miss: \(label)")
                            precondition(abs(mark.z) < targetDepth && error <= 1.45, label)
                            speedLimitedMisses += 1
                        }
                    }
                }
            }
        }
    }
    precondition(trials == 640 && speedLimitedMisses <= 4, "Shot sweep accuracy regressed")
    print("\(trials) shot paths passed (\(speedLimitedMisses) speed-limited landings).")
}

testNominalShots()
testFaultsAndFreeFall()
testShotSweep()
print("Flight invariance, interception, faults and terminal speed passed.")
