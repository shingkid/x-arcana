import Foundation

extension SpellCatalog {
    static let demon: SpellDefinition = SpellDefinition(
        id: .demon, title: "Demon", rune: .summon,
        invocation: .gestureAndVoice(guide: "Star", .summonDemon, phrase: "summon demon", aliases: ["demon"]),
        manaCost: 40,
        effect: { context in
            return context.summon(.demon) {
                RuneEffects.summon(
                    in: context.world.scene, at: context.origin,
                    facing: context.world.camera.simdWorldPosition)
            }
        },
        presentation: .effectOwned,
        sound: .onCast(.summon, layers: [.demon]),
        feedback: "Demon summoned.")
}
