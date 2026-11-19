//
//  Monsters.swift
//  lego-morts-one-3d
//
//  - DeuxRouge (GOD RED): red, four white eyes. Runs with a stiff LEGO minifig walk.
//  - Sonnelves: white, red eyes. Runs with one broken leg (limp).
//

import UIKit
import SceneKit
import simd

protocol Chaser: AnyObject {
    var node: SCNNode { get }
    func setRunning(_ running: Bool)
}

extension Chaser {
    func chase(toward target: SIMD3<Float>, speed: Float, dt: Float, keepY: Float? = nil) {
        var pos = node.simdPosition
        var dir = target - pos
        dir.y = 0
        let dist = simd_length(dir)
        guard dist > 0.001 else {
            setRunning(false)
            return
        }
        dir /= dist
        pos += dir * speed * dt
        pos.y = keepY ?? pos.y
        node.simdPosition = pos
        node.eulerAngles = SCNVector3(0, atan2(dir.x, dir.z), 0)
        setRunning(true)
    }

    func groundDistance(to point: SIMD3<Float>) -> Float {
        var d = node.simdPosition - point
        d.y = 0
        return simd_length(d)
    }

    func park() {
        setRunning(false)
        node.isHidden = true
        node.simdPosition = SIMD3<Float>(0, -100, 0)
    }

    func spawn(at pos: SIMD3<Float>) {
        node.isHidden = false
        node.simdPosition = pos
        setRunning(false)
    }
}

// MARK: - GOD RED

final class DeuxRouge: Chaser {

    let node = SCNNode()
    private var leftLeg: SCNNode!
    private var rightLeg: SCNNode!
    private var leftArm: SCNNode!
    private var rightArm: SCNNode!
    private var walkTime: Float = 0
    private var isRunning = false

    init() { build() }

    func setRunning(_ running: Bool) {
        isRunning = running
        if !running {
            leftLeg.eulerAngles.x = 0
            rightLeg.eulerAngles.x = 0
            leftArm.eulerAngles.x = 0
            rightArm.eulerAngles.x = 0
        }
    }

    /// Call each frame while chasing to animate the stiff LEGO minifig run.
    func updateWalk(dt: Float) {
        guard isRunning else { return }
        walkTime += dt * 14 // fast run
        let swing = sin(walkTime) * 0.55
        // Opposite legs / arms like a classic minifigure stride.
        leftLeg.eulerAngles.x = swing
        rightLeg.eulerAngles.x = -swing
        leftArm.eulerAngles.x = -swing * 0.8
        rightArm.eulerAngles.x = swing * 0.8
    }

