import Foundation

extension SpellCatalog {
    static let alan: SpellDefinition = SpellDefinition(
        id: .alan, title: "Alan", rune: nil,
        invocation: .voice(.summonAlan, phrase: "Alan I summon thee", aliases: ["Alan", "summon Alan"]),
        manaCost: 25,
        effect: { context in
            return context.summon(.alan) {
                PortraitSummons.summon(
                    name: "alan", in: context.world.scene,
                    at: context.origin, facing: context.world.camera, environment: context.world.environment)
            }
        },
        presentation: .effectOwned,
        sound: .onCast(.summon, layers: []),
        feedback: "Alan summoned.")
}
