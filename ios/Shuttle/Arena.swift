import SceneKit
import UIKit
import simd

/// The venue uses metres. The cork points down the shuttle's local negative Y axis.
final class Arena {
    let cameraNode = SCNNode()
    let shuttleNode = SCNNode()
    let shadowNode = SCNNode()
    private let landing = SCNNode()

    init(scene: SCNScene) {
        scene.background.contents = UIColor(red: 0.038, green: 0.073, blue: 0.107, alpha: 1)
        scene.fogColor = UIColor(red: 0.056, green: 0.105, blue: 0.14, alpha: 1)
        scene.fogStartDistance = 19.5
        scene.fogEndDistance = 52
        scene.fogDensityExponent = 1.3

        let venue = Self.readVenue() ?? Self.practiceSurface()
        scene.rootNode.addChildNode(venue)
        makeLights(in: scene)
        cameraNode.name = "Baseline broadcast camera"
        let camera = SCNCamera()
        camera.projectionDirection = .vertical
        camera.zNear = 0.07
        camera.zFar = 65
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.bloomIntensity = 0.13
        camera.bloomThreshold = 1.18
        camera.bloomBlurRadius = 3
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        updateCamera(aspect: 1.9)

        makeShuttle()
        makeFloorMarks()
        for node in [shadowNode, landing, shuttleNode] {
            scene.rootNode.addChildNode(node)
        }
    }

    func updateCamera(aspect: Float) {
        cameraNode.position = SCNVector3(0, 5.55, 11.95)
        cameraNode.look(at: SCNVector3(0, 0.32, -0.58))
        // Protect the singles sidelines when the window is narrow.
        let fovForWidth = 2 * atan(0.53 / max(0.25, Double(aspect))) * 180 / .pi
        cameraNode.camera?.fieldOfView = CGFloat(max(55.0, fovForWidth))
    }

    func presentLanding(at position: SCNVector3?) {
        landing.isHidden = position == nil
        if let position {
            landing.position = SCNVector3(position.x, 0.022, position.z)
        }
    }

    private func makeLights(in scene: SCNScene) {
        func lamp(_ type: SCNLight.LightType, _ color: UIColor, _ intensity: CGFloat, _ position: SCNVector3) -> SCNNode {
            let light = SCNLight()
            light.type = type
            light.color = color
            light.intensity = intensity
            let node = SCNNode()
            node.light = light
            node.position = position
            scene.rootNode.addChildNode(node)
            if type != .ambient { node.look(at: SCNVector3Zero) }
            return node
        }
        _ = lamp(.ambient, UIColor(red: 0.73, green: 0.84, blue: 0.95, alpha: 1), 390, SCNVector3Zero)
        let key = lamp(.directional, UIColor(red: 1, green: 0.95, blue: 0.83, alpha: 1), 1030, SCNVector3(-4.4, 9.7, 4.6))
        key.light?.castsShadow = true
        key.light?.shadowMapSize = CGSize(width: 1024, height: 1024)
        key.light?.shadowSampleCount = 4
        key.light?.shadowRadius = 3
        key.light?.shadowBias = 0.8
        key.light?.shadowColor = UIColor(white: 0.10, alpha: 0.38)
        key.light?.orthographicScale = 14
        key.light?.zNear = 0.15
        key.light?.zFar = 35
        let rim = lamp(.directional, UIColor(red: 0.53, green: 0.84, blue: 1, alpha: 1), 570, SCNVector3(5.5, 5.3, -7.4))
        rim.name = "Backcourt cool fill"
    }

