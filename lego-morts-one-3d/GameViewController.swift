//
//  GameViewController.swift
//  lego-morts-one-3d
//
//  LEGO MORTS ONE - first-person LEGO horror survival game.
//  Left finger = move. Right finger = look (works while moving).
//  Tap near a locker (or the hint) to hide / leave.
//

import UIKit
import SceneKit
import simd

final class GameViewController: UIViewController {

    private var sceneView: SCNView!
    private var world: GameWorld!
    private var director: GameDirector!

    private var displayLink: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var moveInput = SIMD2<Float>(0, 0)

    // Touch tracking — both fingers can be active at once (move + look).
    private var moveTouch: UITouch?
    private var lookTouch: UITouch?
    private var moveOrigin = CGPoint.zero
    private let joyRadius: CGFloat = 55

    // Short-tap detection for one-tap locker enter/leave.
    private var tapTouch: UITouch?
    private var tapStart = CGPoint.zero

    // UI
    private let objectiveLabel = UILabel()
    private let hudLabel = UILabel()
    private let messageLabel = UILabel()
    private let hintLabel = UILabel()
    private let interactLabel = UILabel()
    private let crosshair = UIView()
    private let joyBase = UIView()
    private let joyKnob = UIView()
    private let deathView = UIView()
    private let deathLabel = UILabel()
    private let jumpscareView = UIView()
    private let jumpscareLabel = UILabel()
    private let winView = UIView()

    private var clearMessageWork: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.isMultipleTouchEnabled = true

        setupScene()
        setupUI()

        // Always touch UIKit on the main thread (SCNAction completions may call these off-main).
        director.onObjective = { [weak self] text in
            Self.onMain { self?.objectiveLabel.text = text }
        }
        director.onHUD = { [weak self] text in
            Self.onMain { self?.hudLabel.text = text }
        }
        director.onMessage = { [weak self] text in
            Self.onMain { self?.showMessage(text) }
        }
        director.onDeath = { [weak self] killer in
            Self.onMain { self?.showJumpscare(killedBy: killer) }
        }
        director.onWin = { [weak self] in
            Self.onMain { self?.showWin() }
        }
        director.onInteractHint = { [weak self] text in
            Self.onMain {
                self?.interactLabel.text = text
                self?.interactLabel.isHidden = (text == nil)
            }
        }

        director.start()
        showMessage("Left = run. Right = look. Collect metal.")

        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    // MARK: Setup

    private func setupScene() {
        let scn = SCNView(frame: view.bounds)
        scn.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scn.backgroundColor = .black
        scn.isPlaying = true
        scn.antialiasingMode = .multisampling2X
        scn.isUserInteractionEnabled = false
        view.addSubview(scn)
        sceneView = scn

        world = GameWorld()
        scn.scene = world.scene
        scn.pointOfView = world.player.cameraNode

        director = GameDirector(world: world)
    }

    private func setupUI() {
        objectiveLabel.font = .systemFont(ofSize: 18, weight: .heavy)
        objectiveLabel.textColor = UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1)
        objectiveLabel.textAlignment = .center
        objectiveLabel.numberOfLines = 0
        styleShadow(objectiveLabel)
        objectiveLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(objectiveLabel)

