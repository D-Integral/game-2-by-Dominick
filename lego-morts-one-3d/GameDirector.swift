//
//  GameDirector.swift
//  lego-morts-one-3d
//
//  Objectives:
//  1 Collect 20 metals
//  2 Metal house deposit + roads
//  3 Metal room: rock cutscene → 16 km run → 8 km other way → close gate
//  4 Giant house (1000): 3 levers, 10 lockers, Sonnelves, return to little metal room
//  5 Escape village in 2:30 or die
//  6 Final levers
//  7 Elevator end
//

import UIKit
import SceneKit
import simd

enum Killer {
    case godRed
    case sonnelves
    case hole
    case timeout
}

final class GameDirector {

    enum Objective: Int, CaseIterable {
        case collectMetal
        case buildRoads
        case metalRoom
        case giantHouse
        case escapeVillage
        case findFinalLevers
        case elevatorEnd
        case won
        // Kept for older Continue saves
        case escapeRed = 100
    }

    private enum MetalRoomPhase {
        case goToHole
        case rockCutscene
        case followBlue
        case doorBreaking
        case run16km
        case run8km
        case closeGate
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
    private var waitingEscapeDoor = false

    private var finalLeversCarried = 0
    private var finalLeversPlaced = 0

    private(set) var isDead = false
    private var surviveTimer: Float = 0
    private var falling = false
    private var doorBreakStarted = false
    private var broughtToHouse = false
    private var roomPhase: MetalRoomPhase = .goToHole
    private var cutsceneDoorPlayed = false
    private var sonCeilingPlayed = false

    private(set) var redChasing = false
    private var sonChasing = false
    /// Seconds after Red starts chasing before he can catch you (stops instant death).
    private var catchGrace: Float = 0

    private let playerSpeed: Float = 21
    private let redSpeed: Float = 14          // slower than player so you can outrun him
    private let redSpeedMetal: Float = 12     // even slower in the metal hallway
    private let sonSpeed: Float = 16
    private let catchRadius: Float = 2.0
    private let pickupRadius: Float = 2.2
    private let goalRadius: Float = 4.5
    private let holeRadius: Float = 2.8
    private let lockerRadius: Float = 2.4
    private let escapeDeadline: Float = 150 // 2:30

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
        case redTakesRock
        case redBreaksDoor
        case sonnelvesCeiling
        case escapeVillage
    }

    private var lastHUD = ""
    private var interactHint: String?
    private var playingCutscene = false

    init(world: GameWorld) {
        self.world = world
    }

    func start(at objectiveRaw: Int? = nil) {
        isDead = false
        fullReset()
        if let raw = objectiveRaw, let saved = Objective(rawValue: raw), saved != .won {
            let mapped = (saved == .escapeRed) ? .escapeVillage : saved
            restore(to: mapped)
        } else {
            enter(.collectMetal, playWake: true)
        }
    }

    func update(dt: Float, move: SIMD2<Float>) {
        guard !isDead, objective != .won, !playingCutscene else { return }
        if falling { return }

        if catchGrace > 0 {
            catchGrace = max(0, catchGrace - dt)
        }

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
        // Normal camera-relative move. If you're looking AT Red while he chases,
        // flip stick-forward so "forward" still means run AWAY (look back safely).
        var forward = world.player.forward
        var right = world.player.right
        if redChasing && !world.godRed.node.isHidden && catchGrace <= 0 {
            var toRed = world.godRed.node.simdPosition - world.player.position
            toRed.y = 0
            let toRedLen = simd_length(toRed)
            if toRedLen > 0.1 {
                toRed /= toRedLen
                // Looking toward Red → invert so stick-up flees instead of charging him.
                if simd_dot(forward, toRed) > 0.25 {
                    forward = -forward
                    right = -right
                }
            }
        }

        var delta = forward * move.y + right * move.x
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
        if world.forceNoHoles || objective == .giantHouse {
            world.setHazardHolesVisible(false)
            return
        }
        let monstersActive = redChasing || sonChasing
        world.setHazardHolesVisible(!monstersActive && !world.inMetalRoom)
    }

    private func checkHazardDeath() {
        guard !world.inMetalRoom, !world.forceNoHoles else { return }
        if objective == .metalRoom && roomPhase == .goToHole { return }
        if world.hazardHole(at: world.player.position) {
            dieFromHole()
            return
        }
        if objective != .metalRoom || roomPhase != .goToHole {
            if dist(world.holeCenter) < holeRadius * 0.85 {
                dieFromHole()
            }
        }
    }

    private func dieFromHole() {
        guard !isDead, !falling else { return }
        falling = true
        redChasing = false
        sonChasing = false
        onMessage?("You fall... looking up...")
        world.player.lookUpThenDie { [weak self] in
            self?.falling = false
            self?.die(killedBy: .hole)
        }
    }

