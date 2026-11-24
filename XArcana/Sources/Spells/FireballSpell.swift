import Foundation

extension SpellCatalog {
    static let fireball: SpellDefinition = SpellDefinition(
        id: .fireball, title: "Fireball", rune: .fireball,
        invocation: .gesture(guide: "O"),
        manaCost: 15,
        effect: { context in
            return context.combatResult(context.combat.fireball(toward: context.target))
        },
        presentation: .effectOwned,
        sound: .onCast(.fireball, layers: []),
        feedback: "Fireball cast.")
}