        hudLabel.font = .systemFont(ofSize: 20, weight: .bold)
        hudLabel.textColor = .white
        hudLabel.textAlignment = .center
        styleShadow(hudLabel)
        hudLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hudLabel)

        messageLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        messageLabel.textColor = UIColor(red: 1.0, green: 0.95, blue: 0.6, alpha: 1)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.alpha = 0
        styleShadow(messageLabel)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(messageLabel)

        hintLabel.text = "Left finger: run   •   Right finger: look (while running)"
        hintLabel.font = .systemFont(ofSize: 12, weight: .medium)
        hintLabel.textColor = UIColor(white: 0.7, alpha: 1)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 2
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintLabel)

        interactLabel.font = .systemFont(ofSize: 16, weight: .bold)
        interactLabel.textColor = UIColor(red: 0.5, green: 1.0, blue: 0.7, alpha: 1)
        interactLabel.textAlignment = .center
        interactLabel.isHidden = true
        styleShadow(interactLabel)
        interactLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(interactLabel)

        crosshair.backgroundColor = UIColor(white: 1, alpha: 0.6)
        crosshair.frame = CGRect(x: 0, y: 0, width: 6, height: 6)
        crosshair.layer.cornerRadius = 3
        view.addSubview(crosshair)

        joyBase.backgroundColor = UIColor(white: 1, alpha: 0.12)
        joyBase.layer.borderColor = UIColor(white: 1, alpha: 0.4).cgColor
        joyBase.layer.borderWidth = 2
        joyBase.frame = CGRect(x: 0, y: 0, width: joyRadius * 2, height: joyRadius * 2)
        joyBase.layer.cornerRadius = joyRadius
        joyBase.isHidden = true
        view.addSubview(joyBase)

        joyKnob.backgroundColor = UIColor(white: 1, alpha: 0.35)
        joyKnob.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
        joyKnob.layer.cornerRadius = 25
        joyKnob.isHidden = true
        view.addSubview(joyKnob)

        // Fullscreen jumpscare flash
        jumpscareView.backgroundColor = .black
        jumpscareView.isHidden = true
        jumpscareView.isUserInteractionEnabled = false
        jumpscareView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(jumpscareView)
        jumpscareLabel.font = .systemFont(ofSize: 34, weight: .black)
        jumpscareLabel.textColor = .red
        jumpscareLabel.textAlignment = .center
        jumpscareLabel.numberOfLines = 0
        jumpscareLabel.translatesAutoresizingMaskIntoConstraints = false
        jumpscareView.addSubview(jumpscareLabel)
        pinCenter(jumpscareLabel, in: jumpscareView)

        deathView.backgroundColor = UIColor(red: 0.35, green: 0, blue: 0, alpha: 0.82)
        deathView.isHidden = true
        deathView.isUserInteractionEnabled = false
        deathView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(deathView)
        deathLabel.text = "YOU DIED\n\nTap to revive\n(you lose all your metal & progress)"
        deathLabel.font = .systemFont(ofSize: 26, weight: .heavy)
        deathLabel.textColor = .white
        deathLabel.textAlignment = .center
        deathLabel.numberOfLines = 0
        deathLabel.translatesAutoresizingMaskIntoConstraints = false
        deathView.addSubview(deathLabel)
        pinCenter(deathLabel, in: deathView)

        winView.backgroundColor = UIColor(red: 0.0, green: 0.2, blue: 0.1, alpha: 0.85)
        winView.isHidden = true
        winView.isUserInteractionEnabled = false
        winView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(winView)
        let winLabel = makeOverlayLabel("YOU ESCAPED!\n\nYou fled the village.\n\nTap to play again")
        winLabel.textColor = UIColor(red: 0.6, green: 1.0, blue: 0.7, alpha: 1)
        winView.addSubview(winLabel)
        pinCenter(winLabel, in: winView)

        NSLayoutConstraint.activate([
            objectiveLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            objectiveLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            objectiveLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            hudLabel.topAnchor.constraint(equalTo: objectiveLabel.bottomAnchor, constant: 8),
            hudLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            messageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            messageLabel.topAnchor.constraint(equalTo: view.centerYAnchor, constant: 70),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            interactLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            interactLabel.bottomAnchor.constraint(equalTo: hintLabel.topAnchor, constant: -10),

            hintLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            jumpscareView.topAnchor.constraint(equalTo: view.topAnchor),
            jumpscareView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            jumpscareView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            jumpscareView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            deathView.topAnchor.constraint(equalTo: view.topAnchor),
            deathView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            deathView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            deathView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            winView.topAnchor.constraint(equalTo: view.topAnchor),
            winView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            winView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            winView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func styleShadow(_ label: UILabel) {
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowRadius = 3
        label.layer.shadowOpacity = 1
        label.layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    private func makeOverlayLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 26, weight: .heavy)
        l.textColor = .white
        l.textAlignment = .center
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    private func pinCenter(_ label: UILabel, in container: UIView) {
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 30),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -30)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        crosshair.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
    }

    // MARK: Game loop

    @objc private func step(_ link: CADisplayLink) {
        if lastTime == 0 { lastTime = link.timestamp; return }
        let dt = Float(min(0.05, link.timestamp - lastTime))
        lastTime = link.timestamp
        director.update(dt: dt, move: moveInput)
    }

    // MARK: UI reactions

    private static func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func showMessage(_ text: String) {
        messageLabel.text = text
        messageLabel.alpha = 1
        clearMessageWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.6) { self?.messageLabel.alpha = 0 }
        }
        clearMessageWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: work)
    }

    private func showJumpscare(killedBy: Killer) {
        resetInput()
        switch killedBy {
        case .godRed:
            jumpscareView.backgroundColor = UIColor(red: 0.55, green: 0, blue: 0, alpha: 1)
            jumpscareLabel.text = "GOD RED\nEATS YOUR HEAD"
            jumpscareLabel.textColor = .white
        case .sonnelves:
            jumpscareView.backgroundColor = UIColor(white: 0.92, alpha: 1)
            jumpscareLabel.text = "SONNELVES\nTAKES YOUR HEART"
            jumpscareLabel.textColor = .red
        }
        jumpscareView.alpha = 0
        jumpscareView.isHidden = false
        UIView.animate(withDuration: 0.08, animations: {
            self.jumpscareView.alpha = 1
        }, completion: { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
                self.jumpscareView.isHidden = true
                self.showDeath()
            }
        })
    }

    private func showDeath() {
        resetInput()
        deathView.isHidden = false
    }

    private func showWin() {
        resetInput()
        winView.isHidden = false
    }

    private func resetInput() {
        moveTouch = nil
        lookTouch = nil
        tapTouch = nil
        moveInput = SIMD2<Float>(0, 0)
        joyBase.isHidden = true
        joyKnob.isHidden = true
    }

    // MARK: Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !deathView.isHidden {
            deathView.isHidden = true
            director.revive()
            return
        }
        if !winView.isHidden {
            winView.isHidden = true
            director.restart()
            return
        }

        for touch in touches {
            let loc = touch.location(in: view)

            // Remember a possible short tap (locker interact). Movement still works.
            if tapTouch == nil {
                tapTouch = touch
                tapStart = loc
            }

            // Left half starts / keeps the move stick.
            if loc.x < view.bounds.midX {
                if moveTouch == nil {
                    moveTouch = touch
                    moveOrigin = loc
                    showJoystick(at: loc)
                } else if lookTouch == nil {
                    lookTouch = touch
                }
            } else {
                if lookTouch == nil {
                    lookTouch = touch
                } else if moveTouch == nil {
                    moveTouch = touch
                    moveOrigin = loc
                    showJoystick(at: loc)
                }
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let loc = touch.location(in: view)
            if touch == moveTouch {
                var offset = CGPoint(x: loc.x - moveOrigin.x, y: loc.y - moveOrigin.y)
                let dist = hypot(offset.x, offset.y)
                if dist > joyRadius {
                    offset.x = offset.x / dist * joyRadius
                    offset.y = offset.y / dist * joyRadius
                }
                joyKnob.center = CGPoint(x: moveOrigin.x + offset.x, y: moveOrigin.y + offset.y)
                moveInput = SIMD2<Float>(Float(offset.x / joyRadius), Float(-offset.y / joyRadius))
            } else if touch == lookTouch {
                let prev = touch.previousLocation(in: view)
                let dx = Float(loc.x - prev.x)
                let dy = Float(loc.y - prev.y)
                world.player.look(dx: dx, dy: dy)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouches(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouches(touches)
    }

    private func endTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            if touch == tapTouch {
                let loc = touch.location(in: view)
                let dist = hypot(loc.x - tapStart.x, loc.y - tapStart.y)
                // One short tap (not a drag) enters / leaves a locker.
                if dist < 18, director.canTapInteract() {
                    director.tryInteract()
                }
                tapTouch = nil
            }
            if touch == moveTouch {
                moveTouch = nil
                moveInput = SIMD2<Float>(0, 0)
                joyBase.isHidden = true
                joyKnob.isHidden = true
            } else if touch == lookTouch {
                lookTouch = nil
            }
        }
    }

    private func showJoystick(at point: CGPoint) {
        joyBase.center = point
        joyKnob.center = point
        joyBase.isHidden = false
        joyKnob.isHidden = false
    }

    override var prefersStatusBarHidden: Bool { true }
}