    private func build() {
        let red = UIColor(red: 0.72, green: 0.04, blue: 0.04, alpha: 1)
        let dark = UIColor(red: 0.3, green: 0.0, blue: 0.0, alpha: 1)
        let glow = UIColor(red: 0.22, green: 0.0, blue: 0.0, alpha: 1)

        leftLeg = LegoBuilder.brick(width: 0.5, height: 1.2, length: 0.6, color: red, emission: glow)
        leftLeg.pivot = SCNMatrix4MakeTranslation(0, -0.6, 0)
        leftLeg.position = SCNVector3(-0.4, 1.2, 0)
        node.addChildNode(leftLeg)

        rightLeg = LegoBuilder.brick(width: 0.5, height: 1.2, length: 0.6, color: red, emission: glow)
        rightLeg.pivot = SCNMatrix4MakeTranslation(0, -0.6, 0)
        rightLeg.position = SCNVector3(0.4, 1.2, 0)
        node.addChildNode(rightLeg)

        let body = LegoBuilder.brick(width: 1.7, height: 1.6, length: 1.0, color: red, emission: glow)
        body.position = SCNVector3(0, 2.0, 0)
        node.addChildNode(body)

        leftArm = LegoBuilder.brick(width: 0.4, height: 1.5, length: 0.5, color: red, emission: glow)
        leftArm.pivot = SCNMatrix4MakeTranslation(0, -0.75, 0)
        leftArm.position = SCNVector3(-1.1, 2.75, 0)
        node.addChildNode(leftArm)

        rightArm = LegoBuilder.brick(width: 0.4, height: 1.5, length: 0.5, color: red, emission: glow)
        rightArm.pivot = SCNMatrix4MakeTranslation(0, -0.75, 0)
        rightArm.position = SCNVector3(1.1, 2.75, 0)
        node.addChildNode(rightArm)

        let head = LegoBuilder.brick(width: 1.5, height: 1.2, length: 1.05, color: red, emission: glow)
        head.position = SCNVector3(0, 3.4, 0)
        node.addChildNode(head)

        for dx in [-0.4, 0.4] {
            let s = LegoBuilder.stud(color: red, radius: 0.2, height: 0.14)
            s.position = SCNVector3(Float(dx), 4.07, 0)
            node.addChildNode(s)
        }

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
    private var goodLeg: SCNNode!
    private var brokenLeg: SCNNode!
    private var leftArm: SCNNode!
    private var rightArm: SCNNode!
    private var walkTime: Float = 0
    private var isRunning = false

    init() { build() }

    func setRunning(_ running: Bool) {
        isRunning = running
        if !running {
            goodLeg.eulerAngles.x = 0
            brokenLeg.eulerAngles = SCNVector3(0.35, 0, 0.25) // stays crooked
            leftArm.eulerAngles.x = 0
            rightArm.eulerAngles.x = 0
        }
    }

    /// Limp-run: one healthy leg strides, the broken one drags.
    func updateWalk(dt: Float) {
        guard isRunning else { return }
        walkTime += dt * 11
        let swing = sin(walkTime) * 0.7
        goodLeg.eulerAngles.x = swing
        // Broken leg barely moves and stays twisted.
        brokenLeg.eulerAngles = SCNVector3(0.35 + abs(swing) * 0.15, 0, 0.25)
        leftArm.eulerAngles.x = -swing * 0.5
        rightArm.eulerAngles.x = swing * 0.9
        // Bob the body a little from the limp.
        node.position.y = node.position.y // keep
        let body = node.childNodes.first { $0.name == "body" }
        body?.position.y = 1.85 + abs(sin(walkTime)) * 0.08
    }

    private func build() {
        let white = UIColor(white: 0.92, alpha: 1)
        let dark = UIColor(white: 0.1, alpha: 1)
        let glow = UIColor(white: 0.2, alpha: 1)

        // Healthy leg (right)
        goodLeg = LegoBuilder.brick(width: 0.45, height: 1.1, length: 0.55, color: white, emission: glow)
        goodLeg.pivot = SCNMatrix4MakeTranslation(0, -0.55, 0)
        goodLeg.position = SCNVector3(0.38, 1.1, 0)
        node.addChildNode(goodLeg)

        // Broken leg (left) — shorter, bent, darker tip
        brokenLeg = LegoBuilder.brick(width: 0.4, height: 0.75, length: 0.5, color: white, emission: glow)
        brokenLeg.pivot = SCNMatrix4MakeTranslation(0, -0.35, 0)
        brokenLeg.position = SCNVector3(-0.38, 0.95, 0)
        brokenLeg.eulerAngles = SCNVector3(0.35, 0, 0.25)
        node.addChildNode(brokenLeg)

        let stump = LegoBuilder.brick(width: 0.25, height: 0.3, length: 0.25, color: dark)
        stump.position = SCNVector3(0, -0.55, 0.1)
        brokenLeg.addChildNode(stump)

        let body = LegoBuilder.brick(width: 1.5, height: 1.5, length: 0.95, color: white, emission: glow)
        body.name = "body"
        body.position = SCNVector3(0, 1.85, 0)
        node.addChildNode(body)

        leftArm = LegoBuilder.brick(width: 0.38, height: 1.4, length: 0.45, color: white, emission: glow)
        leftArm.pivot = SCNMatrix4MakeTranslation(0, -0.7, 0)
        leftArm.position = SCNVector3(-1.0, 2.55, 0)
        node.addChildNode(leftArm)

        rightArm = LegoBuilder.brick(width: 0.38, height: 1.4, length: 0.45, color: white, emission: glow)
        rightArm.pivot = SCNMatrix4MakeTranslation(0, -0.7, 0)
        rightArm.position = SCNVector3(1.0, 2.55, 0)
        node.addChildNode(rightArm)

        for side in [-1.0, 1.0] {
            for cx in [-0.12, 0.12] {
                let claw = LegoBuilder.brick(width: 0.1, height: 0.35, length: 0.1, color: dark)
                claw.position = SCNVector3(Float(cx), -0.85, 0.1)
                (side < 0 ? leftArm : rightArm)!.addChildNode(claw)
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

// MARK: - Glytcher

/// Glitchy end-game monster — flickers, jitters, and chases.
final class Glytcher: Chaser {

    let node = SCNNode()
    private var parts: [SCNNode] = []
    private var walkTime: Float = 0
    private var isRunning = false
    private(set) var isFrozen = false
    private(set) var headCut = false
    private var headNode: SCNNode!

    init() { build() }

    func setRunning(_ running: Bool) {
        isRunning = running && !isFrozen
    }

    func updateWalk(dt: Float) {
        guard isRunning, !isFrozen else { return }
        walkTime += dt * 18
        // Glitchy jitter
        for (i, part) in parts.enumerated() {
            let j = sin(walkTime * (1.5 + Float(i) * 0.3)) * 0.08
            part.position.x += j * 0.02
            part.opacity = CGFloat(0.55 + abs(sin(walkTime + Float(i))) * 0.45)
        }
        node.position.y = abs(sin(walkTime * 2)) * 0.15
    }

    func setFrozen(_ frozen: Bool) {
        isFrozen = frozen
        if frozen {
            setRunning(false)
            parts.forEach { $0.opacity = 0.35 }
            node.enumerateChildNodes { n, _ in
                if let mat = n.geometry?.materials.first {
                    mat.emission.contents = UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
                }
            }
        } else {
            parts.forEach { $0.opacity = 1 }
            node.enumerateChildNodes { n, _ in
                if let mat = n.geometry?.materials.first {
                    mat.emission.contents = UIColor(red: 0.4, green: 1.0, blue: 0.3, alpha: 1)
                }
            }
        }
    }

    func cutHead() {
        guard !headCut else { return }
        headCut = true
        headNode.runAction(SCNAction.group([
            SCNAction.moveBy(x: 1.5, y: 2, z: -1, duration: 0.5),
            SCNAction.rotateBy(x: 1, y: 2, z: 0.5, duration: 0.5),
            SCNAction.fadeOut(duration: 0.6)
        ]))
    }

    func resetBoss() {
        headCut = false
        setFrozen(false)
        headNode.removeAllActions()
        headNode.opacity = 1
        headNode.position = SCNVector3(0, 3.5, 0)
        headNode.eulerAngles = SCNVector3Zero
    }

    private func build() {
        let green = UIColor(red: 0.35, green: 1.0, blue: 0.25, alpha: 1)
        let purple = UIColor(red: 0.7, green: 0.2, blue: 1.0, alpha: 1)
        let glow = UIColor(red: 0.4, green: 1.0, blue: 0.3, alpha: 1)

        for i in 0..<5 {
            let bit = LegoBuilder.brick(
                width: CGFloat.random(in: 0.4...1.2),
                height: CGFloat.random(in: 0.3...0.9),
                length: CGFloat.random(in: 0.4...1.0),
                color: i % 2 == 0 ? green : purple,
                emission: glow
            )
            bit.position = SCNVector3(Float.random(in: -0.6...0.6),
                                      Float(i) * 0.55 + 0.4,
                                      Float.random(in: -0.3...0.3))
            bit.eulerAngles = SCNVector3(Float.random(in: -0.4...0.4),
                                         Float.random(in: -0.4...0.4),
                                         Float.random(in: -0.4...0.4))
            node.addChildNode(bit)
            parts.append(bit)
        }

        headNode = LegoBuilder.brick(width: 1.4, height: 1.2, length: 1.2, color: green, emission: glow)
        headNode.position = SCNVector3(0, 3.5, 0)
        node.addChildNode(headNode)

        for dx in [-0.35, 0.35] as [Float] {
            let eye = SCNNode(geometry: SCNSphere(radius: 0.2))
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor.magenta
            mat.emission.contents = UIColor(red: 1, green: 0, blue: 1, alpha: 1)
            eye.geometry?.materials = [mat]
            eye.position = SCNVector3(dx, 0.1, 0.65)
            headNode.addChildNode(eye)
        }
    }
}
