//
//  Monsters.swift
//  lego-morts-one-3d
//
//  The two monsters of LEGO Morts One. In the game they chase the player.
//   - DeuxRouge (aka GOD RED): red body, four white eyes.
//   - Sonnelves: all white, red eyes.
//

import UIKit
import SceneKit
import simd

/// Shared behaviour for a monster that can chase the player.
protocol Chaser: AnyObject {
    var node: SCNNode { get }
}

extension Chaser {
    /// Move toward a target position on the ground and turn to face it.
    func chase(toward target: SIMD3<Float>, speed: Float, dt: Float) {
        var pos = node.simdPosition
        var dir = target - pos
        dir.y = 0
        let dist = simd_length(dir)
        guard dist > 0.001 else { return }
        dir /= dist
        pos += dir * speed * dt
        pos.y = 0
        node.simdPosition = pos
        node.eulerAngles = SCNVector3(0, atan2(dir.x, dir.z), 0)
    }

    /// Distance (ignoring height) from the monster to a point.
    func groundDistance(to point: SIMD3<Float>) -> Float {
        var d = node.simdPosition - point
        d.y = 0
        return simd_length(d)
    }

    /// Hide the monster far away when it is not hunting.
    func park() {
        node.isHidden = true
        node.simdPosition = SIMD3<Float>(0, -100, 0)
    }

    /// Place the monster in the world, ready to hunt.
    func spawn(at pos: SIMD3<Float>) {
        node.isHidden = false
        node.simdPosition = pos
    }
}

// MARK: - Deux-Rouge / GOD RED

final class DeuxRouge: Chaser {

    let node = SCNNode()

    init() { build() }

    private func build() {
        let red = UIColor(red: 0.72, green: 0.04, blue: 0.04, alpha: 1)
        let dark = UIColor(red: 0.3, green: 0.0, blue: 0.0, alpha: 1)
        let glow = UIColor(red: 0.22, green: 0.0, blue: 0.0, alpha: 1)

        for side in [-1.0, 1.0] {
            let leg = LegoBuilder.brick(width: 0.5, height: 1.2, length: 0.6, color: red, emission: glow)
            leg.position = SCNVector3(Float(side) * 0.4, 0.6, 0)
            node.addChildNode(leg)
        }

        let body = LegoBuilder.brick(width: 1.7, height: 1.6, length: 1.0, color: red, emission: glow)
        body.position = SCNVector3(0, 2.0, 0)
        node.addChildNode(body)

        for side in [-1.0, 1.0] {
            let arm = LegoBuilder.brick(width: 0.4, height: 1.5, length: 0.5, color: red, emission: glow)
            arm.position = SCNVector3(Float(side) * 1.1, 2.0, 0)
            node.addChildNode(arm)
        }

        let head = LegoBuilder.brick(width: 1.5, height: 1.2, length: 1.05, color: red, emission: glow)
        head.position = SCNVector3(0, 3.4, 0)
        node.addChildNode(head)

        for dx in [-0.4, 0.4] {
            let s = LegoBuilder.stud(color: red, radius: 0.2, height: 0.14)
            s.position = SCNVector3(Float(dx), 4.07, 0)
            node.addChildNode(s)
        }

        // Four white glowing eyes in a 2x2 grid.
        for dx in [-0.33, 0.33] {
            for dy in [3.18, 3.62] {
                let eye = SCNNode(geometry: SCNSphere(radius: 0.17))
                let eyeMat = SCNMaterial()
                eyeMat.diffuse.contents = UIColor.white
                eyeMat.emission.contents = UIColor(white: 0.95, alpha: 1)
                eye.geometry?.materials = [eyeMat]
                eye.position = SCNVector3(Float(dx), Float(dy), 0.55)
                node.addChildNode(eye)

                let pupil = SCNNode(geometry: SCNSphere(radius: 0.07))
                let pupilMat = SCNMaterial()
                pupilMat.diffuse.contents = UIColor.black
                pupil.geometry?.materials = [pupilMat]
                pupil.position = SCNVector3(Float(dx), Float(dy), 0.69)
                node.addChildNode(pupil)
            }
        }

        let mouth = LegoBuilder.brick(width: 0.95, height: 0.28, length: 0.12, color: dark)
        mouth.position = SCNVector3(0, 2.95, 0.55)
        node.addChildNode(mouth)
    }
}

// MARK: - Sonnelves

final class Sonnelves: Chaser {

    let node = SCNNode()

    init() { build() }

    private func build() {
        let white = UIColor(white: 0.92, alpha: 1)
        let dark = UIColor(white: 0.1, alpha: 1)
        let glow = UIColor(white: 0.2, alpha: 1)

        for side in [-1.0, 1.0] {
            let leg = LegoBuilder.brick(width: 0.45, height: 1.1, length: 0.55, color: white, emission: glow)
            leg.position = SCNVector3(Float(side) * 0.38, 0.55, 0)
            node.addChildNode(leg)
        }

        let body = LegoBuilder.brick(width: 1.5, height: 1.5, length: 0.95, color: white, emission: glow)
        body.position = SCNVector3(0, 1.85, 0)
        node.addChildNode(body)

        for side in [-1.0, 1.0] {
            let arm = LegoBuilder.brick(width: 0.38, height: 1.4, length: 0.45, color: white, emission: glow)
            arm.position = SCNVector3(Float(side) * 1.0, 1.85, 0)
            node.addChildNode(arm)

            for cx in [-0.12, 0.12] {
                let claw = LegoBuilder.brick(width: 0.1, height: 0.35, length: 0.1, color: dark)
                claw.position = SCNVector3(Float(side) * 1.0 + Float(cx), 1.05, 0.1)
                node.addChildNode(claw)
            }
        }

        let head = LegoBuilder.brick(width: 1.35, height: 1.1, length: 1.0, color: white, emission: glow)
        head.position = SCNVector3(0, 3.15, 0)
        node.addChildNode(head)

        for dx in [-0.33, 0.33] {
            let eye = SCNNode(geometry: SCNSphere(radius: 0.18))
            let eyeMat = SCNMaterial()
            eyeMat.diffuse.contents = UIColor.red
            eyeMat.emission.contents = UIColor(red: 1.0, green: 0.05, blue: 0.05, alpha: 1)
            eye.geometry?.materials = [eyeMat]
            eye.position = SCNVector3(Float(dx), 3.25, 0.52)
            node.addChildNode(eye)
        }

        let mouth = LegoBuilder.brick(width: 0.85, height: 0.3, length: 0.12, color: dark)
        mouth.position = SCNVector3(0, 2.78, 0.52)
        node.addChildNode(mouth)
    }
}
