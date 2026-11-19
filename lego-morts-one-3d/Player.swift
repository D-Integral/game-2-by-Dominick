//
//  Player.swift
//  lego-morts-one-3d
//
//  The human you play as. First-person: the camera is your eyes.
//

import UIKit
import SceneKit
import simd

final class Player {

    let node = SCNNode()          // on the ground, turns left/right (yaw)
    let cameraNode = SCNNode()    // your head/eyes, looks up/down (pitch)

    private(set) var yaw: Float = 0
    private(set) var pitch: Float = 0
    let standingEyeHeight: Float = 2.3
    let crouchEyeHeight: Float = 0.95
    var eyeHeight: Float { isCrouching ? crouchEyeHeight : standingEyeHeight }

    private(set) var isCrouching = false
    private(set) var isJumping = false
    private var verticalVelocity: Float = 0
    private let jumpSpeed: Float = 9.5
    private let gravity: Float = 22

    private let lookSensitivity: Float = 0.009
    private let maxPitch: Float = 1.35

    init() {
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zFar = 2500
        cameraNode.camera?.fieldOfView = 75
        cameraNode.position = SCNVector3(0, standingEyeHeight, 0)
        node.addChildNode(cameraNode)

        // Your flashlight: lights up whatever you look at.
        let flash = SCNNode()
        flash.light = SCNLight()
        flash.light?.type = .spot
        flash.light?.color = UIColor(red: 1.0, green: 0.96, blue: 0.85, alpha: 1)
        flash.light?.intensity = 1500
        flash.light?.spotInnerAngle = 30
        flash.light?.spotOuterAngle = 68
        flash.light?.attenuationStartDistance = 1
        flash.light?.attenuationEndDistance = 70
        flash.light?.castsShadow = false
        cameraNode.addChildNode(flash)
    }

    /// Turn the view from a finger drag (in screen points). Works while running.
    func look(dx: Float, dy: Float) {
        // Cancel leftover camera actions so look is never frozen after cutscenes/falls.
        cameraNode.removeAllActions()
        yaw -= dx * lookSensitivity
        pitch += dy * lookSensitivity
        pitch = max(-maxPitch, min(maxPitch, pitch))
        node.eulerAngles = SCNVector3(0, yaw, 0)
        cameraNode.eulerAngles = SCNVector3(pitch, 0, 0)
    }

    func place(at pos: SIMD3<Float>, yaw newYaw: Float) {
        node.simdPosition = pos
        yaw = newYaw
        pitch = 0
        verticalVelocity = 0
        isJumping = false
        setCrouching(false)
        node.eulerAngles = SCNVector3(0, yaw, 0)
        cameraNode.eulerAngles = SCNVector3(0, 0, 0)
        cameraNode.position = SCNVector3(0, eyeHeight, 0)
    }

    func setCrouching(_ crouch: Bool) {
        isCrouching = crouch
        let y = eyeHeight
        cameraNode.removeAllActions()
        cameraNode.runAction(SCNAction.move(to: SCNVector3(0, y, 0), duration: 0.12))
    }

    func toggleCrouch() {
        setCrouching(!isCrouching)
    }

    /// Jump if on the ground (y near floorY).
    @discardableResult
    func jump(floorY: Float = 0) -> Bool {
        guard !isJumping, abs(position.y - floorY) < 0.15 else { return false }
        if isCrouching { setCrouching(false) }
        isJumping = true
        verticalVelocity = jumpSpeed
        return true
    }

    /// Apply gravity / jump arc. Call each frame. Returns current ground Y used.
    func updateVertical(dt: Float, floorY: Float = 0) {
        var pos = position
        if isJumping || pos.y > floorY + 0.01 {
            verticalVelocity -= gravity * dt
            pos.y += verticalVelocity * dt
            if pos.y <= floorY {
                pos.y = floorY
                verticalVelocity = 0
                isJumping = false
            }
            position = pos
        } else {
            pos.y = floorY
            position = pos
            isJumping = false
            verticalVelocity = 0
        }
    }

    var position: SIMD3<Float> {
        get { node.simdPosition }
        set { node.simdPosition = newValue }
    }

    private(set) var isHiding = false

    /// Fall into the hole: camera drops fast, then you land at `landing`.
    func fallIntoHole(at landing: SIMD3<Float>,
                      faceYaw: Float = -Float.pi / 2,
                      completion: @escaping () -> Void) {
        cameraNode.removeAllActions()
        let dip = SCNAction.moveBy(x: 0, y: -6, z: 0, duration: 0.5)
        dip.timingMode = .easeIn
        let recover = SCNAction.run { [weak self] _ in
            guard let self else { return }
            self.node.simdPosition = landing
            self.cameraNode.position = SCNVector3(0, self.eyeHeight, 0)
            self.yaw = faceYaw
            self.pitch = 0
            self.node.eulerAngles.y = self.yaw
            self.cameraNode.eulerAngles.x = 0
        }
        // SCNAction completions can run off the main thread — hop back before UI.
        cameraNode.runAction(SCNAction.sequence([
            dip,
            recover,
            SCNAction.wait(duration: 0.15)
        ])) {
            DispatchQueue.main.async { completion() }
        }
    }

    func setHidden(_ hidden: Bool) {
        isHiding = hidden
        // Dim the flashlight when hiding in a locker.
        cameraNode.childNodes.forEach { child in
            if child.light != nil {
                child.light?.intensity = hidden ? 120 : 1500
            }
        }
    }

    /// Look straight up (e.g. falling into a hole), then call completion.
    func lookUpThenDie(duration: TimeInterval = 1.1, completion: @escaping () -> Void) {
        cameraNode.removeAllActions()
        let look = SCNAction.customAction(duration: duration) { [weak self] _, elapsed in
            guard let self else { return }
            let t = Float(elapsed / CGFloat(duration))
            self.pitch = -self.maxPitch * min(1, t)
            self.cameraNode.eulerAngles.x = self.pitch
        }
        cameraNode.runAction(look) {
            DispatchQueue.main.async { completion() }
        }
    }

    /// Horizontal forward direction (where you are facing).
    var forward: SIMD3<Float> {
        SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
    }

    /// Horizontal right direction.
    var right: SIMD3<Float> {
        SIMD3<Float>(cos(yaw), 0, -sin(yaw))
    }
}
