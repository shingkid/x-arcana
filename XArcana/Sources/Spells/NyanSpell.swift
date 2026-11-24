import Foundation

extension SpellCatalog {
    static let nyan: SpellDefinition = SpellDefinition(
        id: .nyan, title: "Nyan Cat", rune: .nyan,
        invocation: .gestureAndVoice(guide: "W", .nyan, phrase: "Nyan", aliases: ["summon nyan", "nyan cat"]),
        manaCost: 80,
        effect: { context in
            if context.combat.nyan() { return .accepted }
            if context.combat.runSnapshot.nyanRemaining > 0 {
                return .rejected("Nyan Cat is already here. No mana spent.", sparks: false)
            }
            return context.combatResult(false)
        },
        presentation: .effectOwned,
        sound: .simulationTimed(.nyan),
        feedback: "Nyan curse! The horde vanishes when the song ends.")
}
