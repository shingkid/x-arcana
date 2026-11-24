import Foundation

extension SpellCatalog {
    static let ice: SpellDefinition = SpellDefinition(
        id: .ice, title: "Ice", rune: .ice,
        invocation: .gesture(guide: "V"),
        manaCost: 15,
        effect: { context in
            return context.combatResult(context.combat.ice(toward: context.target))
        },
        presentation: .effectOwned,
        sound: .onCast(.ice, layers: []),
        feedback: "Ice cast. Enemies in the cone are slowed.")
}
