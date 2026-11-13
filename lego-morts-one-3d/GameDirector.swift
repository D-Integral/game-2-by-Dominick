//
//  GameDirector.swift
//  lego-morts-one-3d
//
//  Objectives (8):
//  1 Collect 20 metals
//  2 Bring metal to a house, find 15 more (35 total) → build roads (no clues)
//  3 Fall into the hole → metal room, GOD RED chases & breaks a door → run through unbroken door
//  4 Keep running from GOD RED on the surface
//  5 Pull 3 levers → two doors open
//  6 Escape through the green door (red door has SONNELVES)
//  7 Escape through the village — hide in lockers from GOD RED
//  8 Back in the city — pull 2 levers → secret door opens → win
//

import UIKit
import SceneKit
import simd

final class GameDirector {

    enum Objective: Int, CaseIterable {
        case collectMetal
        case buildRoads
        case metalRoom
        case escapeRed
        case levers
        case twoDoors
        case escapeVillage
        case secretEnd
        case won
    }

    private let world: GameWorld

    private(set) var objective: Objective = .collectMetal
    private var metalCarried = 0
    private var metalDeposited = 0
    private let firstMetalGoal = 20
    private let totalMetalGoal = 35
    private var leversPulled = 0
    private var finalLeversPulled = 0
    private(set) var isDead = false
    private var surviveTimer: Float = 0
    private var falling = false
    private var doorBreakStarted = false
    private var broughtToHouse = false

    private var redChasing = false
    private var sonChasing = false

    private let playerSpeed: Float = 10.0
    private let monsterSpeed: Float = 8.0
    private let catchRadius: Float = 2.4
    private let pickupRadius: Float = 2.2
    private let goalRadius: Float = 4.5
    private let leverRadius: Float = 3.2
    private let holeRadius: Float = 2.8
    private let lockerRadius: Float = 2.4
    private let afterDoorRunSeconds: Float = 14

    var onObjective: ((String) -> Void)?
    var onHUD: ((String) -> Void)?
    var onMessage: ((String) -> Void)?
    var onDeath: (() -> Void)?
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

