//
//  Person.swift
//  lego-morts-one-3d
//
//  A little LEGO townsperson. They can be alive... or dead.
//

import UIKit
import SceneKit

final class Person {

    let node = SCNNode()
    let slot: SCNVector3
    private(set) var isAlive = true

    // Remember each material's original color so a dead person can come back.
    private var originalColors: [SCNMaterial: Any] = [:]

    init(slot: SCNVector3, shirt: UIColor) {
        self.slot = slot
        node.position = slot
        build(shirt: shirt)
    }

    private func build(shirt: UIColor) {
        let pants = UIColor(red: 0.15, green: 0.15, blue: 0.22, alpha: 1)
        let skin = UIColor(red: 0.98, green: 0.82, blue: 0.25, alpha: 1) // classic LEGO yellow

        // Legs
        let legs = LegoBuilder.brick(width: 0.75, height: 0.75, length: 0.55, color: pants)
        legs.position = SCNVector3(0, 0.375, 0)
        node.addChildNode(legs)

        // Torso
        let torso = LegoBuilder.brick(width: 0.85, height: 0.9, length: 0.6, color: shirt)
        torso.position = SCNVector3(0, 1.2, 0)
        node.addChildNode(torso)

        // Arms
        for side in [-1.0, 1.0] {
            let arm = LegoBuilder.brick(width: 0.22, height: 0.8, length: 0.3, color: shirt)
            arm.position = SCNVector3(Float(side) * 0.55, 1.2, 0)
            node.addChildNode(arm)
        }

        // Head (classic minifigure cylinder) with a stud on top
        let head = SCNNode(geometry: SCNCylinder(radius: 0.3, height: 0.5))
        let headMat = SCNMaterial()
        headMat.diffuse.contents = skin
        head.geometry?.materials = [headMat]
        head.position = SCNVector3(0, 1.9, 0)
        node.addChildNode(head)

        let headStud = LegoBuilder.stud(color: skin)
        headStud.position = SCNVector3(0, 2.21, 0)
        node.addChildNode(headStud)

        // Two little eyes
        for dx in [-0.11, 0.11] {
            let eye = SCNNode(geometry: SCNSphere(radius: 0.05))
            let eyeMat = SCNMaterial()
            eyeMat.diffuse.contents = UIColor.black
            eye.geometry?.materials = [eyeMat]
            eye.position = SCNVector3(Float(dx), 1.95, 0.29)
            node.addChildNode(eye)
        }
    }

    /// Killed by a monster: fall over and turn gray.
    func die() {
        guard isAlive else { return }
        isAlive = false

        node.enumerateHierarchy { child, _ in
            child.geometry?.materials.forEach { mat in
                if originalColors[mat] == nil {
                    originalColors[mat] = mat.diffuse.contents
                }
                mat.diffuse.contents = UIColor(white: 0.3, alpha: 1)
                mat.emission.contents = UIColor.black
            }
        }

        let fall = SCNAction.rotateTo(x: .pi / 2,
                                      y: CGFloat(node.eulerAngles.y),
                                      z: 0,
                                      duration: 0.35,
                                      usesShortestUnitArc: true)
        let drop = SCNAction.move(to: SCNVector3(slot.x, 0.25, slot.z), duration: 0.35)
        node.runAction(SCNAction.group([fall, drop]))
    }

    /// Come back to life and stand up again.
    func revive() {
        guard !isAlive else { return }
        isAlive = true

        node.enumerateHierarchy { child, _ in
            child.geometry?.materials.forEach { mat in
                if let original = originalColors[mat] {
                    mat.diffuse.contents = original
                }
                mat.emission.contents = UIColor.black
            }
        }

        node.eulerAngles = SCNVector3Zero
        let standUp = SCNAction.move(to: slot, duration: 0.3)
        node.runAction(standUp)
    }
}
