//
//  Props.swift
//  lego-morts-one-3d
//
//  Things you find in the village: metal, levers, doors, the hole, lockers.
//

import UIKit
import SceneKit
import simd

enum Props {

    /// A shiny piece of metal that spins and floats. Walk into it to collect it.
    static func metal() -> SCNNode {
        let box = SCNBox(width: 0.7, height: 0.7, length: 0.7, chamferRadius: 0.1)
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(white: 0.78, alpha: 1)
        mat.emission.contents = UIColor(white: 0.28, alpha: 1)
        mat.specular.contents = UIColor.white
        box.materials = [mat]

        let node = SCNNode(geometry: box)
        node.eulerAngles = SCNVector3(0.5, 0.4, 0)

        let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 2.5))
        let up = SCNAction.moveBy(x: 0, y: 0.3, z: 0, duration: 1.0)
        up.timingMode = .easeInEaseOut
        let bob = SCNAction.repeatForever(SCNAction.sequence([up, up.reversed()]))
        node.runAction(spin)
        node.runAction(bob)
        return node
    }

    /// A lever with a red handle. Returns the root, the handle (to pull) and the beam.
    static func lever() -> (root: SCNNode, handle: SCNNode, beam: SCNNode) {
        let root = SCNNode()

        let base = SCNBox(width: 1.1, height: 0.5, length: 1.1, chamferRadius: 0.06)
        let baseMat = SCNMaterial()
        baseMat.diffuse.contents = UIColor(white: 0.22, alpha: 1)
        base.materials = [baseMat]
        let baseNode = SCNNode(geometry: base)
        baseNode.position = SCNVector3(0, 0.25, 0)
        root.addChildNode(baseNode)

        let handleGeo = SCNBox(width: 0.2, height: 1.4, length: 0.2, chamferRadius: 0.06)
        let handleMat = SCNMaterial()
        handleMat.diffuse.contents = UIColor.red
        handleMat.emission.contents = UIColor(red: 0.5, green: 0, blue: 0, alpha: 1)
        handleGeo.materials = [handleMat]
        let handle = SCNNode(geometry: handleGeo)
        handle.pivot = SCNMatrix4MakeTranslation(0, -0.7, 0)
        handle.position = SCNVector3(0, 0.5, 0)
        root.addChildNode(handle)

        let beam = goalBeam(color: UIColor(red: 0.2, green: 1.0, blue: 0.4, alpha: 1))
        root.addChildNode(beam)

        return (root, handle, beam)
    }

    /// A tall glowing beam of light that marks a place you need to reach.
    static func goalBeam(color: UIColor) -> SCNNode {
        let root = SCNNode()
        let cyl = SCNCylinder(radius: 0.7, height: 40)
        let mat = SCNMaterial()
        mat.diffuse.contents = color.withAlphaComponent(0.2)
        mat.emission.contents = color
        mat.blendMode = .add
        mat.isDoubleSided = true
        mat.writesToDepthBuffer = false
        cyl.materials = [mat]
        let beam = SCNNode(geometry: cyl)
        beam.position = SCNVector3(0, 20, 0)
        root.addChildNode(beam)

        let pulse = SCNAction.repeatForever(SCNAction.sequence([
            SCNAction.fadeOpacity(to: 0.45, duration: 0.8),
            SCNAction.fadeOpacity(to: 1.0, duration: 0.8)
        ]))
        root.runAction(pulse)
        return root
    }

    /// A flickering street lamp for the village streets.
    static func streetLamp(at position: SIMD3<Float>) -> SCNNode {
        let root = SCNNode()
        root.simdPosition = position

        let pole = LegoBuilder.brick(width: 0.25, height: 5.0, length: 0.25,
                                     color: UIColor(white: 0.18, alpha: 1))
        pole.position = SCNVector3(0, 2.5, 0)
        root.addChildNode(pole)

        let lamp = SCNNode(geometry: SCNSphere(radius: 0.35))
        let lampMat = SCNMaterial()
        lampMat.diffuse.contents = UIColor(red: 1.0, green: 0.85, blue: 0.5, alpha: 1)
        lampMat.emission.contents = UIColor(red: 1.0, green: 0.75, blue: 0.35, alpha: 1)
        lamp.geometry?.materials = [lampMat]
        lamp.position = SCNVector3(0, 5.2, 0)
        root.addChildNode(lamp)

        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .omni
        light.light?.color = UIColor(red: 1.0, green: 0.85, blue: 0.55, alpha: 1)
        light.light?.intensity = 450
        light.light?.attenuationStartDistance = 2
        light.light?.attenuationEndDistance = 22
        light.position = SCNVector3(0, 5.2, 0)
        root.addChildNode(light)

        let flicker = SCNAction.repeatForever(SCNAction.sequence([
            SCNAction.run { $0.light?.intensity = CGFloat.random(in: 180...520) },
            SCNAction.wait(duration: 0.15)
        ]))
        light.runAction(flicker)
        return root
    }

    /// A dark hole in the ground you can fall into.
    static func hole() -> SCNNode {
        let root = SCNNode()

        let pit = SCNCylinder(radius: 3.2, height: 0.4)
        let pitMat = SCNMaterial()
        pitMat.diffuse.contents = UIColor.black
        pitMat.emission.contents = UIColor(white: 0.02, alpha: 1)
        pit.materials = [pitMat]
        let pitNode = SCNNode(geometry: pit)
        pitNode.position = SCNVector3(0, 0.05, 0)
        root.addChildNode(pitNode)

        // Stone rim
        let rim = SCNTorus(ringRadius: 3.4, pipeRadius: 0.35)
        let rimMat = SCNMaterial()
        rimMat.diffuse.contents = UIColor(white: 0.25, alpha: 1)
        rim.materials = [rimMat]
        let rimNode = SCNNode(geometry: rim)
        rimNode.position = SCNVector3(0, 0.25, 0)
        root.addChildNode(rimNode)

        // Warning glow from deep inside
        let glow = SCNNode(geometry: SCNCylinder(radius: 1.2, height: 0.1))
        let glowMat = SCNMaterial()
        glowMat.diffuse.contents = UIColor(red: 0.5, green: 0, blue: 0, alpha: 1)
        glowMat.emission.contents = UIColor(red: 0.45, green: 0, blue: 0, alpha: 1)
        glow.geometry?.materials = [glowMat]
        glow.position = SCNVector3(0, -0.2, 0)
        root.addChildNode(glow)

        return root
    }

    /// A metal door in a frame. `doorPanel` is the part that closes / gets smashed.
    static func metalDoor() -> (root: SCNNode, doorPanel: SCNNode) {
        let root = SCNNode()
        let metal = UIColor(white: 0.55, alpha: 1)
        let dark = UIColor(white: 0.2, alpha: 1)

        // Frame posts
        for side in [-1.0, 1.0] {
            let post = LegoBuilder.brick(width: 0.5, height: 5.0, length: 0.6, color: dark)
            post.position = SCNVector3(Float(side) * 1.8, 2.5, 0)
            root.addChildNode(post)
        }
        let lintel = LegoBuilder.brick(width: 4.1, height: 0.5, length: 0.6, color: dark)
        lintel.position = SCNVector3(0, 5.1, 0)
        root.addChildNode(lintel)

        // Door panel (open = slid to the side)
        let panel = SCNBox(width: 3.2, height: 4.6, length: 0.25, chamferRadius: 0.04)
        let panelMat = SCNMaterial()
        panelMat.diffuse.contents = metal
        panelMat.metalness.contents = 0.85
        panelMat.roughness.contents = 0.35
        panelMat.emission.contents = UIColor(white: 0.08, alpha: 1)
        panel.materials = [panelMat]
        let doorPanel = SCNNode(geometry: panel)
        doorPanel.position = SCNVector3(3.6, 2.4, 0) // starts open (to the side)
        root.addChildNode(doorPanel)

        // Handle
        let handle = LegoBuilder.brick(width: 0.15, height: 0.5, length: 0.35, color: UIColor(white: 0.75, alpha: 1))
        handle.position = SCNVector3(-1.1, 0, 0.2)
        doorPanel.addChildNode(handle)

        return (root, doorPanel)
    }

    /// A big doorway that can be open or shut. Used for the two post-lever doors.
    static func choiceDoor(labelColor: UIColor) -> (root: SCNNode, doorPanel: SCNNode) {
        let made = metalDoor()
        // Colored light above the door so you know which is which.
        let lamp = SCNNode(geometry: SCNSphere(radius: 0.4))
        let mat = SCNMaterial()
        mat.diffuse.contents = labelColor
        mat.emission.contents = labelColor
        lamp.geometry?.materials = [mat]
        lamp.position = SCNVector3(0, 5.8, 0)
        made.root.addChildNode(lamp)
        return made
    }

    /// A flat blood stain on the ground.
    static func bloodStain(scale: Float = 1) -> SCNNode {
        let plane = SCNPlane(width: CGFloat(1.8 * scale), height: CGFloat(1.1 * scale))
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 0.45, green: 0.02, blue: 0.02, alpha: 0.85)
        mat.emission.contents = UIColor(red: 0.15, green: 0, blue: 0, alpha: 1)
        mat.isDoubleSided = true
        plane.materials = [mat]
        let node = SCNNode(geometry: plane)
        node.eulerAngles = SCNVector3(-Float.pi / 2, Float.random(in: 0...Float.pi), 0)
        node.position = SCNVector3(0, 0.03, 0)
        return node
    }

    /// A metal road strip between two points on the ground.
    static func road(from a: SIMD3<Float>, to b: SIMD3<Float>) -> SCNNode {
        let dx = b.x - a.x
        let dz = b.z - a.z
        let length = max(0.5, hypot(dx, dz))
        let box = SCNBox(width: CGFloat(length), height: 0.12, length: 2.2, chamferRadius: 0.02)
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(white: 0.42, alpha: 1)
        mat.metalness.contents = 0.8
        mat.roughness.contents = 0.35
        mat.emission.contents = UIColor(white: 0.06, alpha: 1)
        box.materials = [mat]
        let node = SCNNode(geometry: box)
        node.simdPosition = SIMD3<Float>((a.x + b.x) * 0.5, 0.06, (a.z + b.z) * 0.5)
        node.eulerAngles = SCNVector3(0, atan2(dx, dz) + Float.pi / 2, 0)
        return node
    }

    /// A metal locker you can hide inside.
    static func locker() -> SCNNode {
        let root = SCNNode()
        let body = SCNBox(width: 1.4, height: 3.2, length: 1.1, chamferRadius: 0.05)
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(white: 0.4, alpha: 1)
        mat.metalness.contents = 0.7
        mat.roughness.contents = 0.4
        body.materials = [mat]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 1.6, 0)
        root.addChildNode(bodyNode)

        let slit = SCNBox(width: 0.7, height: 0.12, length: 0.08, chamferRadius: 0)
        let slitMat = SCNMaterial()
        slitMat.diffuse.contents = UIColor.black
        slit.materials = [slitMat]
        let slitNode = SCNNode(geometry: slit)
        slitNode.position = SCNVector3(0, 2.5, 0.56)
        root.addChildNode(slitNode)

        let handle = LegoBuilder.brick(width: 0.12, height: 0.35, length: 0.2,
                                       color: UIColor(white: 0.7, alpha: 1))
        handle.position = SCNVector3(0.45, 1.6, 0.6)
        root.addChildNode(handle)

        return root
    }
}