    /// Interleaved position, normal and UV with a UInt32 index buffer per material.
    /// The source art generator and the offline venue render read this same mesh.
    private static func readVenue() -> SCNNode? {
        guard let data = NSDataAsset(name: "StadiumMesh")?.data,
              data.count >= 8, data.prefix(4) == Data("BDA1".utf8) else { return nil }
        var offset = 4
        func byte() -> Int { defer { offset += 1 }; return Int(data[offset]) }
        func word() -> Int { byte() | (byte() << 8) | (byte() << 16) | (byte() << 24) }

        let root = SCNNode()
        root.name = "Featherblade / Court 01"
        let groupCount = word()
        guard (1...128).contains(groupCount) else { return nil }
        for _ in 0..<groupCount {
            guard offset + 16 <= data.count else { return nil }
            let red = CGFloat(byte()) / 255, green = CGFloat(byte()) / 255, blue = CGFloat(byte()) / 255
            let emission = CGFloat(byte()) / 255, roughness = CGFloat(byte()) / 255, metallic = CGFloat(byte()) / 255
            let texture = byte()
            _ = byte()
            let vertexCount = word(), indexCount = word()
            let vertexBytes = vertexCount * 32, indexBytes = indexCount * 4
            guard vertexCount > 0, indexCount.isMultiple(of: 3),
                  vertexBytes + indexBytes <= data.count - offset else { return nil }
            let vertices = data.subdata(in: offset..<offset + vertexBytes)
            offset += vertexBytes
            let indices = data.subdata(in: offset..<offset + indexBytes)
            offset += indexBytes
            func source(_ semantic: SCNGeometrySource.Semantic, _ count: Int, _ start: Int) -> SCNGeometrySource {
                SCNGeometrySource(data: vertices, semantic: semantic, vectorCount: vertexCount, usesFloatComponents: true,
                                  componentsPerVector: count, bytesPerComponent: 4, dataOffset: start, dataStride: 32)
            }
            let element = SCNGeometryElement(data: indices, primitiveType: .triangles, primitiveCount: indexCount / 3, bytesPerIndex: 4)
            let geo = SCNGeometry(sources: [source(.vertex, 3, 0), source(.normal, 3, 12), source(.texcoord, 2, 24)], elements: [element])
            let color = UIColor(red: red, green: green, blue: blue, alpha: 1)
            let mat = SCNMaterial()
            mat.lightingModel = .physicallyBased
            mat.roughness.contents = NSNumber(value: Double(roughness))
            mat.metalness.contents = NSNumber(value: Double(metallic))
            mat.diffuse.contents = color
            if texture == 1 || texture == 2, let image = UIImage(named: texture == 1 ? "CourtSurface" : "CourtRibbon") {
                // Mesh authoring uses the lower-left UV origin. SceneKit samples from the upper left.
                var textureTransform = SCNMatrix4Identity
                textureTransform.m22 = -1
                textureTransform.m42 = 1
                mat.diffuse.contents = image
                mat.diffuse.contentsTransform = textureTransform
                mat.diffuse.mipFilter = .linear
                mat.diffuse.maxAnisotropy = 8
                if emission > 0 {
                    mat.emission.contents = image
                    mat.emission.contentsTransform = textureTransform
                    mat.emission.intensity = emission
                }
            } else if emission > 0 {
                mat.emission.contents = color
                mat.emission.intensity = emission
            }
            mat.isDoubleSided = true
            geo.materials = [mat]
            let node = SCNNode(geometry: geo)
            node.castsShadow = false
            root.addChildNode(node)
        }
        return offset == data.count ? root : nil
    }

    private static func practiceSurface() -> SCNNode {
        let plane = SCNPlane(width: 12, height: 20)
        let m = SCNMaterial()
        if let surface = UIImage(named: "CourtSurface") { m.diffuse.contents = surface }
        else { m.diffuse.contents = UIColor.systemTeal }
        plane.materials = [m]
        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = -.pi / 2
        return node
    }

