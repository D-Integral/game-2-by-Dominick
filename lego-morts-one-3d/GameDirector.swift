//
//  GameDirector.swift
//  lego-morts-one-3d
//
//  Objectives (8):
//  1 Collect 20 metals
//  2 Metal house deposit + roads
//  3 Metal room: blue lights → door break → run 30s → close gate
//  4 Run from GOD RED for 2:30
//  5 Carry 3 levers through metal door, place them (Sonnelves waits)
//  6 Escape village with lockers
//  7 Take 2 final levers
//  8 Place levers → elevator in metal house → win
//

import UIKit
import SceneKit
import simd

enum Killer {
    case godRed
    case sonnelves
}

final class GameDirector {

    enum Objective: Int, CaseIterable {
        case collectMetal
        case buildRoads
        case metalRoom
        case escapeRed
        case carryLevers
        case escapeVillage
        case findFinalLevers   // pick up 2 levers
        case elevatorEnd       // place 2 levers → elevator in metal house
        case won
    }

    private enum MetalRoomPhase {
        case goToHole
        case followBlue
        case doorBreaking
        case runThirty
        case closeGate
    }

    private let world: GameWorld

    private(set) var objective: Objective = .collectMetal
    private var metalCarried = 0
    private var metalDeposited = 0
    private let firstMetalGoal = 20
    private let totalMetalGoal = 35

    private var leversCarried = 0
    private var leversPlaced = 0
    private var finalLeversCarried = 0
    private var finalLeversPlaced = 0
    private var passedLeverGate = false

    private(set) var isDead = false
    private var surviveTimer: Float = 0
    private var falling = false
    private var doorBreakStarted = false
    private var broughtToHouse = false
    private var roomPhase: MetalRoomPhase = .goToHole

    private var redChasing = false
    private var sonChasing = false
    private var sonWaiting = false

    private let playerSpeed: Float = 10.0
    private let monsterRunSpeed: Float = 11.5   // monsters RUN
    private let catchRadius: Float = 2.5
    private let pickupRadius: Float = 2.2
    private let goalRadius: Float = 4.5
    private let holeRadius: Float = 2.8
    private let lockerRadius: Float = 2.4
    private let redChaseSeconds: Float = 150    // 2 minutes 30 seconds
    private let roomRunSeconds: Float = 30

    var onObjective: ((String) -> Void)?
    var onHUD: ((String) -> Void)?
    var onMessage: ((String) -> Void)?
    var onDeath: ((Killer) -> Void)?
    var onWin: (() -> Void)?
    var onInteractHint: ((String?) -> Void)?

    private var lastHUD = ""
    private var interactHint: String?

    init(world: GameWorld) {
        self.world = world
    }

    func start() {
        enter(.collectMetal)
    }

    func update(dt: Float, move: SIMD2<Float>) {
        guard !isDead, objective != .won else { return }
        if falling { return }

        if !world.player.isHiding {
            movePlayer(dt: dt, move: move)
        }
        updateMonsters(dt: dt)
        updateObjective(dt: dt)
        updateInteractHint()
        checkCatch()
    }

    private func movePlayer(dt: Float, move: SIMD2<Float>) {
        var delta = world.player.forward * move.y + world.player.right * move.x
        delta.y = 0
        let len = simd_length(delta)
        guard len > 0.001 else { return }
        delta = delta / len * playerSpeed * dt

        var pos = world.player.position
        if !world.isBlocked(x: pos.x + delta.x, z: pos.z) { pos.x += delta.x }
        if !world.isBlocked(x: pos.x, z: pos.z + delta.z) { pos.z += delta.z }
        pos.y = world.inMetalRoom ? world.roomY : 0
        world.player.position = pos
    }

    private func updateMonsters(dt: Float) {
        let y = world.inMetalRoom ? world.roomY : Float(0)
        if redChasing {
            if objective == .metalRoom && roomPhase == .doorBreaking {
                world.godRed.chase(toward: world.breakDoorPos, speed: monsterRunSpeed, dt: dt, keepY: y)
            } else {
                world.godRed.chase(toward: world.player.position, speed: monsterRunSpeed, dt: dt, keepY: y)
            }
            world.godRed.updateWalk(dt: dt)
        } else {
            world.godRed.setRunning(false)
        }

        if sonChasing {
            world.sonnelves.chase(toward: world.player.position, speed: monsterRunSpeed * 1.05, dt: dt, keepY: 0)
            world.sonnelves.updateWalk(dt: dt)
        } else if sonWaiting {
            world.sonnelves.setRunning(false)
            // Start chase if player gets close to the wait spot / Sonnelves.
            if world.sonnelves.groundDistance(to: world.player.position) < 12 {
                sonWaiting = false
                sonChasing = true
                onMessage?("SONNELVES saw you!")
            }
        } else {
            world.sonnelves.setRunning(false)
        }
    }

