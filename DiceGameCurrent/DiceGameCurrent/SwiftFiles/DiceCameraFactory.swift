import SceneKit

/// Sets up a straight-down orthographic camera over the playfield.
///
/// Orthographic (not perspective) is the right call here for two reasons:
/// it keeps the floor a true rectangle from the camera's point of view
/// (perspective would make it a trapezoid, which breaks the assumption
/// PlayfieldBoundsCalculator relies on), and it's cheaper to render —
/// worth having given the "optimize for small screens" goal alongside the
/// lowered wall height.
enum DiceCameraFactory {

    /// orthographicScale should come from PlayfieldLayout.compute(...) —
    /// computed together with the bounds passed to everything else
    /// (floor, walls, spawn pattern), so the camera's framing and the
    /// actual playfield geometry are guaranteed consistent rather than
    /// derived twice via two different formulas that could drift apart.
    static func makeTopDownCamera(
        playfieldBounds: (x: ClosedRange<Float>, z: ClosedRange<Float>),
        orthographicScale: Double,
        floorY: Float,
        cameraHeight: Float = 15
    ) -> SCNNode {
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = orthographicScale
        camera.zNear = 0.1
        camera.zFar = Double(cameraHeight * 2)

        let node = SCNNode()
        node.camera = camera

        let centerX = (playfieldBounds.x.lowerBound + playfieldBounds.x.upperBound) / 2
        let centerZ = (playfieldBounds.z.lowerBound + playfieldBounds.z.upperBound) / 2
        node.position = SCNVector3(centerX, floorY + cameraHeight, centerZ)

        // Rotate to look straight down (-Y). Confirm in the Xcode scene
        // editor that "up" on screen matches what you expect (e.g. score
        // bar side vs. Roll button side) — rotate around Y afterward if
        // the playfield appears mirrored or rotated 90°.
        node.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)

        return node
    }
}
