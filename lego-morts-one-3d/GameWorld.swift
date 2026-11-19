//
//  GameWorld.swift
//  lego-morts-one-3d
//
//  The big spooky LEGO village you run around in.
//

import UIKit
import SceneKit
import simd

final class GameWorld {

    let scene = SCNScene()
    let player = Player()
    let godRed = DeuxRouge()
    let sonnelves = Sonnelves()

    private(set) var metals: [SCNNode] = []
    private(set) var housePositions: [SIMD3<Float>] = []

    let holeNode = Props.hole()
    private(set) var metalDoorRoot = SCNNode()         // breakable door in metal room
    private(set) var metalDoorPanel = SCNNode()
    private(set) var exitMetalDoorRoot = SCNNode()     // closable metal gate
    private(set) var exitMetalDoorPanel = SCNNode()
    private(set) var escapeDoorRoot = SCNNode()
    private(set) var escapeDoorPanel = SCNNode()
    private(set) var monsterDoorRoot = SCNNode()
    private(set) var monsterDoorPanel = SCNNode()
    private(set) var lockers: [SCNNode] = []
    private let roadsRoot = SCNNode()
    private let metalRoomRoot = SCNNode()
    private let bloodRoot = SCNNode()

    let goalBeam = Props.goalBeam(color: UIColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1))

    private var houseRects: [(cx: Float, cz: Float, half: Float)] = []
    private let bound: Float = 90

    // Key locations (surface)
    let spawn = SIMD3<Float>(0, 0, 78)
    let spawnYaw: Float = 0
    let depositHouse = SIMD3<Float>(-14, 0, 42)        // metal house near spawn (easy to find)
    let holeCenter = SIMD3<Float>(0, 0, 0)
    let escapeDoorPos = SIMD3<Float>(-22, 0, -55)
    let monsterDoorPos = SIMD3<Float>(22, 0, -55)
    let exitGoal = SIMD3<Float>(0, 0, -84)
    let surfaceAfterRoom = SIMD3<Float>(18, 0, 8)
    let portableLeverSpots = [SIMD3<Float>(-50, 0, 20),
                              SIMD3<Float>(55, 0, -5),
                              SIMD3<Float>(-25, 0, -45)]
    let finalPortableLeverSpots = [SIMD3<Float>(-30, 0, 55),
                                   SIMD3<Float>(25, 0, 60)]

    // Metal room: Red from the hole → run 2 km → metal door → turn left → short final hall → gate.
    let roomY: Float = -14
    let run16km: Float = 2_000   // first hall (2 km)
    let run8km: Float = 400      // short left hall after the door (easy to finish)
    let hallwayWidth: Float = 5
    var metalRoomSpawn: SIMD3<Float> { SIMD3<Float>(8, roomY, 0) }
    /// Hole entrance behind you — where GOD RED climbs out.
    var redHoleSpawn: SIMD3<Float> { SIMD3<Float>(1.5, roomY, 0) }
    /// Metal door at the end of the first 16 km.
    var breakDoorPos: SIMD3<Float> { SIMD3<Float>(run16km, roomY, 0) }
    var turnJunction: SIMD3<Float> { SIMD3<Float>(run16km, roomY, 0) }
    var exitDoorPos: SIMD3<Float> { SIMD3<Float>(run16km, roomY, run8km) } // metal gate after 8 km
    var postGateRunPos: SIMD3<Float> { SIMD3<Float>(run16km, roomY, run8km + 8) }

    // Little metal room + giant house (1000 long × 1000 high)
    let bigSquareCenter = SIMD3<Float>(0, 0, -40)
    let littleMetalRoomPos = SIMD3<Float>(0, 0, -40)
    let giantHouseOrigin = SIMD3<Float>(0, 0, -40)
    let giantHouseSize: Float = 1000
    let giantHouseHeight: Float = 1000
    private(set) var hasKey = false
    private(set) var lockedDoorOpen = false
    var keyNode = SCNNode()
    var lockedRoomDoor = SCNNode()
    var lockedRoomLever = SCNNode()
    var tunnelLever = SCNNode()
    var waterLever = SCNNode()
    var houseEscapeDoor = SCNNode()
    var houseEscapePos: SIMD3<Float> { SIMD3<Float>(giantHouseOrigin.x, 0, giantHouseOrigin.z - 10) }
    private(set) var houseLockers: [SCNNode] = []
    private var houseWallRects: [(cx: Float, cz: Float, hw: Float, hd: Float)] = []
    private var hazardHoles: [SIMD3<Float>] = []
    private let hazardRoot = SCNNode()
    var holesEnabled = true
    var forceNoHoles = false

    private(set) var metalDoorClosed = true
    private(set) var metalDoorBroken = false
    private(set) var gateClosed = false
    private(set) var choiceDoorsOpen = false
    private(set) var elevatorOpen = false
    private(set) var inMetalRoom = false
    private(set) var roadsBuilt = false

    // Portable levers (pick up / carry / place)
    private(set) var portableLevers: [SCNNode] = []
    private(set) var finalPortableLevers: [SCNNode] = []
    let leverDepositPos = SIMD3<Float>(40, 0, -20)
    let leverGatePos = SIMD3<Float>(28, 0, -20)       // metal door you carry levers through
    let sonnelvesWaitPos = SIMD3<Float>(34, 0, -8)    // where Sonnelves waits
    private(set) var leverGateRoot = SCNNode()
    private(set) var leverDepositRoot = SCNNode()
    private(set) var elevatorRoot = SCNNode()
    private var finalDepositSlots: SCNNode?

    init() {
        setupEnvironment()
        buildVillage()
        placeStreetLamps()
        placeBlood()
        placeMetals()
        placeHoleAndDoors()
        buildMetalRoom()
        placeLockers()
        placeLeverCarrySetup()
        placeElevatorInMetalHouse()
        placePortableLevers()
        placeFinalPortableLevers()
        buildGiantHouse()
        placeHazardHoles()

        scene.rootNode.addChildNode(roadsRoot)

        player.place(at: spawn, yaw: spawnYaw)
        scene.rootNode.addChildNode(player.node)

        godRed.park()
        sonnelves.park()
        scene.rootNode.addChildNode(godRed.node)
        scene.rootNode.addChildNode(sonnelves.node)

        goalBeam.isHidden = true
        scene.rootNode.addChildNode(goalBeam)
    }

    // MARK: Environment

    private func setupEnvironment() {
        let night = UIColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1)
        scene.background.contents = night
        scene.fogColor = night
        scene.fogStartDistance = 40
        scene.fogEndDistance = 280
        scene.fogDensityExponent = 1.1

        let floor = SCNFloor()
        floor.reflectivity = 0
        let floorMat = SCNMaterial()
        floorMat.diffuse.contents = UIColor(white: 0.08, alpha: 1)
        floor.materials = [floorMat]
        scene.rootNode.addChildNode(SCNNode(geometry: floor))

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(red: 0.12, green: 0.13, blue: 0.22, alpha: 1)
        ambient.light?.intensity = 240
        scene.rootNode.addChildNode(ambient)

        let moon = SCNNode(geometry: SCNSphere(radius: 5))
        let moonMat = SCNMaterial()
        moonMat.diffuse.contents = UIColor(white: 0.9, alpha: 1)
        moonMat.emission.contents = UIColor(white: 0.85, alpha: 1)
        moon.geometry?.materials = [moonMat]
        moon.position = SCNVector3(-50, 60, -90)
        scene.rootNode.addChildNode(moon)

        let moonLight = SCNNode()
        moonLight.light = SCNLight()
        moonLight.light?.type = .directional
        moonLight.light?.color = UIColor(red: 0.5, green: 0.6, blue: 0.9, alpha: 1)
        moonLight.light?.intensity = 420
        moonLight.light?.castsShadow = true
        moonLight.light?.shadowMode = .deferred
        moonLight.light?.shadowColor = UIColor(white: 0, alpha: 0.55)
        moonLight.eulerAngles = SCNVector3(-Float.pi / 3.5, -Float.pi / 5, 0)
        scene.rootNode.addChildNode(moonLight)
    }

    // MARK: Village

    private func buildVillage() {
        let bodyColors = [
            UIColor(red: 0.55, green: 0.12, blue: 0.12, alpha: 1),
            UIColor(red: 0.12, green: 0.2, blue: 0.4, alpha: 1),
            UIColor(red: 0.45, green: 0.4, blue: 0.12, alpha: 1),
            UIColor(red: 0.2, green: 0.35, blue: 0.2, alpha: 1),
            UIColor(red: 0.4, green: 0.25, blue: 0.1, alpha: 1),
            UIColor(red: 0.35, green: 0.15, blue: 0.35, alpha: 1)
        ]
        let roofColors = [
            UIColor(red: 0.25, green: 0.08, blue: 0.08, alpha: 1),
            UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1),
            UIColor(red: 0.2, green: 0.15, blue: 0.1, alpha: 1),
            UIColor(red: 0.15, green: 0.18, blue: 0.12, alpha: 1)
        ]

        let spacing: Float = 14
        var i = 0

        func addHouse(x: Float, z: Float) {
            let isDeposit = abs(x - depositHouse.x) < 1 && abs(z - depositHouse.z) < 1
            let house = LegoBuilder.house(
                bodyColor: bodyColors[i % bodyColors.count],
                roofColor: roofColors[i % roofColors.count],
                metallic: isDeposit   // objective 2 house = shiny metal, easy to spot
            )
            house.position = SCNVector3(x, 0, z)
            // Metal house faces the main street so you see it coming from spawn.
            house.eulerAngles = SCNVector3(0, isDeposit ? Float.pi : Float.pi / 2 * Float(i % 4), 0)
            scene.rootNode.addChildNode(house)
            houseRects.append((cx: x, cz: z, half: 2.1))
            housePositions.append(SIMD3<Float>(x, 0, z))
            i += 1
        }

        // Force the deposit house to exist.
        addHouse(x: depositHouse.x, z: depositHouse.z)

        for gx in -5...5 {
            for gz in -5...5 {
                if gx == 0 || gz == 0 { continue }
                if abs(gx) == 1 && abs(gz) == 1 { continue }
                let x = Float(gx) * spacing
                let z = Float(gz) * spacing
                if abs(x - depositHouse.x) < 1 && abs(z - depositHouse.z) < 1 { continue }
                addHouse(x: x, z: z)
            }
        }

        for gx in [-6, 6] {
            for gz in stride(from: -5, through: 5, by: 2) {
                addHouse(x: Float(gx) * spacing, z: Float(gz) * spacing)
            }
        }
        for gz in [-6, 6] {
            for gx in stride(from: -4, through: 4, by: 2) {
                addHouse(x: Float(gx) * spacing, z: Float(gz) * spacing)
            }
        }

        let corpseSpots = [
            SIMD3<Float>(6, 0, 60), SIMD3<Float>(-60, 0, 6),
            SIMD3<Float>(60, 0, -6), SIMD3<Float>(-6, 0, -60),
            SIMD3<Float>(28, 0, 28), SIMD3<Float>(-28, 0, -28)
        ]
        let shirts = [
            UIColor(red: 0.2, green: 0.45, blue: 0.85, alpha: 1),
            UIColor(red: 0.85, green: 0.5, blue: 0.15, alpha: 1),
            UIColor(red: 0.2, green: 0.6, blue: 0.35, alpha: 1),
            UIColor(red: 0.6, green: 0.25, blue: 0.6, alpha: 1)
        ]
        for (index, spot) in corpseSpots.enumerated() {
            let person = Person(slot: SCNVector3(spot.x, spot.y, spot.z), shirt: shirts[index % shirts.count])
            scene.rootNode.addChildNode(person.node)
            person.die()
        }
    }

    private func placeStreetLamps() {
        let spots: [SIMD3<Float>] = [
            SIMD3<Float>(0, 0, 70), SIMD3<Float>(0, 0, 40), SIMD3<Float>(0, 0, 14),
            SIMD3<Float>(0, 0, -14), SIMD3<Float>(0, 0, -40), SIMD3<Float>(0, 0, -70),
            SIMD3<Float>(40, 0, 0), SIMD3<Float>(-40, 0, 0),
            SIMD3<Float>(70, 0, 0), SIMD3<Float>(-70, 0, 0)
        ]
        for spot in spots {
            scene.rootNode.addChildNode(Props.streetLamp(at: spot))
        }
    }

    private func placeBlood() {
        scene.rootNode.addChildNode(bloodRoot)
        let spots: [SIMD3<Float>] = [
            SIMD3<Float>(2, 0, 50), SIMD3<Float>(-3, 0, 35), SIMD3<Float>(4, 0, 18),
            SIMD3<Float>(-5, 0, 5), SIMD3<Float>(8, 0, -20), SIMD3<Float>(-6, 0, -35),
            SIMD3<Float>(12, 0, 8), SIMD3<Float>(-18, 0, 22), SIMD3<Float>(25, 0, -10),
            SIMD3<Float>(-30, 0, -5), SIMD3<Float>(0, 0, -50), SIMD3<Float>(15, 0, 40),
            SIMD3<Float>(-12, 0, 60), SIMD3<Float>(20, 0, -45), SIMD3<Float>(-22, 0, 12)
        ]
        for spot in spots {
            let stain = Props.bloodStain(scale: Float.random(in: 0.7...1.6))
            stain.simdPosition = spot
            bloodRoot.addChildNode(stain)
        }
    }

    // MARK: Roads

    func buildRoadsToEveryHouse() {
        guard !roadsBuilt else { return }
        roadsBuilt = true
        roadsRoot.childNodes.forEach { $0.removeFromParentNode() }

        // Roads from deposit house to every house.
        for house in housePositions {
            if abs(house.x - depositHouse.x) < 1 && abs(house.z - depositHouse.z) < 1 { continue }
            // Route via the cross streets (to deposit → axis → house) so roads look like streets.
            let mid = SIMD3<Float>(depositHouse.x, 0, house.z)
            roadsRoot.addChildNode(Props.road(from: depositHouse, to: mid))
            roadsRoot.addChildNode(Props.road(from: mid, to: house))
        }
    }

    func clearRoads() {
        roadsBuilt = false
        roadsRoot.childNodes.forEach { $0.removeFromParentNode() }
    }

    // MARK: Metal room

    private func buildMetalRoom() {
        // L-shaped mega hallway: 16 km along +X, then 8 km along +Z.
        metalRoomRoot.simdPosition = SIMD3<Float>(0, roomY, 0)
        metalRoomRoot.isHidden = true
        scene.rootNode.addChildNode(metalRoomRoot)

        let metal = UIColor(white: 0.35, alpha: 1)
        let dark = UIColor(white: 0.15, alpha: 1)
        let w = hallwayWidth

        func addCorridor(centerX: Float, centerZ: Float, lengthX: Float, lengthZ: Float) {
            let floor = SCNBox(width: CGFloat(lengthX), height: 0.4, length: CGFloat(lengthZ), chamferRadius: 0)
            let floorMat = SCNMaterial()
            floorMat.diffuse.contents = metal
            floorMat.metalness.contents = 0.9
            floorMat.emission.contents = UIColor(white: 0.05, alpha: 1)
            floor.materials = [floorMat]
            let floorNode = SCNNode(geometry: floor)
            floorNode.position = SCNVector3(centerX, 0, centerZ)
            metalRoomRoot.addChildNode(floorNode)

            let ceilNode = SCNNode(geometry: floor)
            ceilNode.position = SCNVector3(centerX, 5, centerZ)
            metalRoomRoot.addChildNode(ceilNode)

            let wallMat = SCNMaterial()
            wallMat.diffuse.contents = dark
            wallMat.metalness.contents = 0.7

            if lengthX >= lengthZ {
                // Corridor along X — side walls along Z edges
                for zSide: Float in [-1, 1] {
                    let wall = SCNBox(width: CGFloat(lengthX), height: 5, length: 0.4, chamferRadius: 0)
                    wall.materials = [wallMat]
                    let n = SCNNode(geometry: wall)
                    n.position = SCNVector3(centerX, 2.5, centerZ + zSide * (lengthZ * 0.5))
                    metalRoomRoot.addChildNode(n)
                }
            } else {
                // Corridor along Z — side walls along X edges
                for xSide: Float in [-1, 1] {
                    let wall = SCNBox(width: 0.4, height: 5, length: CGFloat(lengthZ), chamferRadius: 0)
                    wall.materials = [wallMat]
                    let n = SCNNode(geometry: wall)
                    n.position = SCNVector3(centerX + xSide * (lengthX * 0.5), 2.5, centerZ)
                    metalRoomRoot.addChildNode(n)
                }
            }
        }

        // First leg: 16 km along +X
        addCorridor(centerX: run16km * 0.5, centerZ: 0, lengthX: run16km + 4, lengthZ: w)
        // Second leg: 8 km along +Z from the junction
        addCorridor(centerX: run16km, centerZ: run8km * 0.5, lengthX: w, lengthZ: run8km + 4)

        // Blue lights along both halls.
        for x in stride(from: Float(40), through: run16km, by: 80) {
            addBlueLight(at: SCNVector3(x, 4.4, 0))
        }
        for z in stride(from: Float(40), through: run8km, by: 80) {
            addBlueLight(at: SCNVector3(run16km, 4.4, z))
        }
        // Lights near the start / hole so you can see Red climb out.
        addBlueLight(at: SCNVector3(5, 4.4, 0))
        addBlueLight(at: SCNVector3(20, 4.4, 0))

        // Breakable metal door at the END of the first 16 km.
        let breakable = Props.metalDoor()
        metalDoorRoot = breakable.root
        metalDoorPanel = breakable.doorPanel
        metalDoorRoot.position = SCNVector3(run16km, 0, 0)
        metalDoorRoot.eulerAngles = SCNVector3(0, -Float.pi / 2, 0)
        metalDoorPanel.position = SCNVector3(0, 2.4, 0) // closed until Red breaks it
        metalRoomRoot.addChildNode(metalDoorRoot)
        metalDoorClosed = true
        metalDoorBroken = false

        // Gate at the end of the second 8 km leg
        let exit = Props.metalDoor()
        exitMetalDoorRoot = exit.root
        exitMetalDoorPanel = exit.doorPanel
        exitMetalDoorRoot.position = SCNVector3(run16km, 0, run8km)
        exitMetalDoorRoot.eulerAngles = SCNVector3(0, 0, 0)
        exitMetalDoorPanel.position = SCNVector3(3.6, 2.4, 0)
        metalRoomRoot.addChildNode(exitMetalDoorRoot)
        gateClosed = false
    }

    private func addBlueLight(at pos: SCNVector3) {
        let bulb = SCNNode(geometry: SCNSphere(radius: 0.35))
        let bulbMat = SCNMaterial()
        bulbMat.diffuse.contents = UIColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 1)
        bulbMat.emission.contents = UIColor(red: 0.2, green: 0.55, blue: 1.0, alpha: 1)
        bulb.geometry?.materials = [bulbMat]
        bulb.position = pos
        metalRoomRoot.addChildNode(bulb)

        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .omni
        light.light?.color = UIColor(red: 0.35, green: 0.65, blue: 1.0, alpha: 1)
        light.light?.intensity = 900
        light.light?.attenuationEndDistance = 220
        light.position = pos
        metalRoomRoot.addChildNode(light)
    }

    func enterMetalRoom() {
        inMetalRoom = true
        metalRoomRoot.isHidden = false
        holeNode.isHidden = true
        scene.fogStartDistance = 60
        scene.fogEndDistance = 450
        player.cameraNode.camera?.zFar = 900
    }

    func leaveMetalRoom() {
        inMetalRoom = false
        metalRoomRoot.isHidden = true
        holeNode.isHidden = false
        godRed.park()
        scene.fogStartDistance = 40
        scene.fogEndDistance = 280
        player.cameraNode.camera?.zFar = 2500
    }

    // MARK: Surface doors / hole

    private func placeHoleAndDoors() {
        holeNode.simdPosition = holeCenter
        scene.rootNode.addChildNode(holeNode)

        let escape = Props.choiceDoor(labelColor: UIColor(red: 0.2, green: 1.0, blue: 0.4, alpha: 1))
        escapeDoorRoot = escape.root
        escapeDoorPanel = escape.doorPanel
        escapeDoorRoot.simdPosition = escapeDoorPos
        escapeDoorRoot.eulerAngles = SCNVector3(0, Float.pi, 0)
        escapeDoorRoot.isHidden = true
        scene.rootNode.addChildNode(escapeDoorRoot)

        let monster = Props.choiceDoor(labelColor: UIColor(red: 1.0, green: 0.15, blue: 0.15, alpha: 1))
        monsterDoorRoot = monster.root
        monsterDoorPanel = monster.doorPanel
        monsterDoorRoot.simdPosition = monsterDoorPos
        monsterDoorRoot.eulerAngles = SCNVector3(0, Float.pi, 0)
        monsterDoorRoot.isHidden = true
        scene.rootNode.addChildNode(monsterDoorRoot)
    }

    func closeMetalGate(completion: (() -> Void)? = nil) {
        guard !gateClosed else {
            DispatchQueue.main.async { completion?() }
            return
        }
        gateClosed = true
        let close = SCNAction.move(to: SCNVector3(0, 2.4, 0), duration: 0.4)
        close.timingMode = .easeIn
        exitMetalDoorPanel.runAction(close) {
            DispatchQueue.main.async { completion?() }
        }
    }

    func resetMetalGate() {
        gateClosed = false
        exitMetalDoorPanel.removeAllActions()
        exitMetalDoorPanel.position = SCNVector3(3.6, 2.4, 0)
        exitMetalDoorPanel.isHidden = false
    }

    func breakMetalDoor(completion: (() -> Void)? = nil) {
        guard metalDoorClosed, !metalDoorBroken else {
            DispatchQueue.main.async { completion?() }
            return
        }
        metalDoorBroken = true
        metalDoorClosed = false
        let smash = SCNAction.group([
            SCNAction.moveBy(x: 2.5, y: 1.2, z: -3.5, duration: 0.35),
            SCNAction.rotateBy(x: 0.8, y: 1.2, z: 0.4, duration: 0.35)
        ])
        let drop = SCNAction.moveBy(x: 0, y: -3.5, z: 0, duration: 0.4)
        metalDoorPanel.runAction(SCNAction.sequence([smash, drop])) {
            DispatchQueue.main.async {
                self.metalDoorPanel.isHidden = true
                completion?()
            }
        }
    }

    func resetMetalDoor() {
        metalDoorClosed = true
        metalDoorBroken = false
        metalDoorPanel.isHidden = false
        metalDoorPanel.removeAllActions()
        metalDoorPanel.position = SCNVector3(0, 2.4, 0)
        metalDoorPanel.eulerAngles = SCNVector3Zero
        resetMetalGate()
    }

    func showChoiceDoors(_ show: Bool) {
        escapeDoorRoot.isHidden = !show
        monsterDoorRoot.isHidden = !show
        choiceDoorsOpen = show
        if show {
            escapeDoorPanel.position = SCNVector3(3.6, 2.4, 0)
            monsterDoorPanel.position = SCNVector3(3.6, 2.4, 0)
        }
    }

    // MARK: Lockers outside houses

    private func placeLockers() {
        // One locker outside many houses (20 total).
        var count = 0
        for house in housePositions {
            guard count < 20 else { break }
            // Skip deposit house area a bit for clarity.
            let offset: Float = (count % 2 == 0) ? 3.6 : -3.6
            let locker = Props.locker()
            locker.position = SCNVector3(house.x + offset, 0, house.z + 3.2)
            locker.eulerAngles = SCNVector3(0, Float.pi, 0)
            scene.rootNode.addChildNode(locker)
            lockers.append(locker)
            count += 1
        }
    }

    func nearestLocker(to point: SIMD3<Float>, within radius: Float) -> SCNNode? {
        var best: SCNNode?
        var bestDist = radius
        let pools: [[SCNNode]] = [lockers, houseLockers]
        for pool in pools {
            for locker in pool where locker.isHidden == false {
                let world = locker.presentation.worldPosition
                let d = simd_length(SIMD2<Float>(world.x - point.x, world.z - point.z))
                if d < bestDist {
                    bestDist = d
                    best = locker
                }
            }
        }
        return best
    }

    // MARK: Metals

    private func placeMetals() {
        var placed = 0
        var attempts = 0
        while placed < 55 && attempts < 8000 {
            attempts += 1
            let x = Float.random(in: -72...72)
            let z = Float.random(in: -72...74)
            if blockedByHouse(x: x, z: z, margin: 2.0) { continue }
            if simd_length(SIMD2<Float>(x - spawn.x, z - spawn.z)) < 8 { continue }
            if simd_length(SIMD2<Float>(x, z)) < 5 { continue }
            let m = Props.metal()
            m.position = SCNVector3(x, 1.3, z)
            scene.rootNode.addChildNode(m)
            metals.append(m)
            placed += 1
        }
    }

    func restoreAllMetals() {
        metals.forEach { $0.isHidden = false }
    }

    // MARK: Portable levers + carry door + deposit

    private func makePortableLever() -> SCNNode {
        let made = Props.lever()
        made.beam.isHidden = false
        // Tint beam cyan so pickups are visible.
        return made.root
    }

    private func placePortableLevers() {
        for spot in portableLeverSpots {
            let lever = makePortableLever()
            lever.simdPosition = spot
            lever.isHidden = true
            scene.rootNode.addChildNode(lever)
            portableLevers.append(lever)
        }
    }

    private func placeFinalPortableLevers() {
        for spot in finalPortableLeverSpots {
            let lever = makePortableLever()
            lever.simdPosition = spot
            lever.isHidden = true
            scene.rootNode.addChildNode(lever)
            finalPortableLevers.append(lever)
        }
    }

    func showPortableLevers(_ show: Bool) {
        portableLevers.forEach { $0.isHidden = !show; if show { $0.opacity = 1 } }
    }

    func showFinalPortableLevers(_ show: Bool) {
        finalPortableLevers.forEach { $0.isHidden = !show; if show { $0.opacity = 1 } }
    }

    func restorePortableLevers() {
        for (i, lever) in portableLevers.enumerated() {
            lever.isHidden = false
            lever.opacity = 1
            lever.simdPosition = portableLeverSpots[i]
        }
        for (i, lever) in finalPortableLevers.enumerated() {
            lever.isHidden = true
            lever.opacity = 1
            lever.simdPosition = finalPortableLeverSpots[i]
        }
    }

    private func placeLeverCarrySetup() {
        let gate = Props.metalDoor()
        leverGateRoot = gate.root
        leverGateRoot.simdPosition = leverGatePos
        leverGateRoot.eulerAngles = SCNVector3(0, -Float.pi / 2, 0)
        gate.doorPanel.position = SCNVector3(3.6, 2.4, 0) // open passage
        leverGateRoot.isHidden = true
        scene.rootNode.addChildNode(leverGateRoot)

        // Deposit rack where carried levers are placed.
        let rack = SCNNode()
        let base = LegoBuilder.brick(width: 3.5, height: 0.4, length: 1.2,
                                     color: UIColor(white: 0.25, alpha: 1),
                                     emission: UIColor(white: 0.08, alpha: 1))
        base.position = SCNVector3(0, 0.2, 0)
        rack.addChildNode(base)
        for i in 0..<3 {
            let slot = LegoBuilder.brick(width: 0.35, height: 1.2, length: 0.35,
                                         color: UIColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1),
                                         emission: UIColor(red: 0.1, green: 0.25, blue: 0.5, alpha: 1))
            slot.position = SCNVector3(Float(i - 1) * 1.0, 1.0, 0)
            rack.addChildNode(slot)
        }
        let beam = Props.goalBeam(color: UIColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1))
        rack.addChildNode(beam)
        rack.simdPosition = leverDepositPos
        rack.isHidden = true
        leverDepositRoot = rack
        scene.rootNode.addChildNode(rack)
    }

    func showLeverCarrySetup(_ show: Bool) {
        leverGateRoot.isHidden = !show
        leverDepositRoot.isHidden = !show
    }

    private func placeElevatorInMetalHouse() {
        // Elevator shaft / secret door attached to the metal deposit house.
        let elev = Props.choiceDoor(labelColor: UIColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1))
        elevatorRoot = elev.root
        elevatorRoot.simdPosition = SIMD3<Float>(depositHouse.x, 0, depositHouse.z + 3.5)
        elevatorRoot.eulerAngles = SCNVector3(0, Float.pi, 0)
        elev.doorPanel.position = SCNVector3(0, 2.4, 0) // closed
        elevatorRoot.isHidden = true
        scene.rootNode.addChildNode(elevatorRoot)

        // Final deposit slots next to the elevator (for the last 2 levers).
        let slots = SCNNode()
        for i in 0..<2 {
            let slot = LegoBuilder.brick(width: 0.4, height: 1.3, length: 0.4,
                                         color: UIColor(red: 0.9, green: 0.75, blue: 0.2, alpha: 1),
                                         emission: UIColor(red: 0.5, green: 0.4, blue: 0.05, alpha: 1))
            slot.position = SCNVector3(Float(i) * 1.2 - 0.6, 0.7, -1.5)
            slots.addChildNode(slot)
        }
        slots.simdPosition = SIMD3<Float>(depositHouse.x, 0, depositHouse.z + 3.5)
        slots.isHidden = true
        finalDepositSlots = slots
        scene.rootNode.addChildNode(slots)
    }

    func showElevator(_ show: Bool) {
        elevatorRoot.isHidden = !show
        finalDepositSlots?.isHidden = !show
        if show {
            elevatorOpen = false
            if let panel = elevatorRoot.childNodes.first(where: { $0.geometry is SCNBox && ($0.geometry as? SCNBox)?.width ?? 0 > 2 }) {
                panel.position = SCNVector3(0, 2.4, 0)
            }
            // Reset elevator door panel (second child structure from Props.metalDoor).
            elevatorRoot.enumerateChildNodes { node, _ in
                if let box = node.geometry as? SCNBox, abs(box.width - 3.2) < 0.01 {
                    node.position = SCNVector3(0, 2.4, 0)
                }
            }
        }
    }

    func openElevator() {
        elevatorOpen = true
        elevatorRoot.enumerateChildNodes { node, _ in
            if let box = node.geometry as? SCNBox, abs(box.width - 3.2) < 0.01 {
                node.runAction(SCNAction.move(to: SCNVector3(3.6, 2.4, 0), duration: 0.55))
            }
        }
    }

    var elevatorPos: SIMD3<Float> {
        SIMD3<Float>(depositHouse.x, 0, depositHouse.z + 3.5)
    }

    var finalDepositPos: SIMD3<Float> {
        SIMD3<Float>(depositHouse.x, 0, depositHouse.z + 2.0)
    }

    // MARK: Collision

    private func blockedByHouse(x: Float, z: Float, margin: Float) -> Bool {
        for rect in houseRects {
            if abs(x - rect.cx) < rect.half + margin && abs(z - rect.cz) < rect.half + margin {
                return true
            }
        }
        return false
    }

    /// Deposit house: player can walk into the doorway area.
    func nearDepositHouse(_ point: SIMD3<Float>) -> Bool {
        simd_length(SIMD2<Float>(point.x - depositHouse.x, point.z - depositHouse.z)) < 4.5
    }

    func isBlocked(x: Float, z: Float) -> Bool {
        if inMetalRoom {
            let half = hallwayWidth * 0.5 - 0.4
            let inFirst = x >= 0.2 && x <= run16km + half && abs(z) <= half
            let inSecond = abs(x - run16km) <= half && z >= -half && z <= run8km + 4
            if !(inFirst || inSecond) { return true }
            if metalDoorClosed && !metalDoorBroken {
                if abs(x - run16km) < 1.0 && abs(z) < half + 0.2 { return true }
            }
            if gateClosed {
                // Seal behind the gate on the approach side.
                if abs(x - run16km) < half && z > run8km - 1.2 && z < run8km { return true }
            }
            return false
        }

        // Giant house interior uses its own maze walls (much larger bounds).
        if giantHouseRoot?.isHidden == false {
            let o = giantHouseOrigin
            let half = giantHouseSize * 0.5
            if abs(x - o.x) > half - 1 || abs(z - o.z) > half - 1 { return true }
            if !lockedDoorOpen {
                let door = SIMD3<Float>(o.x - 80, 0, o.z - 120)
                if abs(x - door.x) < 1.4 && abs(z - door.z) < 1.6 { return true }
            }
            for wall in houseWallRects {
                if abs(x - (o.x + wall.cx)) < wall.hw + 0.6 &&
                    abs(z - (o.z + wall.cz)) < wall.hd + 0.6 {
                    return true
                }
            }
            return false
        }

        if x < -bound || x > bound || z > bound || z < -bound - 6 { return true }
        if elevatorRoot.isHidden == false && !elevatorOpen {
            let e = elevatorPos
            if abs(x - e.x) < 1.2 && abs(z - e.z) < 1.5 { return true }
        }
        if nearDepositHouse(SIMD3<Float>(x, 0, z)) { return false }
        return blockedByHouse(x: x, z: z, margin: 0.7)
    }

    /// Deadly pit under the player? (disabled while monsters are hunting / forced off)
    func hazardHole(at point: SIMD3<Float>) -> Bool {
        guard holesEnabled, !forceNoHoles else { return false }
        for hole in hazardHoles {
            if simd_length(SIMD2<Float>(point.x - hole.x, point.z - hole.z)) < 1.6 {
                return true
            }
        }
        return false
    }

    private func placeHazardHoles() {
        scene.rootNode.addChildNode(hazardRoot)
        let spots: [SIMD3<Float>] = [
            SIMD3<Float>(12, 0, 55), SIMD3<Float>(-25, 0, 30), SIMD3<Float>(30, 0, 10),
            SIMD3<Float>(-35, 0, -15), SIMD3<Float>(18, 0, -30), SIMD3<Float>(-10, 0, -55),
            SIMD3<Float>(45, 0, -40), SIMD3<Float>(-45, 0, 5)
        ]
        hazardHoles = spots
        for spot in spots {
            let hole = Props.hole()
            hole.simdPosition = spot
            hole.scale = SCNVector3(0.55, 0.55, 0.55)
            hazardRoot.addChildNode(hole)
        }
    }

    func setHazardHolesVisible(_ visible: Bool) {
        let show = visible && !forceNoHoles
        hazardRoot.isHidden = !show
        holesEnabled = show
    }

    // MARK: Giant house (1000 × 1000) + little metal room, maze walls, 10 lockers

    private func buildGiantHouse() {
        let size = giantHouseSize
        let wallH = min(giantHouseHeight, 80) // playable wall height; ceiling scare uses height cue
        let root = SCNNode()
        root.simdPosition = giantHouseOrigin
        houseWallRects.removeAll()

        let wallMat = SCNMaterial()
        wallMat.diffuse.contents = UIColor(white: 0.28, alpha: 1)
        wallMat.metalness.contents = 0.85
        wallMat.emission.contents = UIColor(white: 0.04, alpha: 1)

        let floor = SCNBox(width: CGFloat(size), height: 0.5, length: CGFloat(size), chamferRadius: 0)
        floor.materials = [wallMat]
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(0, 0.1, 0)
        root.addChildNode(floorNode)

        // Outer shell
        for (dx, dz, w, l) in [
            (Float(0), -size / 2, size, Float(2)),
            (Float(0), size / 2, size, Float(2)),
            (-size / 2, Float(0), Float(2), size),
            (size / 2, Float(0), Float(2), size)
        ] as [(Float, Float, Float, Float)] {
            let box = SCNBox(width: CGFloat(w), height: CGFloat(wallH), length: CGFloat(l), chamferRadius: 0)
            box.materials = [wallMat]
            let n = SCNNode(geometry: box)
            n.position = SCNVector3(dx, wallH * 0.5, dz)
            root.addChildNode(n)
        }

        // Lots of maze walls
        let maze: [(Float, Float, Float, Float)] = [
            (-200, -150, 180, 2), (100, -200, 2, 220), (250, 50, 200, 2),
            (-300, 200, 2, 260), (0, 300, 280, 2), (350, -100, 2, 180),
            (-100, 80, 140, 2), (180, 180, 2, 160), (-250, -50, 2, 200),
            (50, -320, 240, 2), (-380, -250, 160, 2), (300, 280, 2, 200),
            (-50, 400, 200, 2), (120, -50, 2, 140), (-180, 250, 160, 2),
            (400, 0, 2, 300), (-400, 100, 2, 240), (0, -400, 300, 2),
            (220, 400, 180, 2), (-320, 350, 140, 2)
        ]
        for (cx, cz, w, d) in maze {
            let box = SCNBox(width: CGFloat(w), height: 8, length: CGFloat(d), chamferRadius: 0)
            box.materials = [wallMat]
            let n = SCNNode(geometry: box)
            n.position = SCNVector3(cx, 4, cz)
            root.addChildNode(n)
            houseWallRects.append((cx, cz, w * 0.5, d * 0.5))
        }

        // --- Little metal room (escape door lives here) ---
        let littleMat = SCNMaterial()
        littleMat.diffuse.contents = UIColor(white: 0.4, alpha: 1)
        littleMat.metalness.contents = 0.95
        littleMat.emission.contents = UIColor(white: 0.08, alpha: 1)
        for (dx, dz, w, l) in [
            (Float(0), Float(-10), Float(16), Float(0.5)),
            (Float(-8), Float(-4), Float(0.5), Float(12)),
            (Float(8), Float(-4), Float(0.5), Float(12)),
            (Float(0), Float(2), Float(16), Float(0.5))
        ] as [(Float, Float, Float, Float)] {
            let box = SCNBox(width: CGFloat(w), height: 5, length: CGFloat(l), chamferRadius: 0)
            box.materials = [littleMat]
            let n = SCNNode(geometry: box)
            n.position = SCNVector3(dx, 2.5, dz)
            root.addChildNode(n)
            houseWallRects.append((dx, dz, w * 0.5, l * 0.5))
        }
        // Opening on +Z side of little room (entrance from house)
        houseWallRects.removeAll { abs($0.cx) < 0.1 && abs($0.cz - 2) < 0.1 }

        let escape = Props.metalDoor()
        houseEscapeDoor = escape.root
        houseEscapeDoor.position = SCNVector3(0, 0, -10)
        escape.doorPanel.position = SCNVector3(3.6, 2.4, 0)
        root.addChildNode(houseEscapeDoor)

        // --- Locked room (needs key) ---
        let roomX: Float = -80
        let roomZ: Float = -120
        for (dx, dz, w, l) in [
            (roomX, roomZ - 6, Float(14), Float(0.5)),
            (roomX, roomZ + 6, Float(14), Float(0.5)),
            (roomX - 7, roomZ, Float(0.5), Float(12)),
            (roomX + 7, roomZ - 3.5, Float(0.5), Float(5)),
            (roomX + 7, roomZ + 3.5, Float(0.5), Float(5))
        ] as [(Float, Float, Float, Float)] {
            let box = SCNBox(width: CGFloat(w), height: 5, length: CGFloat(l), chamferRadius: 0)
            box.materials = [wallMat]
            let n = SCNNode(geometry: box)
            n.position = SCNVector3(dx, 2.5, dz)
            root.addChildNode(n)
            houseWallRects.append((dx, dz, w * 0.5, l * 0.5))
        }
        let door = Props.metalDoor()
        lockedRoomDoor = door.root
        lockedRoomDoor.position = SCNVector3(roomX + 7, 0, roomZ)
        lockedRoomDoor.eulerAngles = SCNVector3(0, -Float.pi / 2, 0)
        door.doorPanel.position = SCNVector3(0, 2.4, 0)
        root.addChildNode(lockedRoomDoor)

        lockedRoomLever = makePortableLever()
        lockedRoomLever.position = SCNVector3(roomX, 0, roomZ)
        root.addChildNode(lockedRoomLever)

        let key = LegoBuilder.brick(width: 0.5, height: 0.2, length: 1.0,
                                    color: UIColor(red: 1, green: 0.85, blue: 0.2, alpha: 1),
                                    emission: UIColor(red: 0.6, green: 0.5, blue: 0.05, alpha: 1))
        keyNode = key
        keyNode.position = SCNVector3(roomX + 30, 1.0, roomZ + 20)
        keyNode.runAction(SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 2)))
        root.addChildNode(keyNode)

        // --- Tunnel lever ---
        let tunnel = SCNBox(width: 5, height: 3.5, length: 40, chamferRadius: 0)
        let tunnelMat = SCNMaterial()
        tunnelMat.diffuse.contents = UIColor(white: 0.18, alpha: 1)
        tunnel.materials = [tunnelMat]
        let tunnelNode = SCNNode(geometry: tunnel)
        tunnelNode.position = SCNVector3(200, 1.7, 100)
        root.addChildNode(tunnelNode)
        tunnelLever = makePortableLever()
        tunnelLever.position = SCNVector3(200, 0, 115)
        root.addChildNode(tunnelLever)

        // --- Underwater lever ---
        let pool = SCNBox(width: 22, height: 3, length: 22, chamferRadius: 0)
        let waterMat = SCNMaterial()
        waterMat.diffuse.contents = UIColor(red: 0.1, green: 0.35, blue: 0.7, alpha: 0.45)
        waterMat.transparency = 0.55
        waterMat.isDoubleSided = true
        pool.materials = [waterMat]
        let poolNode = SCNNode(geometry: pool)
        poolNode.position = SCNVector3(-220, 0.9, 180)
        root.addChildNode(poolNode)
        waterLever = makePortableLever()
        waterLever.position = SCNVector3(-220, -0.2, 180)
        root.addChildNode(waterLever)

        // 10 lockers to hide from Sonnelves
        houseLockers.removeAll()
        let lockerSpots: [SIMD3<Float>] = [
            SIMD3(30, 0, -20), SIMD3(-40, 0, 40), SIMD3(90, 0, 60),
            SIMD3(-120, 0, -40), SIMD3(150, 0, -80), SIMD3(-60, 0, 140),
            SIMD3(70, 0, 200), SIMD3(-200, 0, 40), SIMD3(250, 0, -40),
            SIMD3(20, 0, -150)
        ]
        for spot in lockerSpots {
            let locker = Props.locker()
            locker.position = SCNVector3(spot.x, 0, spot.z)
            root.addChildNode(locker)
            houseLockers.append(locker)
        }

        root.isHidden = true
        root.name = "giantHouse"
        scene.rootNode.addChildNode(root)
    }

    private var giantHouseRoot: SCNNode? {
        scene.rootNode.childNode(withName: "giantHouse", recursively: false)
    }

    func showGiantHouse(_ show: Bool) {
        giantHouseRoot?.isHidden = !show
        forceNoHoles = show
        setHazardHolesVisible(!show)
        if show {
            hasKey = false
            lockedDoorOpen = false
            keyNode.isHidden = false
            lockedRoomLever.isHidden = false
            tunnelLever.isHidden = false
            waterLever.isHidden = false
            lockedRoomDoor.enumerateChildNodes { node, _ in
                if let box = node.geometry as? SCNBox, abs(box.width - 3.2) < 0.01 {
                    node.position = SCNVector3(0, 2.4, 0)
                }
            }
        }
    }

    func tryPickupKey(at point: SIMD3<Float>) -> Bool {
        guard !hasKey, !keyNode.isHidden else { return false }
        let keyWorld = keyNode.presentation.worldPosition
        if simd_length(SIMD2<Float>(point.x - keyWorld.x, point.z - keyWorld.z)) < 2.5 {
            hasKey = true
            keyNode.isHidden = true
            return true
        }
        return false
    }

    func tryUnlockDoor(at point: SIMD3<Float>) -> Bool {
        guard hasKey, !lockedDoorOpen else { return false }
        let door = SIMD3<Float>(giantHouseOrigin.x - 80 + 7, 0, giantHouseOrigin.z - 120)
        if simd_length(SIMD2<Float>(point.x - door.x, point.z - door.z)) < 4 {
            lockedDoorOpen = true
            lockedRoomDoor.enumerateChildNodes { node, _ in
                if let box = node.geometry as? SCNBox, abs(box.width - 3.2) < 0.01 {
                    node.runAction(SCNAction.move(to: SCNVector3(3.6, 2.4, 0), duration: 0.4))
                }
            }
            return true
        }
        return false
    }

    func isInWater(at point: SIMD3<Float>) -> Bool {
        let pool = SIMD3<Float>(giantHouseOrigin.x - 220, 0, giantHouseOrigin.z + 180)
        return abs(point.x - pool.x) < 11 && abs(point.z - pool.z) < 11
    }

    func nearHouseEscape(_ point: SIMD3<Float>) -> Bool {
        simd_length(SIMD2<Float>(point.x - houseEscapePos.x, point.z - houseEscapePos.z)) < 3.5
    }

    func respawnPlayer() {
        leaveMetalRoom()
        player.place(at: spawn, yaw: spawnYaw)
        player.setHidden(false)
    }
}
