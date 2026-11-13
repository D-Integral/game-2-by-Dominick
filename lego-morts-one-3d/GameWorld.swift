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

    final class LeverItem {
        let root = SCNNode()
        let handle: SCNNode
        let beam: SCNNode
        var pulled = false
        init() {
            let made = Props.lever()
            root.addChildNode(made.root)
            handle = made.handle
            beam = made.beam
        }
    }
    private(set) var levers: [LeverItem] = []          // mid-game (3)
    private(set) var finalLevers: [LeverItem] = []     // last objective (2)

    let holeNode = Props.hole()
    private(set) var metalDoorRoot = SCNNode()         // breakable door in metal room
    private(set) var metalDoorPanel = SCNNode()
    private(set) var exitMetalDoorRoot = SCNNode()     // unbroken exit door
    private(set) var exitMetalDoorPanel = SCNNode()
    private(set) var escapeDoorRoot = SCNNode()
    private(set) var escapeDoorPanel = SCNNode()
    private(set) var monsterDoorRoot = SCNNode()
    private(set) var monsterDoorPanel = SCNNode()
    private(set) var secretDoorRoot = SCNNode()
    private(set) var secretDoorPanel = SCNNode()
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
    let depositHouse = SIMD3<Float>(-14, 0, 28)        // bring metal here (no clue beam)
    let holeCenter = SIMD3<Float>(0, 0, 0)
    let escapeDoorPos = SIMD3<Float>(-22, 0, -55)
    let monsterDoorPos = SIMD3<Float>(22, 0, -55)
    let exitGoal = SIMD3<Float>(0, 0, -84)
    let secretDoorPos = SIMD3<Float>(0, 0, 40)
    let surfaceAfterRoom = SIMD3<Float>(18, 0, 8)
    let leverSpots = [SIMD3<Float>(-64, 0, 64),
                      SIMD3<Float>(70, 0, 8),
                      SIMD3<Float>(-10, 0, -70)]
    let finalLeverSpots = [SIMD3<Float>(-20, 0, 50),
                           SIMD3<Float>(20, 0, 50)]

    // Metal room (underground) positions — world space after room is placed at (0, roomY, 0)
    let roomY: Float = -14
    var metalRoomSpawn: SIMD3<Float> { SIMD3<Float>(-14, roomY, 0) }
    var breakDoorPos: SIMD3<Float> { SIMD3<Float>(0, roomY, 0) }
    var exitDoorPos: SIMD3<Float> { SIMD3<Float>(16, roomY, 0) }

    private(set) var metalDoorClosed = true
    private(set) var metalDoorBroken = false
    private(set) var choiceDoorsOpen = false
    private(set) var secretDoorOpen = false
    private(set) var inMetalRoom = false
    private(set) var roadsBuilt = false

    init() {
        setupEnvironment()
        buildVillage()
        placeStreetLamps()
        placeBlood()
        placeMetals()
        placeLevers()
        placeFinalLevers()
        placeHoleAndDoors()
        buildMetalRoom()
        placeLockers()
        placeSecretDoor()

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
        scene.fogStartDistance = 18
        scene.fogEndDistance = 110
        scene.fogDensityExponent = 1.2

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
            let body = isDeposit
                ? UIColor(red: 0.55, green: 0.45, blue: 0.15, alpha: 1)
                : bodyColors[i % bodyColors.count]
            let house = LegoBuilder.house(bodyColor: body, roofColor: roofColors[i % roofColors.count])
            house.position = SCNVector3(x, 0, z)
            house.eulerAngles = SCNVector3(0, Float.pi / 2 * Float(i % 4), 0)
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
        metalRoomRoot.simdPosition = SIMD3<Float>(0, roomY, 0)
        metalRoomRoot.isHidden = true
        scene.rootNode.addChildNode(metalRoomRoot)

        let metal = UIColor(white: 0.35, alpha: 1)
        let dark = UIColor(white: 0.15, alpha: 1)

        // Floor / ceiling
        let floor = SCNBox(width: 44, height: 0.4, length: 14, chamferRadius: 0)
        let floorMat = SCNMaterial()
        floorMat.diffuse.contents = metal
        floorMat.metalness.contents = 0.9
        floorMat.emission.contents = UIColor(white: 0.05, alpha: 1)
        floor.materials = [floorMat]
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(0, 0, 0)
        metalRoomRoot.addChildNode(floorNode)

        let ceiling = SCNBox(width: 44, height: 0.4, length: 14, chamferRadius: 0)
        ceiling.materials = [floorMat]
        let ceilNode = SCNNode(geometry: ceiling)
        ceilNode.position = SCNVector3(0, 6, 0)
        metalRoomRoot.addChildNode(ceilNode)

        // Walls
        for zSide in [-1.0, 1.0] as [Double] {
            let wall = SCNBox(width: 44, height: 6, length: 0.4, chamferRadius: 0)
            let wallMat = SCNMaterial()
            wallMat.diffuse.contents = dark
            wallMat.metalness.contents = 0.7
            wall.materials = [wallMat]
            let wallNode = SCNNode(geometry: wall)
            wallNode.position = SCNVector3(0, 3, Float(zSide) * 7)
            metalRoomRoot.addChildNode(wallNode)
        }
        for xSide in [-1.0, 1.0] as [Double] {
            let wall = SCNBox(width: 0.4, height: 6, length: 14, chamferRadius: 0)
            let wallMat = SCNMaterial()
            wallMat.diffuse.contents = dark
            wallMat.metalness.contents = 0.7
            wall.materials = [wallMat]
            let wallNode = SCNNode(geometry: wall)
            wallNode.position = SCNVector3(Float(xSide) * 22, 3, 0)
            metalRoomRoot.addChildNode(wallNode)
        }

        // Dim red lights
        for x in [-10, 5, 14] as [Float] {
            let light = SCNNode()
            light.light = SCNLight()
            light.light?.type = .omni
            light.light?.color = UIColor(red: 1.0, green: 0.25, blue: 0.2, alpha: 1)
            light.light?.intensity = 500
            light.position = SCNVector3(x, 5, 0)
            metalRoomRoot.addChildNode(light)
        }

        // Breakable door (starts closed) — local x=0
        let breakable = Props.metalDoor()
        metalDoorRoot = breakable.root
        metalDoorPanel = breakable.doorPanel
        metalDoorRoot.position = SCNVector3(0, 0, 0)
        metalDoorRoot.eulerAngles = SCNVector3(0, -Float.pi / 2, 0)
        metalDoorPanel.position = SCNVector3(0, 2.4, 0) // closed
        metalRoomRoot.addChildNode(metalDoorRoot)
        metalDoorClosed = true
        metalDoorBroken = false

        // Unbroken exit door (open) — local x=16
        let exit = Props.metalDoor()
        exitMetalDoorRoot = exit.root
        exitMetalDoorPanel = exit.doorPanel
        exitMetalDoorRoot.position = SCNVector3(16, 0, 0)
        exitMetalDoorRoot.eulerAngles = SCNVector3(0, -Float.pi / 2, 0)
        exitMetalDoorPanel.position = SCNVector3(3.6, 2.4, 0) // open / not broken
        metalRoomRoot.addChildNode(exitMetalDoorRoot)
    }

    func enterMetalRoom() {
        inMetalRoom = true
        metalRoomRoot.isHidden = false
        holeNode.isHidden = true
    }

    func leaveMetalRoom() {
        inMetalRoom = false
        metalRoomRoot.isHidden = true
        holeNode.isHidden = false
        godRed.park()
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

    private func placeSecretDoor() {
        let door = Props.choiceDoor(labelColor: UIColor(red: 0.9, green: 0.75, blue: 0.2, alpha: 1))
        secretDoorRoot = door.root
        secretDoorPanel = door.doorPanel
        secretDoorRoot.simdPosition = secretDoorPos
        secretDoorRoot.eulerAngles = SCNVector3(0, Float.pi, 0)
        secretDoorPanel.position = SCNVector3(0, 2.4, 0) // closed until levers pulled
        secretDoorRoot.isHidden = true
        scene.rootNode.addChildNode(secretDoorRoot)
    }

    func showSecretDoor(_ show: Bool) {
        secretDoorRoot.isHidden = !show
        if show {
            secretDoorOpen = false
            secretDoorPanel.position = SCNVector3(0, 2.4, 0)
        }
    }

    func openSecretDoor() {
        secretDoorOpen = true
        let open = SCNAction.move(to: SCNVector3(3.6, 2.4, 0), duration: 0.5)
        secretDoorPanel.runAction(open)
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
        for locker in lockers {
            let d = simd_length(SIMD2<Float>(locker.simdPosition.x - point.x,
                                             locker.simdPosition.z - point.z))
            if d < bestDist {
                bestDist = d
                best = locker
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

    // MARK: Levers

    private func placeLevers() {
        for spot in leverSpots {
            let lever = LeverItem()
            lever.root.position = SCNVector3(spot.x, 0, spot.z)
            lever.root.isHidden = true
            scene.rootNode.addChildNode(lever.root)
            levers.append(lever)
        }
    }

    private func placeFinalLevers() {
        for spot in finalLeverSpots {
            let lever = LeverItem()
            lever.root.position = SCNVector3(spot.x, 0, spot.z)
            lever.root.isHidden = true
            scene.rootNode.addChildNode(lever.root)
            finalLevers.append(lever)
        }
    }

    func showLevers(_ show: Bool) {
        levers.forEach { $0.root.isHidden = !show }
    }

    func showFinalLevers(_ show: Bool) {
        finalLevers.forEach { $0.root.isHidden = !show }
    }

    func resetLevers() {
        for lever in levers + finalLevers {
            lever.pulled = false
            lever.handle.removeAllActions()
            lever.handle.eulerAngles = SCNVector3Zero
            lever.beam.isHidden = false
        }
    }

    func pull(_ lever: LeverItem) {
        lever.pulled = true
        lever.handle.runAction(SCNAction.rotateTo(x: -1.1, y: 0, z: 0, duration: 0.3))
        lever.beam.isHidden = true
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
            // Metal room bounds (world X/Z with room centered at 0).
            if x < -20 || x > 20 || abs(z) > 5.5 { return true }
            // Closed breakable door blocks the mid corridor.
            if metalDoorClosed && !metalDoorBroken {
                if abs(x - 0) < 1.2 && abs(z) < 2.2 { return true }
            }
            return false
        }

        if x < -bound || x > bound || z > bound || z < -bound - 6 { return true }
        if secretDoorRoot.isHidden == false && !secretDoorOpen {
            if abs(x - secretDoorPos.x) < 1.2 && abs(z - secretDoorPos.z) < 2.2 { return true }
        }
        // Allow walking into deposit house footprint a bit (doorway).
        if nearDepositHouse(SIMD3<Float>(x, 0, z)) { return false }
        return blockedByHouse(x: x, z: z, margin: 0.7)
    }

    func respawnPlayer() {
        leaveMetalRoom()
        player.place(at: spawn, yaw: spawnYaw)
        player.setHidden(false)
    }
}
