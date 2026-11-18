//
//  SaveGameStore.swift
//  lego-morts-one-3d
//
 //  Keeps every playthrough so Continue can list and resume them.
//

import Foundation

enum SaveGameStore {

    struct Slot: Codable, Equatable {
        let id: UUID
        var createdAt: Date
        var updatedAt: Date
        var objectiveRaw: Int
        var label: String
        var finished: Bool
    }

    private static let savesKey = "legoMortsOne.saves.v2"
    private static let activeKey = "legoMortsOne.activeSlot"
    private static let legacyKey = "legoMortsOne.objective"

    static func allSlots() -> [Slot] {
        migrateLegacyIfNeeded()
        return load().sorted { $0.updatedAt > $1.updatedAt }
    }

    static func continuableSlots() -> [Slot] {
        allSlots().filter { !$0.finished }
    }

    static func createNewGame() -> Slot {
        migrateLegacyIfNeeded()
        var slots = load()
        let slot = Slot(
            id: UUID(),
            createdAt: Date(),
            updatedAt: Date(),
            objectiveRaw: GameDirector.Objective.collectMetal.rawValue,
            label: Self.title(for: .collectMetal),
            finished: false
        )
        slots.append(slot)
        save(slots)
        setActive(id: slot.id)
        return slot
    }

    static func setActive(id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: activeKey)
    }

    static func activeSlot() -> Slot? {
        migrateLegacyIfNeeded()
        guard let raw = UserDefaults.standard.string(forKey: activeKey),
              let id = UUID(uuidString: raw) else {
            return continuableSlots().first
        }
        return load().first { $0.id == id }
    }

    static func updateActive(objectiveRaw: Int) {
        migrateLegacyIfNeeded()
        guard let active = activeSlot() else { return }
        var slots = load()
        guard let idx = slots.firstIndex(where: { $0.id == active.id }) else { return }
        let objective = GameDirector.Objective(rawValue: objectiveRaw)
        if objective == .won {
            slots[idx].finished = true
            slots[idx].label = "Completed — you escaped"
            slots[idx].objectiveRaw = objectiveRaw
            slots[idx].updatedAt = Date()
            save(slots)
            return
        }
        slots[idx].objectiveRaw = objectiveRaw
        slots[idx].label = title(for: objective)
        slots[idx].updatedAt = Date()
        slots[idx].finished = false
        save(slots)
    }

    static func markActiveFinished() {
        updateActive(objectiveRaw: GameDirector.Objective.won.rawValue)
    }

    static func title(for objective: GameDirector.Objective?) -> String {
        switch objective {
        case .collectMetal: return "Obj 1 — Collect metals"
        case .buildRoads: return "Obj 2 — Metal house / roads"
        case .metalRoom: return "Obj 3 — Metal room chase"
        case .giantHouse: return "Obj 4 — Giant house levers"
        case .escapeVillage, .escapeRed: return "Obj 5 — Escape village"
        case .findFinalLevers: return "Obj 6 — Final levers"
        case .elevatorEnd: return "Obj 7 — Elevator escape"
        case .won: return "Completed"
        case .none: return "Unknown objective"
        }
    }

    static func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    // MARK: Private

    private static func load() -> [Slot] {
        guard let data = UserDefaults.standard.data(forKey: savesKey),
              let slots = try? JSONDecoder().decode([Slot].self, from: data) else {
            return []
        }
        return slots
    }

    private static func save(_ slots: [Slot]) {
        if let data = try? JSONEncoder().encode(slots) {
            UserDefaults.standard.set(data, forKey: savesKey)
        }
    }

    private static func migrateLegacyIfNeeded() {
        guard UserDefaults.standard.object(forKey: savesKey) == nil,
              let legacy = UserDefaults.standard.object(forKey: legacyKey) as? Int else {
            return
        }
        let objective = GameDirector.Objective(rawValue: legacy)
        let slot = Slot(
            id: UUID(),
            createdAt: Date(),
            updatedAt: Date(),
            objectiveRaw: legacy,
            label: title(for: objective),
            finished: objective == .won
        )
        save([slot])
        setActive(id: slot.id)
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }
}
