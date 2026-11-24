import Foundation

extension SpellCatalog {
    static let nyan: SpellDefinition = SpellDefinition(
        id: .nyan, title: "Nyan Cat", rune: .nyan,
        invocation: .voice(.nyan, phrase: "nyan nyan", aliases: []),
        manaCost: 80,
        effect: { context in
            if context.combat.nyan() { return .accepted }
            if context.combat.runSnapshot.nyanRemaining > 0 {
                return .rejected("Nyan Cat is already here. No mana spent.", sparks: false)
            }
            if context.combat.runSnapshot.nyanKillsSinceCast < 20 {
                return .rejected(
                    "Nyan needs \(20 - context.combat.runSnapshot.nyanKillsSinceCast) more defeats. No mana spent.",
                    sparks: false)
            }
            return context.combatResult(false)
        },
        presentation: .effectOwned,
        sound: .simulationTimed(.nyan),
        feedback: "Nyan curse! Transformed zombies vanish when the song ends.")
}
