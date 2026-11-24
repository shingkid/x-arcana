import Foundation

extension SpellCatalog {
    static let shield: SpellDefinition = SpellDefinition(
        id: .shield, title: "Shield", rune: .shield,
        invocation: .gesture(guide: "Hold still for one second"),
        manaCost: 20,
        effect: { context in
            if context.combat.shield() { return .accepted }
            if let health = context.combat.runSnapshot.shieldHealth, health > 0 {
                return .rejected("Shield already active with \(health) HP.", sparks: true)
            }
            return .rejected(
                context.combat.lastRejection == .insufficientMana
                    ? "Shield needs \(Int(SpellCatalog.shield.manaCost)) mana."
                    : "Shield recovers in \(Int(ceil(context.combat.runSnapshot.shieldCooldownRemaining))) seconds.",
                sparks: true)
        },
        presentation: .effectOwned,
        sound: .onCast(.shield, layers: []),
        feedback: "Shield adds 20 protective HP until consumed.")
}
