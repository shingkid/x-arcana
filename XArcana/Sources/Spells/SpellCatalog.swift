import Foundation
import SceneKit

/// Stable spell names are separate from the controller's existing wire commands.
enum SpellID: String, CaseIterable {
    case lightning, fireball, ice, shield, demon, nyan, revelio, lumos, patronus, albert, alan, sparks
}

enum SpellInvocation {
    case gesture(guide: String)
    case voice(VoiceCommand, phrase: String, aliases: [String])
    case gestureAndVoice(guide: String, VoiceCommand, phrase: String, aliases: [String])
    case unrecognizedStroke

    var hasGesture: Bool {
        switch self {
        case .gesture, .gestureAndVoice: return true
        case .voice, .unrecognizedStroke: return false
        }
    }

    var gestureGuide: String? {
        switch self {
        case .gesture(let guide), .gestureAndVoice(let guide, _, _, _): return guide
        case .voice, .unrecognizedStroke: return nil
        }
    }

    var command: VoiceCommand? {
        switch self {
        case .voice(let command, _, _), .gestureAndVoice(_, let command, _, _): return command
        case .gesture, .unrecognizedStroke: return nil
        }
    }

    var phrases: [String] {
        switch self {
        case .voice(_, let phrase, let aliases), .gestureAndVoice(_, _, let phrase, let aliases):
            return [phrase] + aliases
        case .gesture, .unrecognizedStroke: return []
        }
    }
}

enum SpellSoundPolicy {
    // A required first sound prevents a spell from silently omitting its sound design.
    case onCast(SpellAudio.Sound, layers: [SpellAudio.Sound])
    case simulationTimed(SpellAudio.Sound)

    var sounds: [SpellAudio.Sound] {
        switch self {
        case .onCast(let first, let layers): return [first] + layers
        case .simulationTimed(let sound): return [sound]
        }
    }
}

enum SpellPresentation {
    // Existing combat and world effects create their own spell visuals after validation.
    case effectOwned
    case onAccepted(@MainActor (SpellCastContext) -> Void)

    @MainActor
    func perform(context: SpellCastContext, on stage: GameStage) {
        stage.animateCast()
        if case .onAccepted(let animate) = self { animate(context) }
    }
}

enum SpellCastOutcome: Equatable {
    case accepted
    case rejected(String, sparks: Bool)
}

struct SpellDefinition {
    let id: SpellID
    let title: String
    let rune: RuneKind?
    let invocation: SpellInvocation
    let manaCost: Double
    let effect: @MainActor (SpellCastContext) -> SpellCastOutcome
    let presentation: SpellPresentation
    let sound: SpellSoundPolicy
    let feedback: String

    var acceptedFeedback: String {
        manaCost > 0 ? "\(feedback) · -\(Int(manaCost)) MP" : feedback
    }
}

@MainActor
struct SpellCastContext {
    let combat: Combat
    let world: GameWorld
    let origin: SIMD3<Float>
    let target: SIMD3<Float>

    func combatResult(_ accepted: Bool) -> SpellCastOutcome {
        if accepted { return .accepted }
        if combat.lastRejection == .insufficientMana {
            return .rejected("Not enough mana. Let it recover or say shoot to use the bow.", sparks: true)
        }
        return .rejected("Spell is recovering. Try again.", sparks: false)
    }

    func summon(_ kind: SummonKind, makeNode: () -> SCNNode?) -> SpellCastOutcome {
        let outcome = combat.summon(kind: kind, makeNode: makeNode)
        let name = kind == .patronus ? "Patronus" : kind.rawValue.capitalized
        switch outcome {
        case .summoned: return .accepted
        case .alreadyActive: return .rejected("\(name) is already here. No mana spent.", sparks: false)
        case .insufficientMana:
            return .rejected("Not enough mana. \(name) needs \(Int(kind.manaCost)).", sparks: true)
        case .unavailable:
            return .rejected("\(name) could not appear. Your mana and allies are unchanged.", sparks: false)
        case .gameOver: return .rejected("Run ended. Choose Play again.", sparks: false)
        }
    }
}

/// Add one definition file, then include it here. Every spell must supply all casting components.
enum SpellCatalog {
    static let all: [SpellDefinition] = [
        lightning, fireball, ice, shield, demon, nyan, revelio, lumos, patronus, albert, alan, sparks,
    ]

    static func definition(for rune: RuneKind?) -> SpellDefinition {
        guard let rune else { return sparks }
        guard let definition = all.first(where: { $0.rune == rune }) else {
            preconditionFailure("Missing spell definition for \(rune.rawValue)")
        }
        return definition
    }

    static func definition(for command: VoiceCommand) -> SpellDefinition? {
        all.first { $0.invocation.command == command }
    }

    static func summon(_ kind: SummonKind) -> SpellDefinition {
        // Summon IDs match their persistent companion names; wire commands remain unchanged.
        guard let definition = all.first(where: { $0.id.rawValue == kind.rawValue }) else {
            preconditionFailure("Missing summon definition for \(kind.rawValue)")
        }
        return definition
    }

    static var gestureRunes: [RuneKind] { all.filter { $0.invocation.hasGesture }.compactMap(\.rune) }

    static var voiceAliases: [(phrase: String, command: VoiceCommand)] {
        all.flatMap { definition in
            guard let command = definition.invocation.command else { return [(String, VoiceCommand)]() }
            return definition.invocation.phrases.map { (phrase: $0, command: command) }
        } + [("cast", .cast), ("shoot", .shoot)]
    }

    static var wandGestureGuide: String {
        all.compactMap { definition in
            definition.invocation.gestureGuide.map { "\($0): \(definition.title)" }
        }.joined(separator: " · ")
    }

    static var wandVoiceGuide: String {
        let shortcuts = all.compactMap { $0.invocation.phrases.min { $0.count < $1.count } }
        return "Say: " + shortcuts.joined(separator: " · ")
    }

    static var voiceHelp: String {
        let phrases = all.compactMap { $0.invocation.phrases.first }
        return (["cast", "shoot"] + phrases).joined(separator: ", ")
    }
}