    private func updateMonsters(dt: Float) {
        let y = world.inMetalRoom ? world.roomY : Float(0)
        if redChasing {
            let speed = world.inMetalRoom ? redSpeedMetal : redSpeed
            if objective == .metalRoom && roomPhase == .doorBreaking {
                world.godRed.chase(toward: world.breakDoorPos, speed: speed, dt: dt, keepY: y)
            } else {
                world.godRed.chase(toward: world.player.position, speed: speed, dt: dt, keepY: y)
            }
            world.godRed.updateWalk(dt: dt)
        } else {
            world.godRed.setRunning(false)
        }

        if sonChasing {
            world.sonnelves.chase(toward: world.player.position, speed: sonSpeed, dt: dt, keepY: 0)
            world.sonnelves.updateWalk(dt: dt)
        } else {
            world.sonnelves.setRunning(false)
        }
    }

    private func checkCatch() {
        if world.player.isHiding { return }
        if catchGrace > 0 { return }

        // In the metal room, Red only kills during the actual run — never at the door smash.
        let metalSafe = objective == .metalRoom &&
            (roomPhase == .goToHole || roomPhase == .rockCutscene ||
             roomPhase == .followBlue || roomPhase == .doorBreaking ||
             world.gateClosed)
        if redChasing && !metalSafe &&
            world.godRed.groundDistance(to: world.player.position) < catchRadius {
            die(killedBy: .godRed)
        } else if sonChasing &&
                    world.sonnelves.groundDistance(to: world.player.position) < catchRadius {
            die(killedBy: .sonnelves)
        }
    }

    /// Start Red behind you with a grace window so you can run away.
    private func beginRedChase(behindDistance: Float = 22) {
        let behind = world.player.position - world.player.forward * behindDistance
        let y = world.inMetalRoom ? world.roomY : Float(0)
        // Prefer spawning toward the hallway entrance when in the metal room.
        if world.inMetalRoom {
            let spawnX = max(1, world.player.position.x - behindDistance)
            world.godRed.spawn(at: SIMD3<Float>(spawnX, y, 0))
        } else {
            world.godRed.spawn(at: SIMD3<Float>(behind.x, y, behind.z))
        }
        redChasing = true
        catchGrace = 5.0
        onMessage?("GOD RED is behind you — RUN!")
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

        case .escapeVillage, .escapeRed:
            surviveTimer -= dt
            let m = Int(max(0, surviveTimer)) / 60
            let s = Int(max(0, surviveTimer)) % 60
            setHUD(world.player.isHiding
                   ? String(format: "HIDDEN  %d:%02d left", m, s)
                   : String(format: "Escape! %d:%02d — hide in lockers!", m, s))
            if surviveTimer <= 0 {
                onMessage?("Time ran out...")
                die(killedBy: .timeout)
                return
            }
            if !world.player.isHiding && reachedGoal(world.exitGoal) {
                redChasing = false
                world.godRed.park()
                onMessage?("You escaped the village!")
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
            setHUD("Find the hole — enter the metal room")
            if dist(world.holeCenter) < holeRadius {
                triggerFall()
            }

        case .rockCutscene:
            break

        case .followBlue:
            setHUD("Follow the BLUE lights to the metal door!")
            if world.player.position.x > 12 || dist(world.breakDoorPos) < 8 {
                guard !doorBreakStarted else { break }
                doorBreakStarted = true
                roomPhase = .doorBreaking
                // Red appears at the door to smash it — he cannot catch you yet.
                world.godRed.spawn(at: world.breakDoorPos)
                redChasing = true
                catchGrace = 99
                playDoorBreakCutsceneThenSmash()
            }

        case .doorBreaking:
            setHUD("GOD RED is breaking the door... get ready to RUN!")

        case .run16km:
            let left = max(0, world.run16km - world.player.position.x)
            let grace = catchGrace > 0 ? "  (safe \(Int(ceil(catchGrace)))s)" : ""
            setHUD(String(format: "RUN! Keep going — %.0f m left%@", left, grace))
            if world.player.position.x >= world.run16km - 3 {
                roomPhase = .run8km
                onMessage?("Turn right — another hallway!")
                showBeam(at: world.exitDoorPos)
            }

        case .run8km:
            let left = max(0, world.run8km - world.player.position.z)
            setHUD(String(format: "RUN the other way!  %.0f m left", left))
            if world.player.position.z >= world.run8km - 3 {
                roomPhase = .closeGate
                onMessage?("Close the metal gate!")
                showBeam(at: world.exitDoorPos)
            }

        case .closeGate:
            setHUD("Close the metal gate!")
            if dist(world.exitDoorPos) < 4.5 && !world.gateClosed {
                onMessage?("You slam the metal gate!")
                var p = world.player.position
                p.z = max(p.z, world.run8km + 2)
                world.player.position = p
                world.closeMetalGate { [weak self] in
                    self?.escapeMetalRoom()
                }
            }
        }
    }