    // MARK: Main loop

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
        if redChasing {
            if objective == .metalRoom && !world.metalDoorBroken {
                // GOD RED goes to smash the closed metal door.
                world.godRed.chase(toward: world.breakDoorPos, speed: monsterSpeed, dt: dt)
            } else {
                world.godRed.chase(toward: world.player.position, speed: monsterSpeed, dt: dt)
            }
        }
        if sonChasing {
            world.sonnelves.chase(toward: world.player.position, speed: monsterSpeed * 1.08, dt: dt)
        }
    }

    private func checkCatch() {
        if world.player.isHiding { return }
        let redBlocked = objective == .metalRoom && !world.metalDoorBroken
        if redChasing && !redBlocked &&
            world.godRed.groundDistance(to: world.player.position) < catchRadius {
            die()
        } else if sonChasing &&
                    world.sonnelves.groundDistance(to: world.player.position) < catchRadius {
            die()
        }
    }

    // MARK: Objectives

    private func updateObjective(dt: Float) {
        switch objective {

        case .collectMetal:
            collectMetals()
            setHUD("Metal: \(metalCarried) / \(firstMetalGoal)")
            if metalCarried >= firstMetalGoal {
                onMessage?("20 metals! Bring them to a house.")
                enter(.buildRoads)
            }

        case .buildRoads:
            collectMetals()
            // No clue beams — find the house yourself.
            if world.nearDepositHouse(world.player.position) && metalCarried > 0 {
                metalDeposited += metalCarried
                metalCarried = 0
                broughtToHouse = true
                onMessage?("Metal stored in the house! (\(metalDeposited)/\(totalMetalGoal))")
            }
            setHUD("Deposited: \(metalDeposited) / \(totalMetalGoal)   Carried: \(metalCarried)")
            if broughtToHouse && metalDeposited >= totalMetalGoal {
                world.buildRoadsToEveryHouse()
                onMessage?("Roads built to every house!")
                enter(.metalRoom)
            }

        case .metalRoom:
            // Still on the surface — wait until the player falls into the hole.
            if !world.inMetalRoom {
                let d = simd_length(SIMD2<Float>(world.player.position.x - world.holeCenter.x,
                                                 world.player.position.z - world.holeCenter.z))
                if d < holeRadius {
                    triggerFall()
                }
                setHUD("Find the hole in the village center")
                break
            }

            if !doorBreakStarted {
                doorBreakStarted = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                    guard let self, self.objective == .metalRoom, self.world.inMetalRoom else { return }
                    self.world.breakMetalDoor {
                        self.onMessage?("GOD RED broke the door! Run to the open metal door!")
                    }
                }
            }
            setHUD(world.metalDoorBroken
                   ? "Run through the unbroken metal door!"
                   : "GOD RED is breaking the door...")

            if world.metalDoorBroken {
                let toExit = simd_length(SIMD2<Float>(world.player.position.x - world.exitDoorPos.x,
                                                      world.player.position.z - world.exitDoorPos.z))
                if toExit < 3.5 {
                    escapeMetalRoom()
                }
            }

        case .escapeRed:
            surviveTimer -= dt
            setHUD("Keep running! \(Int(ceil(max(0, surviveTimer))))s")
            if surviveTimer <= 0 {
                redChasing = false
                world.godRed.park()
                onMessage?("You got away... for now.")
                enter(.levers)
            }

        case .levers:
            for lever in world.levers where !lever.pulled {
                if near(lever.root.simdPosition) {
                    world.pull(lever)
                    leversPulled += 1
                    onMessage?("Lever \(leversPulled) / 3 pulled!")
                }
            }
            setHUD("Levers: \(leversPulled) / 3")
            if leversPulled >= 3 {
                world.showLevers(false)
                onMessage?("Two doors unlocked!")
                enter(.twoDoors)
            }

        case .twoDoors:
            let toMonster = simd_length(SIMD2<Float>(world.player.position.x - world.monsterDoorPos.x,
                                                     world.player.position.z - world.monsterDoorPos.z))
            if toMonster < 5.0 && !sonChasing {
                onMessage?("SONNELVES was behind that door!")
                world.sonnelves.spawn(at: world.monsterDoorPos)
                sonChasing = true
            }

            let toEscape = simd_length(SIMD2<Float>(world.player.position.x - world.escapeDoorPos.x,
                                                    world.player.position.z - world.escapeDoorPos.z))
            if toEscape < 4.0 {
                sonChasing = false
                world.sonnelves.park()
                world.showChoiceDoors(false)
                onMessage?("You escaped SONNELVES!")
                enter(.escapeVillage)
            }
            setHUD(sonChasing
                   ? "Wrong door! Escape through the GREEN light!"
                   : "GREEN door = escape  |  RED door = monster")

        case .escapeVillage:
            setHUD(world.player.isHiding
                   ? "HIDDEN — tap once to leave"
                   : "Hide in lockers outside houses! Escape north!")
            if !world.player.isHiding && reachedGoal(world.exitGoal) {
                redChasing = false
                world.godRed.park()
                onMessage?("You reached the edge... return to the city.")
                enter(.secretEnd)
            }

        case .secretEnd:
            for lever in world.finalLevers where !lever.pulled {
                if near(lever.root.simdPosition) {
                    world.pull(lever)
                    finalLeversPulled += 1
                    onMessage?("Final lever \(finalLeversPulled) / 2!")
                }
            }
            setHUD("Final levers: \(finalLeversPulled) / 2")
            if finalLeversPulled >= 2 && !world.secretDoorOpen {
                world.openSecretDoor()
                onMessage?("A secret door opens!")
                showBeam(at: world.secretDoorPos)
            }
            if world.secretDoorOpen && reachedGoal(world.secretDoorPos) {
                win()
            }

        case .won:
            break
        }
    }

    private func collectMetals() {
        for metal in world.metals where !metal.isHidden {
            let d = simd_length(SIMD2<Float>(metal.simdPosition.x - world.player.position.x,
                                             metal.simdPosition.z - world.player.position.z))
            if d < pickupRadius {
                metal.isHidden = true
                metalCarried += 1
            }
        }
    }

    private func near(_ pos: SIMD3<Float>) -> Bool {
        simd_length(SIMD2<Float>(pos.x - world.player.position.x,
                                 pos.z - world.player.position.z)) < leverRadius
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
            self.onMessage?("Metal room... GOD RED is here!")
            self.world.godRed.spawn(at: SIMD3<Float>(-20, self.world.roomY, 0))
            self.redChasing = true
            self.onObjective?("OBJECTIVE 3/8\nGOD RED chases you — then run through the unbroken door")
            self.setHUD("GOD RED is breaking the door...")
        }
    }

    private func escapeMetalRoom() {
        redChasing = false
        world.godRed.park()
        world.leaveMetalRoom()
        world.player.place(at: world.surfaceAfterRoom, yaw: 0)
        onMessage?("You made it out through the metal door!")
        enter(.escapeRed)
    }

    private func reachedGoal(_ goal: SIMD3<Float>) -> Bool {
        simd_length(SIMD2<Float>(goal.x - world.player.position.x,
                                 goal.z - world.player.position.z)) < goalRadius
    }

    // MARK: Interact (one tap lockers)

    private func updateInteractHint() {
        var hint: String?
        if objective == .escapeVillage {
            if world.player.isHiding {
                hint = "Tap once to leave locker"
            } else if world.nearestLocker(to: world.player.position, within: lockerRadius) != nil {
                hint = "Tap once to hide in locker"
            }
        } else if objective == .buildRoads && !broughtToHouse {
            hint = "Find the shiny METAL house and bring the metal inside"
        }
        if hint != interactHint {
            interactHint = hint
            onInteractHint?(hint)
        }
    }

    /// One tap: enter or leave a locker.
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

    /// True when a single tap should interact (near locker / hiding).
    func canTapInteract() -> Bool {
        objective == .escapeVillage &&
        (world.player.isHiding ||
         world.nearestLocker(to: world.player.position, within: lockerRadius) != nil)
    }

    // MARK: Entering an objective

    private func enter(_ next: Objective) {
        objective = next
        lastHUD = ""
        world.goalBeam.isHidden = true

        // Check for falling into the hole during buildRoads→metalRoom transition is via enter metalRoom from hole.
        // For metalRoom entry from buildRoads, player must still walk to the hole first.
        switch next {
        case .collectMetal:
            onObjective?("OBJECTIVE 1/8\nCollect 20 metals")
            setHUD("Metal: \(metalCarried) / \(firstMetalGoal)")

        case .buildRoads:
            onObjective?("OBJECTIVE 2/8\nBring metal to the METAL house — find 15 more (35 total)\nRoads to every house.")
            setHUD("Deposited: \(metalDeposited) / \(totalMetalGoal)   Carried: \(metalCarried)")
            onMessage?("Look for the shiny metal house!")

        case .metalRoom:
            // If we're not already in the room, this enter is called after fall.
            // When coming from buildRoads, redirect to waiting for the hole.
            if !world.inMetalRoom {
                onObjective?("OBJECTIVE 3/8\nGo into the hole — metal room awaits")
                // Still no beam if user wanted 0 clues for roads — but hole needs a hint for obj 3.
                showBeam(at: world.holeCenter)
                setHUD("Find the hole in the village center")
                // Poll for hole entry via a dedicated state: reuse update by checking hole here.
            } else {
                onObjective?("OBJECTIVE 3/8\nGOD RED chases you — then run through the unbroken door")
                setHUD("GOD RED is breaking the door...")
            }

        case .escapeRed:
            onObjective?("OBJECTIVE 4/8\nKeep running from GOD RED!")
            spawnRedBehindPlayer()
            surviveTimer = afterDoorRunSeconds
            setHUD("Keep running! \(Int(afterDoorRunSeconds))s")

        case .levers:
            onObjective?("OBJECTIVE 5/8\nFind and pull the 3 levers")
            leversPulled = 0
            world.resetLevers()
            world.showLevers(true)
            world.showFinalLevers(false)
            setHUD("Levers: 0 / 3")

        case .twoDoors:
            onObjective?("OBJECTIVE 6/8\nTwo doors open — pick the GREEN escape!")
            world.showChoiceDoors(true)
            showBeam(at: world.escapeDoorPos)
            setHUD("GREEN door = escape  |  RED door = monster")

        case .escapeVillage:
            onObjective?("OBJECTIVE 7/8\nEscape! Hide in lockers outside houses")
            spawnRedBehindPlayer()
            showBeam(at: world.exitGoal)
            setHUD("Hide in lockers outside houses! Escape north!")

        case .secretEnd:
            onObjective?("OBJECTIVE 8/8\nPull 2 levers — open the secret door")
            finalLeversPulled = 0
            world.showFinalLevers(true)
            world.showSecretDoor(true)
            world.player.place(at: world.spawn, yaw: world.spawnYaw)
            setHUD("Final levers: 0 / 2")

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
        let y = world.inMetalRoom ? world.roomY : 0
        world.godRed.spawn(at: SIMD3<Float>(behind.x, y, behind.z))
        redChasing = true
    }

    // MARK: Hole polling while waiting for metal room

    // When objective is metalRoom but not yet inside, detect falling.
    // Hooked from updateObjective start — add to metalRoom case top:

    // Actually handle in update before switch:
    // I'll patch by checking at start of metalRoom case if !inMetalRoom → check hole

    // MARK: Death / revive / win

    private func die() {
        guard !isDead else { return }
        isDead = true
        redChasing = false
        sonChasing = false
        falling = false
        doorBreakStarted = false
        metalCarried = 0
        metalDeposited = 0
        broughtToHouse = false
        leversPulled = 0
        finalLeversPulled = 0
        world.player.setHidden(false)
        onDeath?()
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
        leversPulled = 0
        finalLeversPulled = 0
        falling = false
        doorBreakStarted = false
        redChasing = false
        sonChasing = false
        world.restoreAllMetals()
        world.resetLevers()
        world.showLevers(false)
        world.showFinalLevers(false)
        world.resetMetalDoor()
        world.showChoiceDoors(false)
        world.showSecretDoor(false)
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
