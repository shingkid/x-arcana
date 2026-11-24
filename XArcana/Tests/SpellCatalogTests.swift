import SceneKit
import XCTest

@testable import XArcana

final class SpellCatalogTests: XCTestCase {
    func testEverySpellRuneCommandAndSoundHasOneCompleteDefinition() throws {
        XCTAssertEqual(Set(SpellCatalog.all.map(\.id)), Set(SpellID.allCases))
        XCTAssertEqual(SpellCatalog.all.count, SpellID.allCases.count)
        XCTAssertEqual(Set(SpellCatalog.all.compactMap(\.rune)), Set(RuneKind.allCases))
        XCTAssertEqual(SpellCatalog.all.compactMap(\.rune).count, RuneKind.allCases.count)
        let commands = SpellCatalog.all.compactMap(\.invocation.command)
        XCTAssertEqual(
            Set(commands), Set(VoiceCommand.allCases.filter { $0 != .cast && $0 != .shoot && $0 != .summonDemon }))
        XCTAssertEqual(Set(commands).count, commands.count)
        let aliases = SpellCatalog.voiceAliases.map { VoiceCommandParser.normalize($0.phrase) }
        XCTAssertEqual(Set(aliases).count, aliases.count)
        for spell in SpellCatalog.all {
            XCTAssertFalse(spell.title.isEmpty)
            XCTAssertFalse(spell.feedback.isEmpty)
            XCTAssertTrue(spell.manaCost.isFinite && spell.manaCost >= 0)
            XCTAssertFalse(spell.sound.sounds.isEmpty)
            for sound in spell.sound.sounds {
                XCTAssertNotNil(
                    Bundle.main.url(forResource: sound.rawValue, withExtension: "wav", subdirectory: "Audio"),
                    "Missing \(spell.id.rawValue) sound: \(sound.rawValue)")
            }
        }
        guard case .simulationTimed(.nyan) = SpellCatalog.nyan.sound else {
            return XCTFail("Nyan music must follow simulation time.")
        }
        for kind in SummonKind.allCases {
            XCTAssertEqual(SpellCatalog.summon(kind).manaCost, kind == .demon ? 0 : kind.manaCost)
        }
    }

    func testAllDeclaredVoiceAliasesParseOnceIncludingPunctuationAndExactNyanPhrase() {
        for alias in SpellCatalog.voiceAliases {
            var parser = VoiceCommandParser()
            let phrase = "Please " + alias.phrase.replacingOccurrences(of: " ", with: ", ") + "!"
            XCTAssertEqual(parser.consume(phrase), [alias.command], alias.phrase)
            XCTAssertTrue(parser.consume(phrase).isEmpty, alias.phrase)
        }
        for oldPhrase in ["Nyan", "Summon nyan", "Nyan cat"] {
            var parser = VoiceCommandParser()
            XCTAssertTrue(parser.consume(oldPhrase).isEmpty)
        }
        var parser = VoiceCommandParser()
        XCTAssertEqual(parser.consume("Nyan nyan!"), [.nyan])
        XCTAssertTrue(parser.consume("Nyan nyan!").isEmpty)
        XCTAssertEqual(SpellCatalog.nyan.invocation.phrases, ["nyan nyan"])
        XCTAssertFalse(SpellCatalog.nyan.invocation.hasGesture)
        XCTAssertEqual(VoiceCommand(rawValue: "summonDemon"), .summonDemon)
        XCTAssertEqual(VoiceCommand(rawValue: "summonPatronus"), .summonPatronus)
        XCTAssertEqual(VoiceCommand(rawValue: "cast"), .cast)
        XCTAssertEqual(VoiceCommand(rawValue: "shoot"), .shoot)
    }

    func testSecretSpellsStayOutOfEveryGuideWithoutChangingInvocations() {
        for guide in [SpellCatalog.wandGestureGuide, SpellCatalog.wandVoiceGuide, SpellCatalog.voiceHelp] {
            for name in ["demon", "nyan", "alan", "albert"] {
                XCTAssertFalse(guide.lowercased().contains(name), "\(name) appeared in \(guide)")
            }
        }
        XCTAssertTrue(SpellCatalog.wandGestureGuide.contains(SpellCatalog.lightning.title))
        XCTAssertTrue(SpellCatalog.wandVoiceGuide.lowercased().contains("patronus"))
        XCTAssertTrue(SpellCatalog.voiceHelp.contains("cast, shoot"))
        XCTAssertTrue(SpellCatalog.gestureRunes.contains(.summon))
        XCTAssertEqual(SpellCatalog.definition(for: VoiceCommand.summonAlan)?.id, .alan)
        XCTAssertEqual(SpellCatalog.definition(for: VoiceCommand.summonAlbert)?.id, .albert)
        var parser = VoiceCommandParser()
        XCTAssertEqual(parser.consume("Alan. Albert. Nyan nyan!"), [.summonAlan, .summonAlbert, .nyan])
    }