    private func makeShuttle() {
        func finish(_ geometry: SCNGeometry, _ color: UIColor, _ center: Float) {
            let material = SCNMaterial()
            material.lightingModel = .blinn
            material.diffuse.contents = color
            material.emission.contents = color
            material.emission.intensity = 0.24
            material.isDoubleSided = true
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.position.y = center
            shuttleNode.addChildNode(node)
        }
        let bone = UIColor(red: 1, green: 0.98, blue: 0.82, alpha: 1)
        let ice = UIColor(red: 0.76, green: 0.98, blue: 0.90, alpha: 1)
        let gold = UIColor(red: 1, green: 0.71, blue: 0.35, alpha: 1)
        let cork = SCNCapsule(capRadius: 0.025, height: 0.063)
        cork.radialSegmentCount = 12
        finish(cork, bone, -0.052)
        let band = SCNCylinder(radius: 0.026, height: 0.012)
        band.radialSegmentCount = 16
        finish(band, gold, -0.034)
        // Each vane sweeps past its rachis and overlaps its neighbour.
        var feathers = [SCNVector3](), shafts = [SCNVector3]()
        func point(_ r: Float, _ angle: Float, _ y: Float) -> SCNVector3 {
            SCNVector3(r * cos(angle), y, r * sin(angle))
        }
        for i in 0..<16 {
            let a = Float(i) * 2 * .pi / 16
            let root = point(0.019, a, -0.029), shoulder = point(0.051, a + 0.12, 0.060)
            let left = point(0.060, a - 0.12, 0.077), right = point(0.064, a + 0.35, 0.082)
            let tip = point(0.072, a + 0.24, 0.108 + 0.002 * sin(a * 3))
            let heel = point(0.032, a - 0.03, 0.004)
            feathers += [heel, left, shoulder, left, tip, shoulder, shoulder, tip, right, heel, shoulder, right]
            shafts += [point(0.020, a - 0.045, -0.028), point(0.020, a + 0.045, -0.028), shoulder,
                       root, tip, point(0.055, a + 0.14, 0.067)]
        }
        func mesh(_ points: [SCNVector3]) -> SCNGeometry {
            var normals = [SCNVector3]()
            for i in stride(from: 0, to: points.count, by: 3) {
                func vector(_ p: SCNVector3) -> SIMD3<Float> { SIMD3(p.x, p.y, p.z) }
                let a = vector(points[i]), b = vector(points[i + 1]), c = vector(points[i + 2])
                let n = simd_normalize(simd_cross(b - a, c - a))
                normals.append(contentsOf: Array(repeating: SCNVector3(n.x, n.y, n.z), count: 3))
            }
            let element = SCNGeometryElement(indices: (0..<points.count).map { UInt16($0) }, primitiveType: .triangles)
            return SCNGeometry(sources: [SCNGeometrySource(vertices: points), SCNGeometrySource(normals: normals)], elements: [element])
        }
        finish(mesh(feathers), bone, 0)
        finish(mesh(shafts), ice, 0)
        for (radius, y) in [(0.030, -0.002), (0.040, 0.027)] {
            let tie = SCNTorus(ringRadius: CGFloat(radius), pipeRadius: 0.0018)
            tie.ringSegmentCount = 20
            tie.pipeSegmentCount = 4
            finish(tie, ice, Float(y))
        }
        shuttleNode.name = "Feather shuttle / cork-forward"
        // The render mesh is enlarged for flight legibility at phone scale.
        shuttleNode.scale = SCNVector3(1.45, 1.45, 1.45)
    }

    private func makeFloorMarks() {
        let side: CGFloat = 96
        let shadow = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { renderer in
            let space = CGColorSpaceCreateDeviceRGB()
            let colors = [UIColor(white: 0.02, alpha: 0.83).cgColor, UIColor(white: 0.02, alpha: 0.40).cgColor,
                          UIColor(white: 0.02, alpha: 0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.45, 1]) else { return }
            let center = CGPoint(x: side / 2, y: side / 2)
            renderer.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: side / 2, options: [])
        }
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.diffuse.contents = shadow
        mat.blendMode = .alpha
        mat.writesToDepthBuffer = false
        let patch = SCNPlane(width: 0.38, height: 0.31)
        patch.materials = [mat]
        let face = SCNNode(geometry: patch)
        face.eulerAngles.x = -.pi / 2
        face.castsShadow = false
        shadowNode.addChildNode(face)
        shadowNode.renderingOrder = 1
        let luminous = SCNMaterial()
        luminous.lightingModel = .constant
        luminous.diffuse.contents = UIColor(red: 0.97, green: 0.82, blue: 0.48, alpha: 1)
        let ring = SCNTorus(ringRadius: 0.225, pipeRadius: 0.011)
        ring.ringSegmentCount = 36
        ring.pipeSegmentCount = 4
        ring.materials = [luminous]
        let circle = SCNNode(geometry: ring)
        circle.castsShadow = false
        landing.addChildNode(circle)
        for i in 0..<4 {
            let tick = SCNBox(width: 0.018, height: 0.009, length: 0.090, chamferRadius: 0)
            tick.materials = [luminous]
            let node = SCNNode(geometry: tick)
            let angle = Float(i) * .pi / 2
            node.position = SCNVector3(0.30 * sin(angle), 0, 0.30 * cos(angle))
            node.eulerAngles.y = angle
            node.castsShadow = false
            landing.addChildNode(node)
        }
        landing.opacity = 0.75
        landing.isHidden = true
    }
}
