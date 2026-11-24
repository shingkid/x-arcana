import Foundation

enum SummonKind: String, Codable, CaseIterable {
    case albert, alan, demon, patronus

    var manaCost: Double {
        switch self {
        case .albert: return 30
        case .alan: return 25
        case .demon: return 20
        case .patronus: return 30
        }
    }

    var maxHealth: Double {
        switch self {
        case .albert: return 20
        case .alan: return 15
        case .demon: return 30
        case .patronus: return 0
        }
    }

    func canCoexist(with other: SummonKind) -> Bool {
        (self == .albert && other == .alan) || (self == .alan && other == .albert)
    }
}

enum SummonResult: Equatable {
    case summoned, alreadyActive, insufficientMana, unavailable, gameOver
}

enum CombatRejection: String {
    case gameOver, paused, notReady, cooldown, invalidTarget, insufficientMana
}

struct RunSnapshot: Codable, Equatable {
    var health: Double = 100
    var maxHealth: Int = 100
    var mana: Double = 100
    var maxMana: Double = 100
    var level: Int = 1
    // Kept for older peers. Current levels identify stages, without experience points.
    var xp: Int = 0
    var xpToNextLevel: Int = 0
    var score: Int = 0
    var kills: Int = 0
    var wave: Int = 1
    var bestScore: Int = 0
    var bestWave: Int = 0
    var isGameOver: Bool = false
    var shieldHealth: Double? = 0
    // Legacy timed-shield snapshots remain decodable. New shields have no duration.
    var shieldRemaining: Double = 0
    var shieldCooldownRemaining: Double = 0
    var hasStarted: Bool = true
    var countdownRemaining: Double = 0
    var nyanRemaining: Double = 0
    var nyanKillsSinceCast: Int = 0
}

/// All times are simulation times, so pause and game over stop regeneration.
final class SurvivalState {
    static let nyanDuration: TimeInterval = 27
    static let manaRegenerationDelay: TimeInterval = 2
    static let manaRegenerationPerSecond: Double = 4
    private(set) var snapshot: RunSnapshot
    private var regenerationDelay: TimeInterval = 0
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = .standard, hasStarted: Bool = true) {
        self.defaults = defaults
        snapshot = RunSnapshot()
        snapshot.hasStarted = hasStarted
        snapshot.bestScore = defaults?.integer(forKey: "XArcana.bestScore") ?? 0
        snapshot.bestWave = defaults?.integer(forKey: "XArcana.bestWave") ?? 0
    }

    func update(deltaTime: TimeInterval, suppressRegeneration: Bool = false) {
        guard snapshot.hasStarted, snapshot.countdownRemaining <= 0, !snapshot.isGameOver,
            deltaTime.isFinite, deltaTime > 0
        else { return }
        snapshot.nyanRemaining = max(0, snapshot.nyanRemaining - deltaTime)
        snapshot.shieldCooldownRemaining = max(0, snapshot.shieldCooldownRemaining - deltaTime)
        let regenerationTime = suppressRegeneration ? 0 : max(0, deltaTime - regenerationDelay)
        regenerationDelay = max(0, regenerationDelay - deltaTime)
        snapshot.mana = min(snapshot.maxMana, snapshot.mana + regenerationTime * Self.manaRegenerationPerSecond)
    }

    func canSpend(_ cost: Double) -> Bool {
        snapshot.hasStarted && snapshot.countdownRemaining <= 0 && !snapshot.isGameOver && cost >= 0
            && snapshot.mana >= cost
    }

    @discardableResult
    func spend(_ cost: Double) -> Bool {
        guard canSpend(cost) else { return false }
        snapshot.mana -= cost
        if cost > 0 { regenerationDelay = Self.manaRegenerationDelay }
        return true
    }

    @discardableResult
    func beginCountdown() -> Bool {
        guard !snapshot.hasStarted, !snapshot.isGameOver else { return false }
        snapshot.hasStarted = true
        snapshot.countdownRemaining = 3
        return true
    }

    func advanceCountdown(deltaTime: TimeInterval) {
        guard snapshot.hasStarted, !snapshot.isGameOver, deltaTime.isFinite, deltaTime > 0 else { return }
        snapshot.countdownRemaining = max(0, snapshot.countdownRemaining - deltaTime)
    }

    @discardableResult
    func activateNyan(manaCost: Double = 80) -> Bool {
        guard snapshot.nyanRemaining <= 0, snapshot.nyanKillsSinceCast >= 20, spend(manaCost) else { return false }
        snapshot.nyanKillsSinceCast = 0
        snapshot.nyanRemaining = Self.nyanDuration
        return true
    }

    @discardableResult
    func activateShield(manaCost: Double = 20) -> Bool {
        guard (snapshot.shieldHealth ?? 0) == 0, snapshot.shieldCooldownRemaining <= 0, spend(manaCost) else {
            return false
        }
        snapshot.shieldHealth = 20
        snapshot.shieldCooldownRemaining = 10
        return true
    }

    func damage(_ amount: Double) {
        guard !snapshot.isGameOver, amount.isFinite, amount > 0 else { return }
        let absorbed = min(snapshot.shieldHealth ?? 0, amount)
        snapshot.shieldHealth = (snapshot.shieldHealth ?? 0) - absorbed
        snapshot.health = max(0, snapshot.health - (amount - absorbed))
        snapshot.isGameOver = snapshot.health == 0
        if snapshot.isGameOver { snapshot.nyanRemaining = 0 }
    }

    func recordKill() {
        guard !snapshot.isGameOver else { return }
        snapshot.kills += 1
        snapshot.nyanKillsSinceCast = min(20, snapshot.nyanKillsSinceCast + 1)
        snapshot.score += 100
        saveRecords()
    }

    func clearWave() {
        guard !snapshot.isGameOver else { return }
        snapshot.score += 250
        snapshot.bestWave = max(snapshot.bestWave, snapshot.wave)
        saveRecords()
    }

    func nextWave() {
        guard snapshot.hasStarted, snapshot.countdownRemaining <= 0, !snapshot.isGameOver else { return }
        snapshot.wave += 1
        snapshot.level = snapshot.wave
        snapshot.maxHealth += 10
        snapshot.maxMana += 10
        snapshot.health = Double(snapshot.maxHealth)
        snapshot.mana = snapshot.maxMana
        regenerationDelay = 0
    }

    func restart(hasStarted: Bool = true) {
        let bestScore = snapshot.bestScore
        let bestWave = snapshot.bestWave
        snapshot = RunSnapshot()
        snapshot.hasStarted = hasStarted
        snapshot.bestScore = bestScore
        snapshot.bestWave = bestWave
        regenerationDelay = 0
    }

    func clearRecords() {
        snapshot.bestScore = 0
        snapshot.bestWave = 0
        defaults?.removeObject(forKey: "XArcana.bestScore")
        defaults?.removeObject(forKey: "XArcana.bestWave")
    }

    private func saveRecords() {
        snapshot.bestScore = max(snapshot.bestScore, snapshot.score)
        defaults?.set(snapshot.bestScore, forKey: "XArcana.bestScore")
        defaults?.set(snapshot.bestWave, forKey: "XArcana.bestWave")
    }
}