    func testDemonUsesOnlyStarWhileLegacyWireValueStaysReadable() {
        XCTAssertEqual(SpellCatalog.definition(for: .summon).id, .demon)
        XCTAssertEqual(SpellCatalog.demon.invocation.gestureGuide, "Star")
        XCTAssertNil(SpellCatalog.demon.invocation.command)
        XCTAssertNil(SpellCatalog.definition(for: VoiceCommand.summonDemon))
        XCTAssertEqual(VoiceCommand(rawValue: "summonDemon"), .summonDemon)
        XCTAssertEqual(SpellCatalog.demon.manaCost, 0)
        XCTAssertFalse(SpellCatalog.demon.acceptedFeedback.contains("-0 MP"))
        var parser = VoiceCommandParser()
        XCTAssertTrue(parser.consume("Demon. Summon demon!").isEmpty)
    }

    @MainActor
    private func host(state: SurvivalState? = nil) -> Encounter {
        let game = Encounter(startsImmediately: true, defaults: nil, state: state)
        game.stage.frame = CGRect(x: 0, y: 0, width: 640, height: 360)
        game.stage.layoutIfNeeded()
        game.start()
        return game
    }

    @MainActor
    func testAcceptedCastRunsRequiredCustomAnimationAfterEffectAndRejectionDoesNotAnimate() throws {
        let game = host()
        defer { game.stop() }
        let tip = try XCTUnwrap(game.room.camera.childNode(withName: "wandTip", recursively: true))
        var order: [String] = []
        var accepts = true
        let spell = SpellDefinition(
            id: .sparks, title: "Test", rune: nil, invocation: .unrecognizedStroke, manaCost: 0,
            effect: { _ in
                order.append("effect")
                return accepts ? .accepted : .rejected("Rejected", sparks: false)
            },
            presentation: .onAccepted { _ in order.append("animation") },
            sound: .onCast(.sparks, layers: []), feedback: "Accepted")
        XCTAssertTrue(game.castSpell(spell, at: game.room.castingPoint()))
        XCTAssertEqual(order, ["effect", "animation"])
        XCTAssertNotNil(tip.action(forKey: "cast"))
        tip.removeAction(forKey: "cast")
        accepts = false
        XCTAssertFalse(game.castSpell(spell, at: game.room.castingPoint()))
        XCTAssertEqual(order, ["effect", "animation", "effect"])
        XCTAssertNil(tip.action(forKey: "cast"))
        XCTAssertEqual(game.status, "Rejected")
        XCTAssertEqual(game.runSnapshot.mana, 100)
        game.simulationActive = false
        XCTAssertFalse(game.castSpell(spell, at: game.room.castingPoint()))
        XCTAssertEqual(order.count, 3)
    }

    @MainActor
    func testInvalidTargetRejectsBuiltInEffectBeforeManaAndCustomAnimation() throws {
        let game = host()
        defer { game.stop() }
        let tip = try XCTUnwrap(game.room.camera.childNode(withName: "wandTip", recursively: true))
        var animations = 0
        let invalidSpell = SpellDefinition(
            id: .lightning, title: "Invalid target", rune: .zap, invocation: .gesture(guide: "Z"),
            manaCost: SpellCatalog.lightning.manaCost,
            effect: { context in
                let invalid = SpellCastContext(
                    combat: context.combat, world: context.world,
                    origin: context.origin, target: SIMD3(.nan, 0, 0))
                return SpellCatalog.lightning.effect(invalid)
            },
            presentation: .onAccepted { _ in animations += 1 },
            sound: SpellCatalog.lightning.sound, feedback: "Should not cast")
        XCTAssertFalse(game.castSpell(invalidSpell, at: game.room.castingPoint()))
        XCTAssertEqual(game.combat.lastRejection, .invalidTarget)
        XCTAssertEqual(game.runSnapshot.mana, 100)
        XCTAssertEqual(animations, 0)
        XCTAssertNil(tip.action(forKey: "cast"))
        XCTAssertFalse(game.status.contains("MP"))
    }

