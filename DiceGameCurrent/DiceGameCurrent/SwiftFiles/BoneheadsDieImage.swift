import Metal
import SceneKit
import UIKit
import simd

/// A banked Boneheads die, rendered from the real die.
///
/// The grid used to draw a rounded rectangle with pips on it. The ask was
/// that a banked die be a literal copy of the one that was thrown, so this
/// renders the actual `d6.obj` mesh with the actual `DieMaterial` and the
/// actual face numerals, under a light matched to the tray's, and hands
/// back a picture of it.
///
/// **Tilted rather than top-down.** The tray's camera looks straight down,
/// where a die shows only its top face; here the whole point is to see
/// that it is a cube, so the camera sits off to one side and above.
///
/// Rendered once per face and colour and cached: two colours by six faces
/// is twelve images for a whole match, about 1.7 MB at 192px. The board
/// asks for one every time it draws a slot, so this has to be a lookup
/// rather than a render.
///
/// Every step of it can fail on a device this was never compiled for — no
/// mesh in the bundle, no Metal device, a snapshot that comes back
/// opaque — so every step returns nil rather than a broken picture, and
/// `BoneheadsGrid` falls back to the flat `PipFace` it drew before.
enum BoneheadsDieImage {

    /// The rendered canvas. Double the ~90pt a slot gets on a phone.
    static let pixels: CGFloat = 192

    /// How far the camera sits off vertical. Straight down shows one face
    /// and nothing else; this shows the top and two sides, which is what
    /// says "cube" at a glance.
    static let tilt: CGFloat = 0.52          // radians, about 30 degrees

    private static var cache: [String: UIImage] = [:]

    /// Whether rendering has already been found not to work here.
    ///
    /// One failure is enough: without this, every draw of every slot would
    /// retry a Metal device that is not coming back.
    private static var isUnavailable = false

    static func image(value: Int, colorway: DieColorway) -> UIImage? {
        guard !isUnavailable else { return nil }
        let key = "\(value)-\(colorway.bodyHex)-\(colorway.numberHex)"
        if let cached = cache[key] { return cached }
        guard let rendered = render(value: value, colorway: colorway) else {
            isUnavailable = true
            return nil
        }
        cache[key] = rendered
        return rendered
    }

    // MARK: Rendering

    private static func render(value: Int, colorway: DieColorway) -> UIImage? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let die = DieMeshLibrary.templateNode(forSides: 6) else { return nil }

        DieMaterial.apply(sides: 6, colorway: colorway, to: die)
        die.position = SCNVector3Zero
        die.orientation = orientation(showing: value)

        let scene = SCNScene()
        // Clear, so the die sits on the board's own cell rather than on a
        // square of its own.
        scene.background.contents = UIColor.clear
        scene.rootNode.addChildNode(die)

        // The tray's key light, same pitch and yaw, so a banked die is lit
        // the way the die that made it was. No shadow: there is no floor
        // here to catch one, and the shadow under a banked die is
        // SwiftUI's, from `Elevation` — one shadow system for the app.
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 900
        key.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 6, 0)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 420
        scene.rootNode.addChildNode(fill)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        // A cube of side 1 measures 1.73 corner to corner and is seen
        // corner-on here, so its silhouette is about 1.3 across. 1.05
        // leaves a margin rather than clipping the one edge that carries
        // the shape — there is no renderer here to measure it against, so
        // the margin is deliberate.
        camera.camera?.orthographicScale = 1.05
        let radius: Float = 6
        camera.position = SCNVector3(
            radius * sin(Float(tilt)) * 0.7071,
            radius * cos(Float(tilt)),
            radius * sin(Float(tilt)) * 0.7071
        )
        camera.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(camera)

        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        renderer.autoenablesDefaultLighting = false

        return renderer.snapshot(atTime: 0,
                                 with: CGSize(width: pixels, height: pixels),
                                 antialiasingMode: .multisampling4X)
    }

    /// Turns the die so `value` is the face pointing up.
    ///
    /// Face index to value is `index + 1`, which is the same convention
    /// `DieFaceLabels` numbers the permanent labels with and the same one
    /// `DiceRollController` scores a settled die by — so the picture and
    /// the number in the column cannot disagree.
    private static func orientation(showing value: Int) -> SCNQuaternion {
        let normals = DieFaceNormals.normals(forSides: 6)
        let index = max(0, min(value - 1, normals.count - 1))
        let n = normals[index]
        let from = simd_normalize(SIMD3<Float>(n.x, n.y, n.z))
        let to = SIMD3<Float>(0, 1, 0)
        // The 1 face points straight DOWN on this mesh, so `from` is
        // exactly `-to` for it — and a from/to rotation is undefined when
        // the two are antiparallel, which is a NaN orientation and an
        // invisible die for the most common face on the board. Half a
        // turn about X is the same rotation and is defined.
        let turn = simd_dot(from, to) < -0.9999
            ? simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
            : simd_quatf(from: from, to: to)
        // No yaw on top of that. The camera already sits at 45 degrees in
        // the horizontal plane, so an axis-aligned cube is seen corner-on
        // from it — top face plus two sides, which is what reads as a
        // cube. Turning the die 45 degrees as well would cancel that out
        // and put a single face square to the camera, which reads as a
        // tile.
        return SCNQuaternion(turn.vector.x, turn.vector.y,
                             turn.vector.z, turn.vector.w)
    }
}
