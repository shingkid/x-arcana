import Foundation

extension SpellCatalog {
    static let demon: SpellDefinition = SpellDefinition(
        id: .demon, title: "Demon", rune: .summon,
        invocation: .gesture(guide: "Star"),
        manaCost: 0,
        effect: { context in
            return context.summon(.demon) {
                RuneEffects.summon(
                    in: context.world.scene, at: context.origin,
                    facing: context.world.camera.simdWorldPosition)
            }
        },
        presentation: .effectOwned,
        sound: .onCast(.summon, layers: [.demon]),
        feedback: "Demon summoned. 20 MP per second for up to 5 seconds.")
}