    private func playDoorBreakCutsceneThenSmash() {
        onMessage?("GOD RED is breaking the metal door!")
        let smash = { [weak self] in
            guard let self, self.objective == .metalRoom else { return }
            self.world.breakMetalDoor {
                // Push the player past the door, put Red well behind, then chase.
                var p = self.world.player.position
                p.x = max(p.x, 22)
                self.world.player.position = p
                self.world.player.place(at: p, yaw: -Float.pi / 2) // face down the hall (+X)
                self.roomPhase = .run16km
                self.world.godRed.spawn(at: SIMD3<Float>(max(2, p.x - 28), self.world.roomY, 0))
                self.redChasing = true
                self.catchGrace = 5.0
                self.onMessage?("Door broken! RUN — GOD RED is behind you!")
                self.showBeam(at: self.world.turnJunction)
            }
        }
        if cutsceneDoorPlayed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: smash)
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

        if giantLeversTaken >= 3 {
            waitingEscapeDoor = true
            showBeam(at: world.houseEscapePos)
            setHUD("All levers! Return to the LITTLE METAL ROOM escape door!")
            if world.nearHouseEscape(pos) {
                sonChasing = false
                world.sonnelves.park()
                world.showGiantHouse(false)
                onMessage?("You escape through the little metal room!")
                enter(.escapeVillage)
            }
            return
        }

