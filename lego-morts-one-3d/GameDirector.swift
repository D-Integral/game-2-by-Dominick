//
//  GameDirector.swift
//  lego-morts-one-3d
//
//  Objectives (8):
//  1 Collect 20 metals
//  2 Metal house deposit + roads
 //  3 Metal room: blue lights → door break → run 100cm → close gate
//  4 Big square / giant house: 3 levers (key room, tunnel, underwater)
//  5 Run from GOD RED for 2:30
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
    case hole
}

final class GameDirector {

    enum Objective: Int, CaseIterable {
        case collectMetal
        case buildRoads
        case metalRoom
        case giantHouse
        case escapeRed
        case escapeVillage
        case findFinalLevers
        case elevatorEnd
        case won
    }

    private enum MetalRoomPhase {
        case goToHole
        case followBlue
        case doorBreaking
        case runHundred
        case closeGate
        case runPastGate
    }

    private let world: GameWorld

    private(set) var objective: Objective = .collectMetal
    private var metalCarried = 0
    private var metalDeposited = 0
    private let firstMetalGoal = 20
    private let totalMetalGoal = 35

    private var giantLeversTaken = 0
    private var tookLockedLever = false
    private var tookTunnelLever = false
    private var tookWaterLever = false

    private var finalLeversCarried = 0
    private var finalLeversPlaced = 0

    private(set) var isDead = false
    private var surviveTimer: Float = 0
    private var falling = false
    private var doorBreakStarted = false
    private var broughtToHouse = false
    private var roomPhase: MetalRoomPhase = .goToHole
    private var cutsceneDoorPlayed = false

    private var redChasing = false
    private var sonChasing = false

    private let playerSpeed: Float = 10.0
    private let monsterRunSpeed: Float = 11.5
    private let catchRadius: Float = 2.5
    private let pickupRadius: Float = 2.2
    private let goalRadius: Float = 4.5
    private let holeRadius: Float = 2.8
    private let lockerRadius: Float = 2.4
    private let redChaseSeconds: Float = 150

    var onObjective: ((String) -> Void)?
    var onHUD: ((String) -> Void)?
    var onMessage: ((String) -> Void)?
    var onDeath: ((Killer) -> Void)?
    var onWin: (() -> Void)?
    var onInteractHint: ((String?) -> Void)?
    var onCutscene: ((CutsceneKind, @escaping () -> Void) -> Void)?
    var onSaveProgress: ((Int) -> Void)?

    enum CutsceneKind {
        case wakeVillage
        case redFallsHole
        case redBreaksDoor
    }

    private var lastHUD = ""
    private var interactHint: String?
    private var playingCutscene = false

    init(world: GameWorld) {
        self.world = world
    }

    func start(at objectiveRaw: Int? = nil) {
        if let raw = objectiveRaw, let saved = Objective(rawValue: raw), saved != .won {
            restore(to: saved)
        } else {
            enter(.collectMetal, playWake: true)
        }
    }

    func update(dt: Float, move: SIMD2<Float>) {
        guard !isDead, objective != .won, !playingCutscene else { return }
        if falling { return }

        updateHazardVisibility()

        if !world.player.isHiding {
            movePlayer(dt: dt, move: move)
        }
        updateMonsters(dt: dt)
        checkHazardDeath()
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
        if world.inMetalRoom {
            pos.y = world.roomY
        } else if world.isInWater(at: pos) {
            pos.y = -0.6
        } else {
            pos.y = 0
        }
        world.player.position = pos
    }

    private func updateHazardVisibility() {
        let monstersActive = redChasing || sonChasing
        world.setHazardHolesVisible(!monstersActive && !world.inMetalRoom)
    }