    private func checkCatch() {
        if world.player.isHiding { return }
        let redBlocked = objective == .metalRoom && roomPhase == .doorBreaking
        if redChasing && !redBlocked &&
            world.godRed.groundDistance(to: world.player.position) < catchRadius {
            die(killedBy: .godRed)
        } else if sonChasing &&
                    world.sonnelves.groundDistance(to: world.player.position) < catchRadius {
            die(killedBy: .sonnelves)
        }
    }

    // MARK: Objectives

    private func updateObjective(dt: Float) {
        switch objective {

        case .collectMetal:
            collectMetals()
            setHUD("Metal: \(metalCarried) / \(firstMetalGoal)")
            if metalCarried >= firstMetalGoal {
                onMessage?("20 metals! Bring them to the metal house.")
                enter(.buildRoads)
            }

        case .buildRoads:
            collectMetals()
            if world.nearDepositHouse(world.player.position) && metalCarried > 0 {
                metalDeposited += metalCarried
                metalCarried = 0
                broughtToHouse = true
                onMessage?("Metal stored! (\(metalDeposited)/\(totalMetalGoal))")
            }
            setHUD("Deposited: \(metalDeposited) / \(totalMetalGoal)   Carried: \(metalCarried)")
            if broughtToHouse && metalDeposited >= totalMetalGoal {
                world.buildRoadsToEveryHouse()
                onMessage?("Roads built to every house!")
                enter(.metalRoom)
            }

        case .metalRoom:
            updateMetalRoom(dt: dt)

        case .escapeRed:
            surviveTimer -= dt
            let m = Int(surviveTimer) / 60
            let s = Int(surviveTimer) % 60
            setHUD(String(format: "GOD RED! Survive %d:%02d", max(0, m), max(0, s)))
            if surviveTimer <= 0 {
                redChasing = false
                world.godRed.park()
                onMessage?("You escaped GOD RED!")
                enter(.carryLevers)
            }

        case .carryLevers:
            // Pick up portable levers.
            for lever in world.portableLevers where !lever.isHidden && lever.opacity > 0.5 {
                if dist(lever.simdPosition) < pickupRadius {
                    lever.isHidden = true
                    leversCarried += 1
                    onMessage?("Lever taken! (\(leversCarried)/3)")
                }
            }

            // Must pass through the metal door while carrying.
            if leversCarried > 0 && dist(world.leverGatePos) < 4 {
                passedLeverGate = true
            }

            // Place levers at the deposit rack.
            if passedLeverGate && leversCarried > 0 && dist(world.leverDepositPos) < 4 {
                leversPlaced += leversCarried
                leversCarried = 0
                onMessage?("Levers placed! (\(leversPlaced)/3)")
            }

            setHUD("Levers carried: \(leversCarried)  placed: \(leversPlaced)/3")
            if leversPlaced >= 3 {
                sonChasing = false
                sonWaiting = false
                world.sonnelves.park()
                world.showLeverCarrySetup(false)
                world.showPortableLevers(false)
                onMessage?("All levers placed!")
                enter(.escapeVillage)
            }

        case .escapeVillage:
            setHUD(world.player.isHiding
                   ? "HIDDEN — tap once to leave"
                   : "Hide in lockers! Escape north!")
            if !world.player.isHiding && reachedGoal(world.exitGoal) {
                redChasing = false
                world.godRed.park()
                onMessage?("Back to the city...")
                enter(.findFinalLevers)
            }

        case .findFinalLevers:
            for lever in world.finalPortableLevers where !lever.isHidden {
                if dist(lever.simdPosition) < pickupRadius {
                    lever.isHidden = true
                    finalLeversCarried += 1
                    onMessage?("Final lever \(finalLeversCarried)/2 taken!")
                }
            }
            setHUD("Final levers carried: \(finalLeversCarried)/2")
            if finalLeversCarried >= 2 {
                enter(.elevatorEnd)
            }

        case .elevatorEnd:
            if finalLeversCarried > 0 && dist(world.finalDepositPos) < 4.5 {
                finalLeversPlaced += finalLeversCarried
                finalLeversCarried = 0
                onMessage?("Levers set in place!")
                world.openElevator()
                showBeam(at: world.elevatorPos)
                onMessage?("The elevator opens in the metal house!")
            }
            setHUD(world.elevatorOpen
                   ? "Enter the elevator in the metal house!"
                   : "Put the 2 levers by the metal house")
            if world.elevatorOpen && dist(world.elevatorPos) < 3.5 {
                win()
            }

        case .won:
            break
        }
    }

