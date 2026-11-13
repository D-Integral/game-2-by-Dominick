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
    let eyeHeight: Float = 2.3

    private let lookSensitivity: Float = 0.0065
    private let maxPitch: Float = 1.35

    init() {
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zFar = 500
        cameraNode.camera?.fieldOfView = 75
        cameraNode.position = SCNVector3(0, eyeHeight, 0)
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

    /// Turn the view from a finger drag (in screen points).
    func look(dx: Float, dy: Float) {
        yaw -= dx * lookSensitivity
        pitch += dy * lookSensitivity
        pitch = max(-maxPitch, min(maxPitch, pitch))
        node.eulerAngles.y = yaw
        cameraNode.eulerAngles.x = pitch
    }

    func place(at pos: SIMD3<Float>, yaw newYaw: Float) {
        node.simdPosition = pos
        yaw = newYaw
        pitch = 0
        node.eulerAngles.y = yaw
        cameraNode.eulerAngles.x = 0
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

    /// Horizontal forward direction (where you are facing).
    var forward: SIMD3<Float> {
        SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
    }

    /// Horizontal right direction.
    var right: SIMD3<Float> {
        SIMD3<Float>(cos(yaw), 0, -sin(yaw))
    }
}
