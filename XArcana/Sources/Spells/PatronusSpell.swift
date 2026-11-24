import Foundation

extension SpellCatalog {
    static let patronus: SpellDefinition = SpellDefinition(
        id: .patronus, title: "Patronus", rune: .patronus,
        invocation: .voice(.summonPatronus, phrase: "summon Patronus", aliases: ["Patronus", "Expecto Patronum"]),
        manaCost: 30,
        effect: { context in
            return context.summon(.patronus) {
                RuneEffects.patronus(in: context.world.scene, at: context.origin, from: context.world.camera)
            }
        },
        presentation: .effectOwned,
        sound: .onCast(.patronus, layers: []),
        feedback: "Patronus charging. Enemies touched are slowed for 15 seconds.")
}