    private func updateMetalRoom(dt: Float) {
        switch roomPhase {
        case .goToHole:
            setHUD("Find the hole — follow into the metal room")
            if dist(world.holeCenter) < holeRadius {
                triggerFall()
            }

        case .followBlue:
            setHUD("Follow the BLUE lights!")
            // Start the break once the player has moved toward the blue path / door.
            if world.player.position.x > -6 || dist(world.breakDoorPos) < 6 {
                guard !doorBreakStarted else { break }
                doorBreakStarted = true
                roomPhase = .doorBreaking
                onMessage?("GOD RED is breaking the metal door!")
                setHUD("GOD RED is breaking the door...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self, self.objective == .metalRoom else { return }
                    self.world.breakMetalDoor {
                        self.onMessage?("Door broken! Keep running — 30 seconds!")
                        self.roomPhase = .runThirty
                        self.surviveTimer = self.roomRunSeconds
                    }
                }
            }

        case .doorBreaking:
            setHUD("GOD RED is breaking the door...")

        case .runThirty:
            surviveTimer -= dt
            setHUD("Metal room! Run \(Int(ceil(max(0, surviveTimer))))s")
            if surviveTimer <= 0 {
                roomPhase = .closeGate
                onMessage?("Close the metal gate!")
                showBeam(at: world.exitDoorPos)
            }

        case .closeGate:
            setHUD("Close the metal gate to escape!")
            if dist(world.exitDoorPos) < 3.8 && !world.gateClosed {
                onMessage?("You slam the metal gate!")
                world.closeMetalGate { [weak self] in
                    self?.escapeMetalRoom()
                }
            }
        }
    }

    private func collectMetals() {
        for metal in world.metals where !metal.isHidden {
            if dist(metal.simdPosition) < pickupRadius {
                metal.isHidden = true
                metalCarried += 1
            }
        }
    }

    private func dist(_ pos: SIMD3<Float>) -> Float {
        simd_length(SIMD2<Float>(pos.x - world.player.position.x,
                                 pos.z - world.player.position.z))
    }

    private func reachedGoal(_ goal: SIMD3<Float>) -> Bool {
        dist(goal) < goalRadius
    }

    private func triggerFall() {
        guard !falling else { return }
        falling = true
        world.goalBeam.isHidden = true
        onMessage?("You fall into the hole!")
        world.enterMetalRoom()
        world.resetMetalDoor()
        doorBreakStarted = false
        world.player.fallIntoHole(at: world.metalRoomSpawn, faceYaw: -Float.pi / 2) { [weak self] in
            guard let self else { return }
            self.falling = false
            self.roomPhase = .followBlue
            self.onMessage?("Follow the blue lights... GOD RED is coming!")
            self.world.godRed.spawn(at: SIMD3<Float>(-20, self.world.roomY, 0))
            self.redChasing = true
            self.onObjective?("OBJECTIVE 3/8\nFollow the BLUE lights — then survive GOD RED")
            self.setHUD("Follow the BLUE lights!")
        }
    }

    private func escapeMetalRoom() {
        redChasing = false
        world.godRed.park()
        world.leaveMetalRoom()
        world.player.place(at: world.surfaceAfterRoom, yaw: 0)
        onMessage?("Gate closed — you made it out!")
        enter(.escapeRed)
    }

    // MARK: Interact

    private func updateInteractHint() {
        var hint: String?
        if objective == .escapeVillage {
            if world.player.isHiding {
                hint = "Tap once to leave locker"
            } else if world.nearestLocker(to: world.player.position, within: lockerRadius) != nil {
                hint = "Tap once to hide in locker"
            }
        } else if objective == .metalRoom && roomPhase == .closeGate {
            hint = "Get to the gate and close it"
        } else if objective == .buildRoads && !broughtToHouse {
            hint = "Find the shiny METAL house"
        } else if objective == .carryLevers {
            hint = "Take 3 levers → through metal door → place them (avoid SONNELVES)"
        }
        if hint != interactHint {
            interactHint = hint
            onInteractHint?(hint)
        }
    }

    func tryInteract() {
        guard objective == .escapeVillage else { return }
        if world.player.isHiding {
            world.player.setHidden(false)
            onMessage?("You leave the locker.")
            return
        }
        if let locker = world.nearestLocker(to: world.player.position, within: lockerRadius) {
            world.player.position = SIMD3<Float>(locker.simdPosition.x, 0, locker.simdPosition.z)
            world.player.setHidden(true)
            onMessage?("You hide in the locker...")
        }
    }

    func canTapInteract() -> Bool {
        objective == .escapeVillage &&
        (world.player.isHiding ||
         world.nearestLocker(to: world.player.position, within: lockerRadius) != nil)
    }

    // MARK: Enter

