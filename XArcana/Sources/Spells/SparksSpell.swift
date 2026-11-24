import Foundation

extension SpellCatalog {
    static let sparks: SpellDefinition = SpellDefinition(
        id: .sparks, title: "Sparks", rune: nil,
        invocation: .unrecognizedStroke,
        manaCost: 0,
        effect: { _ in .accepted },
        presentation: .onAccepted { context in
            context.world.performRune(nil, at: context.origin)
        },
        sound: .onCast(.sparks, layers: []),
        feedback: "Sparks cast.")
}
