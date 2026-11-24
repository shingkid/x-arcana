import Foundation

extension SpellCatalog {
    static let albert: SpellDefinition = SpellDefinition(
        id: .albert, title: "Albert", rune: nil,
        invocation: .voice(.summonAlbert, phrase: "Albert I summon thee", aliases: ["Albert", "summon Albert"]),
        manaCost: 30,
        effect: { context in
            return context.summon(.albert) {
                PortraitSummons.summon(
                    name: "albert", in: context.world.scene,
                    at: context.origin, facing: context.world.camera, environment: context.world.environment)
            }
        },
        presentation: .effectOwned,
        sound: .onCast(.summon, layers: []),
        feedback: "Albert summoned.")
}