    @MainActor
    func testElementalDispatchSpendsDeclaredCostOnceAndCooldownDoesNotSpend() throws {
        let game = host()
        defer { game.stop() }
        let point = game.room.castingPoint()
        let tip = try XCTUnwrap(game.room.camera.childNode(withName: "wandTip", recursively: true))
        game.combat.update(at: 0)
        XCTAssertTrue(game.castSpell(SpellCatalog.lightning, at: point))
        XCTAssertEqual(game.runSnapshot.mana, 95)
        XCTAssertTrue(game.status.hasSuffix("-5 MP"))
        tip.removeAction(forKey: "cast")
        XCTAssertFalse(game.castSpell(SpellCatalog.fireball, at: point))
        XCTAssertEqual(game.runSnapshot.mana, 95)
        XCTAssertNil(tip.action(forKey: "cast"))
        for step in 1...6 { game.combat.update(at: Double(step) * 0.05) }
        XCTAssertTrue(game.castSpell(SpellCatalog.fireball, at: point))
        XCTAssertEqual(game.runSnapshot.mana, 80)
        XCTAssertTrue(game.status.hasSuffix("-15 MP"))
        for step in 7...12 { game.combat.update(at: Double(step) * 0.05) }
        XCTAssertTrue(game.castSpell(SpellCatalog.ice, at: point))
        XCTAssertEqual(game.runSnapshot.mana, 65)
        XCTAssertTrue(game.status.hasSuffix("-15 MP"))
        XCTAssertTrue(game.castSpell(SpellCatalog.shield, at: point))
        XCTAssertEqual(game.runSnapshot.mana, 45)
    }

    @MainActor
    func testDuplicateShieldAndSummonAndUnaffordableSummonDoNotSpendOrAnimate() throws {
        let game = host()
        defer { game.stop() }
        let point = game.room.castingPoint()
        let tip = try XCTUnwrap(game.room.camera.childNode(withName: "wandTip", recursively: true))
        XCTAssertTrue(game.castSpell(SpellCatalog.shield, at: point))
        XCTAssertEqual(game.runSnapshot.mana, 80)
        XCTAssertTrue(game.status.hasSuffix("-20 MP"))
        tip.removeAction(forKey: "cast")
        XCTAssertFalse(game.castSpell(SpellCatalog.shield, at: point))
        XCTAssertEqual(game.runSnapshot.mana, 80)
        XCTAssertNil(tip.action(forKey: "cast"))
        game.handleVoice(.summonAlbert)
        XCTAssertEqual(game.runSnapshot.mana, 50)
        tip.removeAction(forKey: "cast")
        game.handleVoice(.summonAlbert)
        XCTAssertEqual(game.runSnapshot.mana, 50)
        XCTAssertNil(tip.action(forKey: "cast"))
        game.handleVoice(.summonAlan)
        XCTAssertEqual(game.runSnapshot.mana, 25)
        tip.removeAction(forKey: "cast")
        game.handleVoice(.summonPatronus)
        XCTAssertEqual(game.runSnapshot.mana, 25)
        XCTAssertNil(tip.action(forKey: "cast"))
        XCTAssertTrue(game.status.contains("Patronus needs 30"))
        XCTAssertEqual(game.room.scene.rootNode.childNodes.filter { $0.name?.hasPrefix("summon.") == true }.count, 2)
    }

    @MainActor
    func testStarDemonStartsWithoutUpfrontCostAndDuplicateAndVoiceDoNotSpend() throws {
        let game = host()
        defer { game.stop() }
        let point = game.room.castingPoint()
        let tip = try XCTUnwrap(game.room.camera.childNode(withName: "wandTip", recursively: true))
        XCTAssertTrue(game.castSpell(SpellCatalog.definition(for: .summon), at: point))
        XCTAssertEqual(game.runSnapshot.mana, 100)
        XCTAssertEqual(game.status, SpellCatalog.demon.acceptedFeedback)
        tip.removeAction(forKey: "cast")
        XCTAssertFalse(game.castSpell(SpellCatalog.demon, at: point))
        XCTAssertEqual(game.runSnapshot.mana, 100)
        XCTAssertNil(tip.action(forKey: "cast"))
        game.handleVoice(.summonDemon)
        XCTAssertEqual(game.runSnapshot.mana, 100)
        XCTAssertNil(tip.action(forKey: "cast"))
    }

    @MainActor
    func testNyanVoiceUsesCatalogDefinitionAndDuplicateDoesNotRestartOrSpend() throws {
        let state = SurvivalState(defaults: nil)
        for _ in 0..<20 { state.recordKill() }
        let game = host(state: state)
        defer { game.stop() }
        let tip = try XCTUnwrap(game.room.camera.childNode(withName: "wandTip", recursively: true))
        game.handleVoice(.nyan)
        XCTAssertEqual(game.runSnapshot.mana, 20)
        XCTAssertEqual(game.runSnapshot.nyanRemaining, 27)
        XCTAssertEqual(game.status, SpellCatalog.nyan.acceptedFeedback)
        tip.removeAction(forKey: "cast")
        XCTAssertFalse(game.castSpell(SpellCatalog.definition(for: .nyan), at: game.room.castingPoint()))
        XCTAssertEqual(game.runSnapshot.mana, 20)
        XCTAssertEqual(game.runSnapshot.nyanRemaining, 27)
        XCTAssertNil(tip.action(forKey: "cast"))
        XCTAssertEqual(game.status, "Nyan Cat is already here. No mana spent.")
        XCTAssertFalse(game.status.contains("-80 MP"))
    }
}
