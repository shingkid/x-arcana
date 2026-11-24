import Foundation

extension SpellCatalog {
    static let revelio: SpellDefinition = SpellDefinition(
        id: .revelio, title: "Revelio", rune: .revelio,
        invocation: .voice(.revelio, phrase: "Revelio", aliases: []),
        manaCost: 0,
        effect: { context in
            context.world.performRune(.revelio, at: context.origin)
            return .accepted
        },
        presentation: .effectOwned,
        sound: .onCast(.revelio, layers: []),
        feedback: "Hidden writing revealed.")
}