    private func enter(_ next: Objective) {
        objective = next
        lastHUD = ""
        world.goalBeam.isHidden = true

        switch next {
        case .collectMetal:
            onObjective?("OBJECTIVE 1/8\nCollect 20 metals")
            setHUD("Metal: \(metalCarried) / \(firstMetalGoal)")

        case .buildRoads:
            onObjective?("OBJECTIVE 2/8\nBring metal to the METAL house — 35 total")
            setHUD("Deposited: \(metalDeposited) / \(totalMetalGoal)   Carried: \(metalCarried)")
            onMessage?("Look for the shiny metal house!")

        case .metalRoom:
            roomPhase = .goToHole
            doorBreakStarted = false
            onObjective?("OBJECTIVE 3/8\nEnter the hole — follow BLUE lights")
            showBeam(at: world.holeCenter)
            setHUD("Find the hole in the village center")

        case .escapeRed:
            onObjective?("OBJECTIVE 4/8\nRUN from GOD RED — 2:30")
            spawnRedBehindPlayer()
            surviveTimer = redChaseSeconds
            setHUD("GOD RED! Survive 2:30")

        case .carryLevers:
            onObjective?("OBJECTIVE 5/8\nTake 3 levers, go through the metal door, place them\nSONNELVES waits nearby!")
            leversCarried = 0
            leversPlaced = 0
            passedLeverGate = false
            world.restorePortableLevers()
            world.showPortableLevers(true)
            world.showLeverCarrySetup(true)
            world.sonnelves.spawn(at: world.sonnelvesWaitPos)
            sonWaiting = true
            sonChasing = false
            showBeam(at: world.leverDepositPos)
            setHUD("Levers carried: 0  placed: 0/3")

        case .escapeVillage:
            onObjective?("OBJECTIVE 6/8\nEscape! Hide in lockers outside houses")
            spawnRedBehindPlayer()
            showBeam(at: world.exitGoal)
            setHUD("Hide in lockers! Escape north!")

        case .findFinalLevers:
            onObjective?("OBJECTIVE 7/8\nTake 2 levers for the secret elevator")
            finalLeversCarried = 0
            finalLeversPlaced = 0
            world.showFinalPortableLevers(true)
            world.player.place(at: world.spawn, yaw: world.spawnYaw)
            setHUD("Final levers carried: 0/2")

        case .elevatorEnd:
            onObjective?("OBJECTIVE 8/8\nPut 2 levers by the metal house — enter the elevator")
            world.showElevator(true)
            showBeam(at: world.finalDepositPos)
            setHUD("Put the 2 levers by the metal house")

        case .won:
            break
        }
    }

    private func showBeam(at pos: SIMD3<Float>) {
        world.goalBeam.simdPosition = pos
        world.goalBeam.isHidden = false
    }

    private func spawnRedBehindPlayer() {
        let behind = world.player.position - world.player.forward * 16
        let y = world.inMetalRoom ? world.roomY : Float(0)
        world.godRed.spawn(at: SIMD3<Float>(behind.x, y, behind.z))
        redChasing = true
    }

    // MARK: Death / win

    private func die(killedBy: Killer) {
        guard !isDead else { return }
        isDead = true
        redChasing = false
        sonChasing = false
        sonWaiting = false
        falling = false
        doorBreakStarted = false
        metalCarried = 0
        metalDeposited = 0
        broughtToHouse = false
        leversCarried = 0
        leversPlaced = 0
        finalLeversCarried = 0
        finalLeversPlaced = 0
        world.player.setHidden(false)
        world.godRed.setRunning(false)
        world.sonnelves.setRunning(false)
        onDeath?(killedBy)
    }

    func revive() {
        guard isDead else { return }
        isDead = false
        fullReset()
        onMessage?("You revived... but lost everything.")
        enter(.collectMetal)
    }

    private func win() {
        objective = .won
        redChasing = false
        sonChasing = false
        world.godRed.park()
        world.sonnelves.park()
        world.goalBeam.isHidden = true
        world.player.setHidden(false)
        onWin?()
    }

    func restart() {
        isDead = false
        fullReset()
        enter(.collectMetal)
    }

    private func fullReset() {
        metalCarried = 0
        metalDeposited = 0
        broughtToHouse = false
        leversCarried = 0
        leversPlaced = 0
        finalLeversCarried = 0
        finalLeversPlaced = 0
        passedLeverGate = false
        falling = false
        doorBreakStarted = false
        roomPhase = .goToHole
        redChasing = false
        sonChasing = false
        sonWaiting = false
        world.restoreAllMetals()
        world.restorePortableLevers()
        world.showPortableLevers(false)
        world.showFinalPortableLevers(false)
        world.showLeverCarrySetup(false)
        world.resetMetalDoor()
        world.showChoiceDoors(false)
        world.showElevator(false)
        world.clearRoads()
        world.leaveMetalRoom()
        world.godRed.park()
        world.sonnelves.park()
        world.respawnPlayer()
    }

    private func setHUD(_ text: String) {
        if text != lastHUD {
            lastHUD = text
            onHUD?(text)
        }
    }
}