    private func checkHazardDeath() {
        guard !world.inMetalRoom else { return }
        // Story hole is used to enter the metal room — don't treat it as lethal then.
        if objective == .metalRoom && roomPhase == .goToHole { return }
        if world.hazardHole(at: world.player.position) {
            die(killedBy: .hole)
            return
        }
        // Falling into the center story hole outside the entry phase also kills.
        if objective != .metalRoom || roomPhase != .goToHole {
            if dist(world.holeCenter) < holeRadius * 0.85 {
                die(killedBy: .hole)
            }
        }
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
        } else {
            world.sonnelves.setRunning(false)
        }
    }

    private func checkCatch() {
        if world.player.isHiding { return }
        let redBlocked = objective == .metalRoom &&
            (roomPhase == .doorBreaking || (world.gateClosed && world.player.position.x > 9))
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

        case .giantHouse:
            updateGiantHouse()

        case .escapeRed:
            surviveTimer -= dt
            let m = Int(surviveTimer) / 60
            let s = Int(surviveTimer) % 60
            setHUD(String(format: "GOD RED! Survive %d:%02d", max(0, m), max(0, s)))
            if surviveTimer <= 0 {
                redChasing = false
                world.godRed.park()
                onMessage?("You escaped GOD RED!")
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
            if world.player.position.x > 2.5 || dist(world.breakDoorPos) < 5 {
                guard !doorBreakStarted else { break }
                doorBreakStarted = true
                roomPhase = .doorBreaking
                playDoorBreakCutsceneThenSmash()
            }

        case .doorBreaking:
            setHUD("GOD RED is breaking the door...")

        case .runHundred:
            setHUD("Door broken! Run another 100cm!")
            // 100cm past the break door (~x 5.0) or reach the post-break mark.
            if world.player.position.x >= 5.0 {
                roomPhase = .closeGate
                onMessage?("Close the metal gate!")
                showBeam(at: world.exitDoorPos)
            }

        case .closeGate:
            setHUD("Close the metal gate to escape!")
            if dist(world.exitDoorPos) < 3.8 && !world.gateClosed {
                onMessage?("You slam the metal gate!")
                // Step past the gate so the seal closes behind you.
                var p = world.player.position
                p.x = max(p.x, 9.3)
                world.player.position = p
                world.closeMetalGate { [weak self] in
                    guard let self else { return }
                    self.roomPhase = .runPastGate
                    self.onMessage?("Run past the gate!")
                    self.showBeam(at: self.world.postGateRunPos)
                }
            }

        case .runPastGate:
            setHUD("Run past the gate!")
            if world.player.position.x >= 10.0 || dist(world.postGateRunPos) < 1.5 {
                escapeMetalRoom()
            }
        }
    }

    private func playDoorBreakCutsceneThenSmash() {
        onMessage?("GOD RED is breaking the metal door!")
        setHUD("GOD RED is breaking the door...")
        let smash = { [weak self] in
            guard let self, self.objective == .metalRoom else { return }
            self.world.breakMetalDoor {
                self.onMessage?("Door broken! Run another 100 centimeters!")
                self.roomPhase = .runHundred
            }
        }
        if cutsceneDoorPlayed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: smash)
        } else {
            cutsceneDoorPlayed = true
            playingCutscene = true
            onCutscene?(.redBreaksDoor) { [weak self] in
                self?.playingCutscene = false
                smash()
            }
        }
    }

    private func updateGiantHouse() {
        let pos = world.player.position

        if world.tryPickupKey(at: pos) {
            onMessage?("You found the KEY!")
        }
        if world.tryUnlockDoor(at: pos) {
            onMessage?("Locked room unlocked!")
        }

        if !tookLockedLever && !world.lockedRoomLever.isHidden && world.lockedDoorOpen {
            let leverWorld = world.lockedRoomLever.presentation.worldPosition
            if dist(SIMD3<Float>(leverWorld.x, 0, leverWorld.z)) < pickupRadius {
                world.lockedRoomLever.isHidden = true
                tookLockedLever = true
                giantLeversTaken += 1
                onMessage?("Locked-room lever! (\(giantLeversTaken)/3)")
            }
        }

        if !tookTunnelLever && !world.tunnelLever.isHidden {
            let leverWorld = world.tunnelLever.presentation.worldPosition
            if dist(SIMD3<Float>(leverWorld.x, 0, leverWorld.z)) < pickupRadius {
                world.tunnelLever.isHidden = true
                tookTunnelLever = true
                giantLeversTaken += 1
                onMessage?("Tunnel lever! (\(giantLeversTaken)/3)")
            }
        }

        if !tookWaterLever && !world.waterLever.isHidden {
            let leverWorld = world.waterLever.presentation.worldPosition
            if dist(SIMD3<Float>(leverWorld.x, 0, leverWorld.z)) < pickupRadius + 0.5 {
                world.waterLever.isHidden = true
                tookWaterLever = true
                giantLeversTaken += 1
                onMessage?("Underwater lever! (\(giantLeversTaken)/3)")
            }
        }

        var bits: [String] = []
        bits.append(tookLockedLever ? "Room✓" : (world.hasKey ? "Room (unlocked?)" : "Find KEY"))
        bits.append(tookTunnelLever ? "Tunnel✓" : "Tunnel")
        bits.append(tookWaterLever ? "Water✓" : "Dive")
        setHUD("Levers \(giantLeversTaken)/3 — " + bits.joined(separator: " · "))

        if giantLeversTaken >= 3 {
            world.showGiantHouse(false)
            onMessage?("All 3 levers taken from the giant house!")
            enter(.escapeRed)
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
        playingCutscene = true
        onCutscene?(.redFallsHole) { [weak self] in
            guard let self else { return }
            self.playingCutscene = false
            self.onMessage?("You fall into the hole!")
            self.world.enterMetalRoom()
            self.world.resetMetalDoor()
            self.doorBreakStarted = false
            self.world.player.fallIntoHole(at: self.world.metalRoomSpawn, faceYaw: -Float.pi / 2) {
                self.falling = false
                self.roomPhase = .followBlue
                self.onMessage?("Follow the blue lights... GOD RED is coming!")
                // Wait behind the closed break door until the smash.
                self.world.godRed.spawn(at: SIMD3<Float>(3.2, self.world.roomY, 0))
                self.redChasing = true
                self.onObjective?("OBJECTIVE 3/8\nFollow the BLUE lights — survive GOD RED")
                self.setHUD("Follow the BLUE lights!")
            }
        }
    }

    private func escapeMetalRoom() {
        redChasing = false
        world.godRed.park()
        world.leaveMetalRoom()
        world.player.place(at: world.bigSquareCenter, yaw: 0)
        onMessage?("You escaped through the gates — a gigantic house ahead!")
        enter(.giantHouse)
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
        } else if objective == .giantHouse {
            if !world.hasKey {
                hint = "Find the key, then the locked room"
            } else if !world.lockedDoorOpen {
                hint = "Unlock the locked room"
            } else {
                hint = "Take levers: locked room, tunnel, underwater"
            }
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

    // MARK: Enter / restore

    private func enter(_ next: Objective, playWake: Bool = false) {
        objective = next
        lastHUD = ""
        world.goalBeam.isHidden = true
        onSaveProgress?(next.rawValue)

        let begin: () -> Void = { [weak self] in
            self?.configure(for: next)
        }

        if playWake {
            playingCutscene = true
            onCutscene?(.wakeVillage) { [weak self] in
                self?.playingCutscene = false
                begin()
            }
        } else {
            begin()
        }
    }

    private func configure(for next: Objective) {
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

        case .giantHouse:
            onObjective?("OBJECTIVE 4/8\nGiant house — take 3 levers\n(key room, tunnel, underwater)")
            giantLeversTaken = 0
            tookLockedLever = false
            tookTunnelLever = false
            tookWaterLever = false
            world.showGiantHouse(true)
            world.player.place(at: world.bigSquareCenter, yaw: Float.pi)
            showBeam(at: SIMD3<Float>(world.giantHouseOrigin.x, 0, world.giantHouseOrigin.z - 20))
            setHUD("Levers 0/3 — Find KEY · Tunnel · Dive")

        case .escapeRed:
            onObjective?("OBJECTIVE 5/8\nRUN from GOD RED — 2:30")
            world.showGiantHouse(false)
            spawnRedBehindPlayer()
            surviveTimer = redChaseSeconds
            setHUD("GOD RED! Survive 2:30")

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

    private func restore(to saved: Objective) {
        world.restoreAllMetals()
        world.showPortableLevers(false)
        world.showFinalPortableLevers(false)
        world.showLeverCarrySetup(false)
        world.showGiantHouse(false)
        world.showElevator(false)
        world.clearRoads()
        world.leaveMetalRoom()
        world.godRed.park()
        world.sonnelves.park()
        world.respawnPlayer()

        // Give enough progress so later objectives are reachable.
        if saved.rawValue >= Objective.buildRoads.rawValue {
            metalCarried = firstMetalGoal
            metalDeposited = totalMetalGoal
            broughtToHouse = true
            world.buildRoadsToEveryHouse()
        }
        enter(saved)
        onMessage?("Continue — back to your objective.")
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

    // MARK: Death / win — revive keeps the same objective

    private func die(killedBy: Killer) {
        guard !isDead else { return }
        isDead = true
        redChasing = false
        sonChasing = false
        falling = false
        doorBreakStarted = false
        world.player.setHidden(false)
        world.godRed.setRunning(false)
        world.sonnelves.setRunning(false)
        onDeath?(killedBy)
    }

    func revive() {
        guard isDead else { return }
        isDead = false
        resetForCurrentObjective()
        onMessage?("You revived — same objective.")
        configure(for: objective)
    }

    private func resetForCurrentObjective() {
        world.player.setHidden(false)
        world.godRed.park()
        world.sonnelves.park()
        redChasing = false
        sonChasing = false
        falling = false
        doorBreakStarted = false
        world.leaveMetalRoom()
        world.resetMetalDoor()
        world.goalBeam.isHidden = true

        switch objective {
        case .collectMetal:
            metalCarried = 0
            world.restoreAllMetals()
            world.respawnPlayer()

        case .buildRoads:
            metalCarried = 0
            world.respawnPlayer()

        case .metalRoom:
            roomPhase = .goToHole
            world.respawnPlayer()
            showBeam(at: world.holeCenter)

        case .giantHouse:
            giantLeversTaken = 0
            tookLockedLever = false
            tookTunnelLever = false
            tookWaterLever = false
            world.showGiantHouse(true)
            world.player.place(at: world.bigSquareCenter, yaw: Float.pi)

        case .escapeRed:
            surviveTimer = redChaseSeconds
            world.player.place(at: world.surfaceAfterRoom, yaw: 0)
            spawnRedBehindPlayer()

        case .escapeVillage:
            world.player.place(at: world.spawn, yaw: world.spawnYaw)
            spawnRedBehindPlayer()
            showBeam(at: world.exitGoal)

        case .findFinalLevers:
            finalLeversCarried = 0
            world.showFinalPortableLevers(true)
            world.player.place(at: world.spawn, yaw: world.spawnYaw)

        case .elevatorEnd:
            world.showElevator(true)
            world.player.place(at: world.depositHouse, yaw: 0)
            showBeam(at: world.finalDepositPos)

        case .won:
            break
        }
    }

    private func win() {
        objective = .won
        redChasing = false
        sonChasing = false
        world.godRed.park()
        world.sonnelves.park()
        world.goalBeam.isHidden = true
        world.player.setHidden(false)
        onSaveProgress?(-1)
        onWin?()
    }

    func restart() {
        isDead = false
        fullReset()
        enter(.collectMetal, playWake: true)
    }

    private func fullReset() {
        metalCarried = 0
        metalDeposited = 0
        broughtToHouse = false
        giantLeversTaken = 0
        tookLockedLever = false
        tookTunnelLever = false
        tookWaterLever = false
        finalLeversCarried = 0
        finalLeversPlaced = 0
        falling = false
        doorBreakStarted = false
        cutsceneDoorPlayed = false
        roomPhase = .goToHole
        redChasing = false
        sonChasing = false
        world.restoreAllMetals()
        world.restorePortableLevers()
        world.showPortableLevers(false)
        world.showFinalPortableLevers(false)
        world.showLeverCarrySetup(false)
        world.showGiantHouse(false)
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
