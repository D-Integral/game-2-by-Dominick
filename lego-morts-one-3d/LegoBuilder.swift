//
//  LegoBuilder.swift
//  lego-morts-one-3d
//
//  Helpers to build LEGO-style blocky objects (bricks, studs, houses).
//

import UIKit
import SceneKit

enum LegoBuilder {

    /// A single LEGO stud (the little round bump on top of a brick).
    static func stud(color: UIColor, radius: CGFloat = 0.16, height: CGFloat = 0.12) -> SCNNode {
        let cyl = SCNCylinder(radius: radius, height: height)
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        cyl.materials = [mat]
        return SCNNode(geometry: cyl)
    }

    /// A LEGO brick: a colored box, optionally with a grid of studs on top.
    /// `emission` makes the brick glow faintly so it stays visible in the dark.
    static func brick(width: CGFloat, height: CGFloat, length: CGFloat,
                      color: UIColor, studs: Bool = false, emission: UIColor? = nil) -> SCNNode {
        let box = SCNBox(width: width, height: height, length: length, chamferRadius: 0.04)
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        if let emission { mat.emission.contents = emission }
        box.materials = [mat]
        let node = SCNNode(geometry: box)

        if studs {
            let spacing: CGFloat = 0.5
            let countX = max(1, Int(width / spacing))
            let countZ = max(1, Int(length / spacing))
            let startX = -CGFloat(countX - 1) * spacing / 2
            let startZ = -CGFloat(countZ - 1) * spacing / 2
            for i in 0..<countX {
                for j in 0..<countZ {
                    let s = stud(color: color)
                    s.position = SCNVector3(Float(startX + CGFloat(i) * spacing),
                                            Float(height / 2 + 0.06),
                                            Float(startZ + CGFloat(j) * spacing))
                    node.addChildNode(s)
                }
            }
        }
        return node
    }

    /// A glowing little window that makes houses look creepy at night.
    private static func window(lit: Bool) -> SCNNode {
        let box = SCNBox(width: 0.55, height: 0.55, length: 0.1, chamferRadius: 0.02)
        let mat = SCNMaterial()
        if lit {
            mat.diffuse.contents = UIColor(red: 1.0, green: 0.82, blue: 0.35, alpha: 1)
            mat.emission.contents = UIColor(red: 0.9, green: 0.65, blue: 0.2, alpha: 1)
        } else {
            mat.diffuse.contents = UIColor(white: 0.04, alpha: 1)
        }
        box.materials = [mat]
        return SCNNode(geometry: box)
    }

    /// A blocky LEGO house with a roof, a door and glowing windows.
    static func house(bodyColor: UIColor, roofColor: UIColor) -> SCNNode {
        let root = SCNNode()
        let w: CGFloat = 3.2
        let h: CGFloat = 2.6
        let l: CGFloat = 3.0

        // Walls
        let body = brick(width: w, height: h, length: l, color: bodyColor, studs: false)
        body.position = SCNVector3(0, Float(h / 2), 0)
        root.addChildNode(body)

        // Roof (a pyramid sitting on top of the walls)
        let roof = SCNNode(geometry: SCNPyramid(width: w + 0.5, height: 1.7, length: l + 0.5))
        let roofMat = SCNMaterial()
        roofMat.diffuse.contents = roofColor
        roof.geometry?.materials = [roofMat]
        roof.position = SCNVector3(0, Float(h), 0)
        root.addChildNode(roof)

        // Door
        let door = SCNBox(width: 0.85, height: 1.35, length: 0.12, chamferRadius: 0.02)
        let doorMat = SCNMaterial()
        doorMat.diffuse.contents = UIColor(white: 0.06, alpha: 1)
        door.materials = [doorMat]
        let doorNode = SCNNode(geometry: door)
        doorNode.position = SCNVector3(0, 0.68, Float(l / 2) + 0.02)
        root.addChildNode(doorNode)

        // Two windows, randomly lit so the street feels alive (and scary)
        let leftWindow = window(lit: Bool.random())
        leftWindow.position = SCNVector3(-0.95, 1.7, Float(l / 2) + 0.02)
        root.addChildNode(leftWindow)

        let rightWindow = window(lit: Bool.random())
        rightWindow.position = SCNVector3(0.95, 1.7, Float(l / 2) + 0.02)
        root.addChildNode(rightWindow)

        return root
    }
}