        var bits: [String] = []
        bits.append(tookLockedLever ? "Room✓" : (world.hasKey ? "Unlock room" : "Find KEY"))
        bits.append(tookTunnelLever ? "Tunnel✓" : "Tunnel")
        bits.append(tookWaterLever ? "Water✓" : "Dive")
        setHUD("Levers \(giantLeversTaken)/3 — " + bits.joined(separator: " · ") + "  |  Hide in lockers!")
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
        roomPhase = .rockCutscene
        playingCutscene = true
        onCutscene?(.redTakesRock) { [weak self] in
            guard let self else { return }
            self.playingCutscene = false
            self.onMessage?("You fall into the hole!")
            self.world.enterMetalRoom()
            self.world.resetMetalDoor()
            self.doorBreakStarted = false
            self.world.player.fallIntoHole(at: self.world.metalRoomSpawn, faceYaw: -Float.pi / 2) {
                self.falling = false
                self.roomPhase = .followBlue
                self.redChasing = false
                self.world.godRed.park()
                self.catchGrace = 0
                self.onMessage?("Follow the blue lights to the metal door...")
                self.onObjective?("OBJECTIVE 3\nFollow BLUE lights — then RUN from GOD RED")
                self.setHUD("Follow the BLUE lights!")
            }
        }
    }

    private func escapeMetalRoom() {
        redChasing = false
        world.godRed.park()
        world.leaveMetalRoom()
        world.player.place(at: world.littleMetalRoomPos, yaw: 0)
        onMessage?("Gate closed — little metal room & gigantic house ahead!")
        enter(.giantHouse)
    }

    // MARK: Interact

    private func updateInteractHint() {
        var hint: String?
        if redChasing && catchGrace <= 0 && !world.player.isHiding {
            hint = "Run away! Look back if you want — keep holding forward"
        } else if catchGrace > 0 && redChasing {
            hint = "GO! You have a head start — run down the hallway!"
        } else if objective == .escapeVillage || objective == .giantHouse {
            if world.player.isHiding {
                hint = "Tap once to leave locker"
            } else if world.nearestLocker(to: world.player.position, within: lockerRadius) != nil {
                hint = "Tap once to hide in locker"
            } else if objective == .giantHouse && waitingEscapeDoor {
                hint = "Return to the little metal room escape door"
            } else if objective == .giantHouse {
                hint = "Take 3 levers — hide from SONNELVES in lockers"
            }
        } else if objective == .metalRoom && roomPhase == .closeGate {
            hint = "Close the metal gate"
        } else if objective == .buildRoads && !broughtToHouse {
            hint = "Find the shiny METAL house"
        }
        if hint != interactHint {
            interactHint = hint
            onInteractHint?(hint)
        }
    }

    func tryInteract() {
        guard objective == .escapeVillage || objective == .giantHouse else { return }
        if world.player.isHiding {
            world.player.setHidden(false)
            onMessage?("You leave the locker.")
            return
        }
        if let locker = world.nearestLocker(to: world.player.position, within: lockerRadius) {
            let w = locker.presentation.worldPosition
            world.player.position = SIMD3<Float>(w.x, 0, w.z)
            world.player.setHidden(true)
            onMessage?("You hide in the locker...")
        }
    }

    func canTapInteract() -> Bool {
        (objective == .escapeVillage || objective == .giantHouse) &&
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
        } else if next == .escapeVillage {
            playingCutscene = true
            onCutscene?(.escapeVillage) { [weak self] in
                self?.playingCutscene = false
                begin()
            }
        } else if next == .giantHouse && !sonCeilingPlayed {
            playingCutscene = true
            onCutscene?(.sonnelvesCeiling) { [weak self] in
                guard let self else { return }
                self.sonCeilingPlayed = true
                self.playingCutscene = false
                begin()
            }
        } else {
            begin()
        }
    }

    private func configure(for next: Objective) {
        switch next {
        case .collectMetal:
            onObjective?("OBJECTIVE 1\nCollect 20 metals")
            setHUD("Metal: \(metalCarried) / \(firstMetalGoal)")

        case .buildRoads:
            onObjective?("OBJECTIVE 2\nBring metal to the METAL house — 35 total")
            setHUD("Deposited: \(metalDeposited) / \(totalMetalGoal)   Carried: \(metalCarried)")
            onMessage?("Look for the shiny metal house!")

        case .metalRoom:
            roomPhase = .goToHole
            doorBreakStarted = false
            onObjective?("OBJECTIVE 3\nEnter the hole — metal room chase")
            showBeam(at: world.holeCenter)
            setHUD("Find the hole in the village center")

        case .giantHouse:
            onObjective?("OBJECTIVE 4\nGiant house — 3 levers, hide from SONNELVES\nThen escape via the little metal room")
            giantLeversTaken = 0
            tookLockedLever = false
            tookTunnelLever = false
            tookWaterLever = false
            waitingEscapeDoor = false
            world.showGiantHouse(true)
            world.player.place(at: world.littleMetalRoomPos, yaw: 0)
            // Sonnelves drops from the ceiling and hunts.
            world.sonnelves.spawn(at: SIMD3<Float>(world.giantHouseOrigin.x,
                                                   40,
                                                   world.giantHouseOrigin.z + 30))
            sonChasing = true
            showBeam(at: SIMD3<Float>(world.giantHouseOrigin.x - 50, 0, world.giantHouseOrigin.z - 100))
            setHUD("Levers 0/3 — Find KEY · Tunnel · Dive  |  Hide!")

        case .escapeVillage, .escapeRed:
            onObjective?("OBJECTIVE 5\nEscape the village in 2:30 — or die")
            world.showGiantHouse(false)
            world.forceNoHoles = false
            world.player.place(at: world.spawn, yaw: world.spawnYaw)
            spawnRedBehindPlayer()
            surviveTimer = escapeDeadline
            showBeam(at: world.exitGoal)
            setHUD("Escape! 2:30 — hide in lockers!")

        case .findFinalLevers:
            onObjective?("OBJECTIVE 6\nTake 2 levers for the secret elevator")
            finalLeversCarried = 0
            finalLeversPlaced = 0
            world.showFinalPortableLevers(true)
            world.player.place(at: world.spawn, yaw: world.spawnYaw)
            setHUD("Final levers carried: 0/2")

        case .elevatorEnd:
            onObjective?("OBJECTIVE 7\nPut 2 levers by the metal house — enter the elevator")
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

        if saved.rawValue >= Objective.buildRoads.rawValue && saved.rawValue < 50 {
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
        beginRedChase(behindDistance: 20)
    }

    // MARK: Death / win

    private func die(killedBy: Killer) {
        guard !isDead else { return }
        isDead = true
        redChasing = false
        sonChasing = false
        falling = false
        doorBreakStarted = false
        catchGrace = 0
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
            waitingEscapeDoor = false
            world.showGiantHouse(true)
            world.player.place(at: world.littleMetalRoomPos, yaw: 0)
            world.sonnelves.spawn(at: SIMD3<Float>(world.giantHouseOrigin.x, 40, world.giantHouseOrigin.z + 30))
            sonChasing = true

        case .escapeVillage, .escapeRed:
            surviveTimer = escapeDeadline
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
        start(at: nil)
    }

    private func fullReset() {
        metalCarried = 0
        metalDeposited = 0
        broughtToHouse = false
        giantLeversTaken = 0
        tookLockedLever = false
        tookTunnelLever = false
        tookWaterLever = false
        waitingEscapeDoor = false
        finalLeversCarried = 0
        finalLeversPlaced = 0
        falling = false
        doorBreakStarted = false
        cutsceneDoorPlayed = false
        sonCeilingPlayed = false
        catchGrace = 0
        roomPhase = .goToHole
        redChasing = false
        sonChasing = false
        world.forceNoHoles = false
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
