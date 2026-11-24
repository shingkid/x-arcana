import Foundation

extension SpellCatalog {
    static let lumos: SpellDefinition = SpellDefinition(
        id: .lumos, title: "Lumos", rune: .lumos,
        invocation: .voice(.lumos, phrase: "Lumos", aliases: []),
        manaCost: 0,
        effect: { context in
            context.world.performRune(.lumos, at: context.origin)
            return .accepted
        },
        presentation: .effectOwned,
        sound: .onCast(.lumos, layers: []),
        feedback: "Lumos lit the room.")
}