// Older controller snapshots have no shield fields.
extension RunSnapshot {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        health = try values.decodeIfPresent(Double.self, forKey: .health) ?? health
        maxHealth = try values.decodeIfPresent(Int.self, forKey: .maxHealth) ?? maxHealth
        mana = try values.decodeIfPresent(Double.self, forKey: .mana) ?? mana
        maxMana = try values.decodeIfPresent(Double.self, forKey: .maxMana) ?? maxMana
        level = try values.decodeIfPresent(Int.self, forKey: .level) ?? level
        xp = try values.decodeIfPresent(Int.self, forKey: .xp) ?? xp
        xpToNextLevel = try values.decodeIfPresent(Int.self, forKey: .xpToNextLevel) ?? xpToNextLevel
        score = try values.decodeIfPresent(Int.self, forKey: .score) ?? score
        kills = try values.decodeIfPresent(Int.self, forKey: .kills) ?? kills
        wave = try values.decodeIfPresent(Int.self, forKey: .wave) ?? wave
        bestScore = try values.decodeIfPresent(Int.self, forKey: .bestScore) ?? bestScore
        bestWave = try values.decodeIfPresent(Int.self, forKey: .bestWave) ?? bestWave
        isGameOver = try values.decodeIfPresent(Bool.self, forKey: .isGameOver) ?? isGameOver
        shieldHealth = try values.decodeIfPresent(Double.self, forKey: .shieldHealth)
        shieldRemaining = try values.decodeIfPresent(Double.self, forKey: .shieldRemaining) ?? 0
        shieldCooldownRemaining = try values.decodeIfPresent(Double.self, forKey: .shieldCooldownRemaining) ?? 0
        hasStarted = try values.decodeIfPresent(Bool.self, forKey: .hasStarted) ?? true
        countdownRemaining = try values.decodeIfPresent(Double.self, forKey: .countdownRemaining) ?? 0
        nyanRemaining = try values.decodeIfPresent(Double.self, forKey: .nyanRemaining) ?? 0
        nyanKillsSinceCast = try values.decodeIfPresent(Int.self, forKey: .nyanKillsSinceCast) ?? 0
    }
}
