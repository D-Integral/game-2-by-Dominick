//
//  GameDirector.swift
//  lego-morts-one-3d
//
//  Objectives:
//  1–5 early game … escape village
//  6 Sonnelves zigzag house (speed 18, crouch/jump)
//  7 Glytcher cave — jump over electrified water ×10
//  8 Glytcher boss — freeze+cut ×4, seal door, elevator win
//

import UIKit
import SceneKit
import simd

enum Killer {
    case godRed
    case sonnelves
    case hole
    case timeout
    case glitch
    case electric
    case glytcher
}

final class GameDirector {

    enum Objective: Int, CaseIterable {
        case collectMetal
        case buildRoads
        case metalRoom
        case giantHouse
        case escapeVillage
        case sonnelvesZigzag
        case glytcherCave
        case glytcherBoss
        case won
        // Kept for older Continue saves
        case escapeRed = 100
        case findFinalLevers = 101
        case elevatorEnd = 102
    }

    private enum MetalRoomPhase {
        case goToHole
        case rockCutscene
        case run16km      // Red from the hole — run 16 km to the metal door
        case doorBreaking  // door at 16 km — Red breaks it
        case run8km        // run another 8 km
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

    private var bossCycles = 0
    private var glytcherFrozen = false
    private var freezeReady = true
    private var awaitingDoorSeal = false

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
    private var glytcherChasing = false
    /// Seconds after Red starts chasing before he can catch you (stops instant death).
    private var catchGrace: Float = 0

    private let playerSpeed: Float = 21
    private let redSpeed: Float = 18
    private let redSpeedMetal: Float = 9
    private let sonSpeed: Float = 16
    private let sonSpeedZigzag: Float = 18
    private let glytcherSpeed: Float = 15
    private let catchRadius: Float = 1.8
    private let catchRadiusMetal: Float = 1.5
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
    var onActionButtons: ((ActionButtons) -> Void)?

    struct ActionButtons {
        var jump = false
        var crouch = false
        var freeze = false
        var cut = false
    }

    enum CutsceneKind {
        case wakeVillage
        case redTakesRock
        case redBreaksDoor
        case sonnelvesCeiling
        case escapeVillage
        case glytcherAppears
        case bossIntro
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
            var mapped = saved
            if saved == .escapeRed { mapped = .escapeVillage }
            if saved == .findFinalLevers || saved == .elevatorEnd { mapped = .sonnelvesZigzag }
            restore(to: mapped)
        } else {
            enter(.collectMetal, playWake: true)
        }
    }

    func tapJump() {
        let floor: Float = world.inMetalRoom ? world.roomY : 0
        _ = world.player.jump(floorY: floor)
    }

    func tapCrouch() {
        world.player.toggleCrouch()
    }

