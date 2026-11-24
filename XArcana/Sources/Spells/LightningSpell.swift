import Foundation

extension SpellCatalog {
    static let lightning: SpellDefinition = SpellDefinition(
        id: .lightning, title: "Zap", rune: .zap,
        invocation: .gesture(guide: "Z"),
        manaCost: 5,
        effect: { context in
            return context.combatResult(context.combat.cast(toward: context.target))
        },
        presentation: .effectOwned,
        sound: .onCast(.zap, layers: []),
        feedback: "Zap cast.")
}