    func tapFreeze() {
        guard objective == .glytcherBoss, freezeReady, !awaitingDoorSeal else { return }
        freezeReady = false
        glytcherFrozen = true
        world.glytcher.setFrozen(true)
        glytcherChasing = false
        onMessage?("GLYTCHER frozen!")
        setActionButtons()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            guard let self, self.objective == .glytcherBoss, !self.awaitingDoorSeal else { return }
            if self.glytcherFrozen {
                self.glytcherFrozen = false
                self.world.glytcher.setFrozen(false)
                self.glytcherChasing = true
                self.onMessage?("GLYTCHER thaws!")
            }
            self.freezeReady = true
            self.setActionButtons()
        }
    }

    func tapCut() {
        guard objective == .glytcherBoss, glytcherFrozen, !awaitingDoorSeal else {
            if objective == .glytcherBoss && !glytcherFrozen {
                onMessage?("Freeze GLYTCHER first!")
            }
            return
        }
        bossCycles += 1
        world.runHeadMachine()
        onMessage?("Cut! (\(bossCycles)/4) — he is still alive...")
        glytcherFrozen = false
        freezeReady = true
        world.glytcher.setFrozen(false)
        if bossCycles >= 4 {
            awaitingDoorSeal = true
            glytcherChasing = false
            world.glytcher.park()
            onMessage?("Now close the metal door OUTSIDE the cave!")
            showBeam(at: world.caveDoorOutsidePos)
            onObjective?("OBJECTIVE 8\nSeal the cave door — then take the elevator")
        } else {
            glytcherChasing = true
            // Respawn a still-living Glytcher body
            world.glytcher.resetBoss()
            world.glytcher.spawn(at: world.bossArenaOrigin)
        }
        setActionButtons()
        setHUD("Freeze + cut GLYTCHER: \(min(bossCycles, 4))/4")
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
        // Camera look is always free (never locked to movement).
        // In the metal hallway chase, stick-forward follows the hall so you can
        // look around (even back at Red) while still running the correct way.
        let forward: SIMD3<Float>
        let right: SIMD3<Float>
        if objective == .metalRoom && world.inMetalRoom &&
            (roomPhase == .run16km || roomPhase == .run8km || roomPhase == .closeGate) {
            let along: SIMD3<Float>
            switch roomPhase {
            case .run8km, .closeGate:
                along = SIMD3<Float>(0, 0, 1)   // second hall after left turn (+Z)
            default:
                along = SIMD3<Float>(1, 0, 0)   // first hall (+X)
            }
            forward = along
            right = SIMD3<Float>(-along.z, 0, along.x)
        } else {
            forward = world.player.forward
            right = world.player.right
        }

        var delta = forward * move.y + right * move.x
        delta.y = 0
        let len = simd_length(delta)
        if len > 0.001 {
            delta = delta / len * playerSpeed * dt
            var pos = world.player.position
            if !world.isBlocked(x: pos.x + delta.x, z: pos.z) { pos.x += delta.x }
            if !world.isBlocked(x: pos.x, z: pos.z + delta.z) { pos.z += delta.z }
            world.player.position = pos
        }

        let floorY: Float
        if world.inMetalRoom {
            floorY = world.roomY
        } else if world.isInWater(at: world.player.position) && world.endAreaActive == .none {
            floorY = -0.6
        } else {
            floorY = 0
        }
        world.player.updateVertical(dt: dt, floorY: floorY)
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
            let speed = objective == .sonnelvesZigzag ? sonSpeedZigzag : sonSpeed
            world.sonnelves.chase(toward: world.player.position, speed: speed, dt: dt, keepY: 0)
            world.sonnelves.updateWalk(dt: dt)
        } else {
            world.sonnelves.setRunning(false)
        }

        if glytcherChasing && !glytcherFrozen {
            world.glytcher.chase(toward: world.player.position, speed: glytcherSpeed, dt: dt, keepY: 0)
            world.glytcher.updateWalk(dt: dt)
        } else {
            world.glytcher.setRunning(false)
        }
    }

    private func checkCatch() {
        if world.player.isHiding { return }
        if catchGrace > 0 { return }

        let metalSafe = objective == .metalRoom &&
            (roomPhase == .goToHole || roomPhase == .rockCutscene ||
             roomPhase == .doorBreaking || world.gateClosed)
        let radius = world.inMetalRoom ? catchRadiusMetal : catchRadius
        if redChasing && !metalSafe &&
            world.godRed.groundDistance(to: world.player.position) < radius {
            die(killedBy: .godRed)
        } else if sonChasing &&
                    world.sonnelves.groundDistance(to: world.player.position) < catchRadius {
            die(killedBy: .sonnelves)
        } else if glytcherChasing && !glytcherFrozen &&
                    world.glytcher.groundDistance(to: world.player.position) < catchRadius {
            die(killedBy: .glytcher)
        }

        // Zigzag glitch floor — must jump over
        if objective == .sonnelvesZigzag && world.inGlitchZone(world.player.position) {
            if world.player.position.y < 0.55 {
                die(killedBy: .glitch)
            }
        }
        // Cave electrified water
        if objective == .glytcherCave && world.inElectrifiedWater(world.player.position) {
            die(killedBy: .electric)
        }
    }

    private func setActionButtons() {
        var buttons = ActionButtons()
        switch objective {
        case .sonnelvesZigzag, .glytcherCave:
            buttons.jump = true
            buttons.crouch = (objective == .sonnelvesZigzag)
        case .glytcherBoss:
            buttons.freeze = !awaitingDoorSeal
            buttons.cut = !awaitingDoorSeal
            buttons.jump = true
        default:
            break
        }
        onActionButtons?(buttons)
    }

    /// Start Red behind you with a grace window so you can run away.
    private func beginRedChase(behindDistance: Float = 28) {
        let behind = world.player.position - world.player.forward * behindDistance
        let y = world.inMetalRoom ? world.roomY : Float(0)
        if world.inMetalRoom {
            let spawnX = max(1, world.player.position.x - behindDistance)
            world.godRed.spawn(at: SIMD3<Float>(spawnX, y, 0))
            catchGrace = 10.0
        } else {
            world.godRed.spawn(at: SIMD3<Float>(behind.x, y, behind.z))
            catchGrace = 6.0
        }
        redChasing = true
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
                onMessage?("You escaped the village — into a house...")
                enter(.sonnelvesZigzag)
            }

        case .sonnelvesZigzag:
            setHUD("SONNELVES (18)! Left/right ×10 — crouch & jump!")
            if world.zigzagExitReached(world.player.position) {
                sonChasing = false
                world.sonnelves.park()
                onMessage?("You escaped SONNELVES — a massive cave ahead...")
                enter(.glytcherCave)
            }

        case .glytcherCave:
            setHUD("GLYTCHER cave — run, jump the gaps ×10!")
            if world.caveExitReached(world.player.position) {
                glytcherChasing = false
                world.glytcher.park()
                onMessage?("Deeper in the cave — the boss fight...")
                enter(.glytcherBoss)
            }

        case .glytcherBoss:
            if awaitingDoorSeal {
                setHUD("Close the cave metal door from OUTSIDE!")
                if !world.caveDoorClosed && world.nearCaveDoorOutside(world.player.position) {
                    onMessage?("You seal the cave door!")
                    world.closeCaveDoor { [weak self] in
                        self?.world.openCaveElevator()
                        self?.showBeam(at: self?.world.caveElevatorWorldPos ?? .zero)
                        self?.onMessage?("Elevator open — escape!")
                        self?.setHUD("Enter the elevator to escape!")
                    }
                }
                if world.caveElevatorOpen && dist(world.caveElevatorWorldPos) < 3.5 {
                    win()
                }
            } else {
                setHUD("Freeze + cut GLYTCHER: \(bossCycles)/4")
            }

        case .findFinalLevers, .elevatorEnd:
            enter(.sonnelvesZigzag)

        case .won:
            break
        }
    }

    private func updateMetalRoom(dt: Float) {
        switch roomPhase {
        case .goToHole:
            setHUD("Find the hole — GOD RED comes from there")
            if dist(world.holeCenter) < holeRadius {
                triggerFall()
            }

        case .rockCutscene:
            break

        case .run16km:
            let leftKm = max(0, world.run16km - world.player.position.x) / 1000
            let grace = catchGrace > 0 ? String(format: "  (head start %.0fs)", catchGrace) : ""
            setHUD(String(format: "RUN 2 km!  %.2f km left%@", leftKm, grace))
            // Reached the metal door at the end of the first hall.
            if world.player.position.x >= world.run16km - 6 {
                guard !doorBreakStarted else { break }
                doorBreakStarted = true
                roomPhase = .doorBreaking
                catchGrace = 99 // safe while he smashes the door
                playDoorBreakCutsceneThenSmash()
            }

        case .doorBreaking:
            setHUD("Metal door! GOD RED is breaking it — then turn LEFT!")

        case .run8km:
            let leftKm = max(0, world.run8km - world.player.position.z) / 1000
            let grace = catchGrace > 0 ? String(format: "  (head start %.0fs)", catchGrace) : ""
            setHUD(String(format: "Turned LEFT — keep running!  %.2f km left%@", leftKm, grace))
            if world.player.position.z >= world.run8km - 5 {
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
        onMessage?("You found the metal door — GOD RED is breaking it!")
        let smash = { [weak self] in
            guard let self, self.objective == .metalRoom else { return }
            self.world.breakMetalDoor {
                // Through the door, turn LEFT into the second hall (+Z).
                var p = self.world.player.position
                p.x = self.world.run16km
                p.z = 10
                // yaw = π → forward is +Z (left turn when you were running +X).
                self.world.player.place(at: p, yaw: Float.pi)
                self.roomPhase = .run8km
                // Keep Red far back in the first hall so he does not eat you at the corner.
                self.world.godRed.spawn(at: SIMD3<Float>(self.world.run16km - 120, self.world.roomY, 0))
                self.redChasing = true
                self.catchGrace = 14.0
                self.onMessage?("Door broken! Turn LEFT and RUN — you have time!")
                self.showBeam(at: self.world.exitDoorPos)
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
                self.roomPhase = .run16km
                // GOD RED climbs out of the hole behind you.
                self.world.godRed.spawn(at: self.world.redHoleSpawn)
                self.redChasing = true
                self.catchGrace = 10.0
                self.onMessage?("GOD RED comes from the hole — RUN 2 kilometers!")
                self.onObjective?("OBJECTIVE 3\nGOD RED from the hole — run 2 km, then turn LEFT")
                self.showBeam(at: self.world.breakDoorPos)
                self.setHUD("RUN 2 km!  2.00 km left")
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
        if objective == .metalRoom && roomPhase == .run8km {
            hint = "You turned LEFT — keep running forward"
        } else if redChasing && catchGrace <= 0 && !world.player.isHiding {
            hint = "Hold forward to run — right finger looks around"
        } else if catchGrace > 0 && redChasing {
            hint = "GO! Head start — hold forward down the hall"
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
        } else if objective == .sonnelvesZigzag {
            if world.inCrouchZone(world.player.position) {
                hint = "CROUCH — Sonnelves broke the wall!"
            } else if world.inGlitchZone(world.player.position) {
                hint = "JUMP over the glitch particles!"
            } else {
                hint = "Zigzag left/right — Jump & Crouch buttons"
            }
        } else if objective == .glytcherCave {
            hint = "Run the pads — JUMP the water gaps!"
        } else if objective == .glytcherBoss {
            hint = awaitingDoorSeal
                ? "Seal the door outside, then elevator"
                : "Freeze button, then Cut button (×4)"
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
        } else if next == .glytcherCave {
            playingCutscene = true
            onCutscene?(.glytcherAppears) { [weak self] in
                self?.playingCutscene = false
                begin()
            }
        } else if next == .glytcherBoss {
            playingCutscene = true
            onCutscene?(.bossIntro) { [weak self] in
                self?.playingCutscene = false
                begin()
            }
        } else {
            begin()
        }
    }

    private func configure(for next: Objective) {
        world.showEndArea(.none)
        glytcherChasing = false
        setActionButtons()

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
            onObjective?("OBJECTIVE 3\nEnter the hole — run 2 km, metal door, turn LEFT")
            showBeam(at: world.holeCenter)
            setHUD("Find the hole — GOD RED comes from there")

        case .giantHouse:
            onObjective?("OBJECTIVE 4\nGiant house — 3 levers, hide from SONNELVES\nThen escape via the little metal room")
            giantLeversTaken = 0
            tookLockedLever = false
            tookTunnelLever = false
            tookWaterLever = false
            waitingEscapeDoor = false
            world.showGiantHouse(true)
            world.player.place(at: world.littleMetalRoomPos, yaw: 0)
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

        case .sonnelvesZigzag:
            onObjective?("OBJECTIVE 6\nHouse chase — SONNELVES speed 18\nLeft/right ×10 — crouch & jump!")
            world.showGiantHouse(false)
            world.showEndArea(.zigzag)
            world.player.place(at: world.zigzagOrigin, yaw: Float.pi)
            world.sonnelves.spawn(at: SIMD3<Float>(world.zigzagOrigin.x,
                                                   0,
                                                   world.zigzagOrigin.z + 12))
            sonChasing = true
            catchGrace = 3
            showBeam(at: world.zigzagEndPos)
            setActionButtons()
            setHUD("SONNELVES! Zigzag — crouch low, jump glitch floors!")

        case .glytcherCave:
            onObjective?("OBJECTIVE 7\nGLYTCHER cave — run, then jump ×10\nWater gaps kill!")
            world.showEndArea(.cave)
            if let first = world.cavePlatforms.first {
                world.player.place(at: first, yaw: Float.pi)
            }
            world.glytcher.resetBoss()
            world.glytcher.spawn(at: SIMD3<Float>(world.caveOrigin.x + 8, 0, world.caveOrigin.z - 20))
            glytcherChasing = true
            catchGrace = 4
            if let last = world.cavePlatforms.last { showBeam(at: last) }
            setActionButtons()
            setHUD("Run → JUMP the water gaps ×10!")

        case .glytcherBoss:
            onObjective?("OBJECTIVE 8\nBOSS — freeze & cut GLYTCHER 4 times\nThen seal the door & elevator")
            world.showEndArea(.boss)
            bossCycles = 0
            awaitingDoorSeal = false
            glytcherFrozen = false
            freezeReady = true
            world.resetBossArenaState()
            world.player.place(at: SIMD3<Float>(world.bossArenaOrigin.x,
                                                0,
                                                world.bossArenaOrigin.z + 10), yaw: Float.pi)
            world.glytcher.spawn(at: world.bossArenaOrigin)
            glytcherChasing = true
            catchGrace = 3
            setActionButtons()
            setHUD("Freeze + cut GLYTCHER: 0/4")

        case .findFinalLevers, .elevatorEnd:
            configure(for: .sonnelvesZigzag)

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
        world.showEndArea(.none)
        world.clearRoads()
        world.leaveMetalRoom()
        world.godRed.park()
        world.sonnelves.park()
        world.glytcher.park()
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
        glytcherChasing = false
        falling = false
        doorBreakStarted = false
        catchGrace = 0
        world.player.setHidden(false)
        world.godRed.setRunning(false)
        world.sonnelves.setRunning(false)
        world.glytcher.setRunning(false)
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
        world.glytcher.park()
        redChasing = false
        sonChasing = false
        glytcherChasing = false
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

        case .sonnelvesZigzag, .glytcherCave, .glytcherBoss, .findFinalLevers, .elevatorEnd:
            // configure() re-places the player for these
            break

        case .won:
            break
        }
    }

    private func win() {
        objective = .won
        redChasing = false
        sonChasing = false
        glytcherChasing = false
        world.godRed.park()
        world.sonnelves.park()
        world.glytcher.park()
        world.goalBeam.isHidden = true
        world.player.setHidden(false)
        onSaveProgress?(-1)
        onActionButtons?(ActionButtons())
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
        bossCycles = 0
        awaitingDoorSeal = false
        glytcherFrozen = false
        freezeReady = true
        falling = false
        doorBreakStarted = false
        cutsceneDoorPlayed = false
        sonCeilingPlayed = false
        catchGrace = 0
        roomPhase = .goToHole
        redChasing = false
        sonChasing = false
        glytcherChasing = false
        world.forceNoHoles = false
        world.restoreAllMetals()
        world.restorePortableLevers()
        world.showPortableLevers(false)
        world.showFinalPortableLevers(false)
        world.showLeverCarrySetup(false)
        world.showGiantHouse(false)
        world.showEndArea(.none)
        world.resetMetalDoor()
        world.showChoiceDoors(false)
        world.showElevator(false)
        world.clearRoads()
        world.leaveMetalRoom()
        world.godRed.park()
        world.sonnelves.park()
        world.glytcher.park()
        world.respawnPlayer()
    }

    private func setHUD(_ text: String) {
        if text != lastHUD {
            lastHUD = text
            onHUD?(text)
        }
    }
}
