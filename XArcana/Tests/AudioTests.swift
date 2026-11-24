import AVFoundation
import XCTest

@testable import XArcana

final class AudioTests: XCTestCase {
    func testEveryBundledSoundDecodesAndContainsAudibleSamples() throws {
        for sound in SpellAudio.Sound.allCases {
            let url = try XCTUnwrap(
                Bundle.main.url(forResource: sound.rawValue, withExtension: "wav", subdirectory: "Audio"))
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            XCTAssertEqual(format.sampleRate, 24000)
            XCTAssertEqual(format.channelCount, sound == .ambience || sound == .nyan ? 2 : 1)
            let buffer = try XCTUnwrap(
                AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: buffer)
            let channels = try XCTUnwrap(buffer.floatChannelData)
            for index in 0..<Int(format.channelCount) {
                let samples = UnsafeBufferPointer(start: channels[index], count: Int(buffer.frameLength))
                XCTAssertTrue(
                    samples.allSatisfy { $0.isFinite && abs($0) <= sound.peakCeiling + 0.00004 }, sound.rawValue)
                let meanSquare = samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count)
                XCTAssertGreaterThan(meanSquare, 0.00001, sound.rawValue)
                let rmsLimit: Double =
                    sound == .ambience
                    ? 0.06 : (sound == .nyan ? 0.14 : (sound == .demon ? 0.12 : (sound == .sparks ? 0.10 : 0.16)))
                XCTAssertLessThanOrEqual(sqrt(meanSquare), rmsLimit + 0.0001, sound.rawValue)
                if sound == .ambience {
                    XCTAssertEqual(Double(file.length) / format.sampleRate, 32, accuracy: 0.001)
                    XCTAssertLessThan(abs(samples.first! - samples.last!), 0.01, "Room loop must have no abrupt seam.")
                } else {
                    if sound == .nyan {
                        XCTAssertEqual(Double(file.length) / format.sampleRate, 27, accuracy: 0.001)
                    } else {
                        XCTAssertTrue((0.5...4).contains(Double(file.length) / format.sampleRate), sound.rawValue)
                    }
                    XCTAssertLessThan(abs(samples.first!), 0.001, "Click-free attack: \(sound.rawValue)")
                    XCTAssertLessThan(abs(samples.last!), 0.001, "Click-free ending: \(sound.rawValue)")
                }
            }
        }
    }

    func testIceAndShieldHaveTheirOwnSounds() throws {
        XCTAssertEqual(SpellCatalog.definition(for: .ice).sound.sounds, [.ice])
        XCTAssertEqual(SpellCatalog.definition(for: .shield).sound.sounds, [.shield])
        let pairs: [(SpellAudio.Sound, SpellAudio.Sound)] = [(.ice, .revelio), (.shield, .lumos)]
        for (new, former) in pairs {
            let newURL = try XCTUnwrap(
                Bundle.main.url(forResource: new.rawValue, withExtension: "wav", subdirectory: "Audio"))
            let formerURL = try XCTUnwrap(
                Bundle.main.url(forResource: former.rawValue, withExtension: "wav", subdirectory: "Audio"))
            XCTAssertNotEqual(try Data(contentsOf: newURL), try Data(contentsOf: formerURL))
        }
    }

    func testOnlyDemonSummonsIncludeTheGrowl() {
        XCTAssertEqual(SpellCatalog.summon(.alan).sound.sounds, [.summon])
        XCTAssertEqual(SpellCatalog.summon(.albert).sound.sounds, [.summon])
        XCTAssertEqual(SpellCatalog.summon(.demon).sound.sounds, [.summon, .demon])
        XCTAssertEqual(SpellCatalog.summon(.patronus).sound.sounds, [.patronus])
    }

    func testOverlappingCastsKeepSharedHeadroomWithoutAmplifyingSingleCasts() {
        XCTAssertEqual(SpellAudio.mixGain(for: [.zap]), 1)
        for count in [2, 3, 6, 12, 30] {
            let sounds = (0..<count).map { SpellAudio.Sound.allCases[$0 % SpellAudio.Sound.allCases.count] }
            let gain = SpellAudio.mixGain(for: sounds)
            let peak = sounds.filter { $0 != .ambience }.reduce(Float.zero) {
                $0 + $1.peakCeiling * $1.playbackVolume * gain
            }
            XCTAssertGreaterThan(gain, 0)
            XCTAssertLessThanOrEqual(gain, 1)
            XCTAssertLessThanOrEqual(peak, 0.78001)
            XCTAssertLessThan(
                peak + SpellAudio.Sound.ambience.peakCeiling * SpellAudio.Sound.ambience.playbackVolume, 0.85)
        }
    }

    @MainActor
    func testNyanMusicFollowsSimulationPauseEndAndRestart() async throws {
        let audio = SpellAudio()
        await audio.syncNyan(remaining: SurvivalState.nyanDuration, paused: true)
        await audio.start()
        var state = await audio.nyanPlayback
        XCTAssertFalse(state.isPlaying)
        let accepted = await audio.play(SpellCatalog.nyan.sound)
        XCTAssertTrue(accepted)
        state = await audio.nyanPlayback
        XCTAssertFalse(state.isPlaying, "A cast acknowledgment must not start an independent song.")

        await audio.syncNyan(remaining: SurvivalState.nyanDuration, paused: false)
        try await Task.sleep(for: .milliseconds(100))
        state = await audio.nyanPlayback
        XCTAssertTrue(state.isPlaying)
        XCTAssertGreaterThan(state.elapsed, 0.03)
        let elapsed = state.elapsed
        // Normal repeated updates must preserve the active player rather than restart at zero.
        await audio.syncNyan(remaining: SurvivalState.nyanDuration, paused: false)
        state = await audio.nyanPlayback
        XCTAssertGreaterThanOrEqual(state.elapsed, elapsed - 0.01)

        await audio.syncNyan(remaining: SurvivalState.nyanDuration - 7, paused: true)
        let paused = await audio.nyanPlayback
        XCTAssertFalse(paused.isPlaying)
        XCTAssertEqual(paused.elapsed, 7, accuracy: 0.02)
        try await Task.sleep(for: .milliseconds(70))
        state = await audio.nyanPlayback
        XCTAssertEqual(state.elapsed, paused.elapsed, accuracy: 0.01)
        await audio.syncNyan(remaining: SurvivalState.nyanDuration - 7, paused: false)
        state = await audio.nyanPlayback
        XCTAssertTrue(state.isPlaying)
        XCTAssertEqual(state.elapsed, 7, accuracy: 0.1)

        await audio.handleInterruption(.began, shouldResume: false)
        state = await audio.nyanPlayback
        XCTAssertFalse(state.isPlaying)
        await audio.syncNyan(remaining: SurvivalState.nyanDuration - 8, paused: false)
        await audio.handleInterruption(.ended, shouldResume: true)
        state = await audio.nyanPlayback
        XCTAssertTrue(state.isPlaying)
        XCTAssertEqual(state.elapsed, 8, accuracy: 0.1)

        await audio.syncNyan(remaining: SurvivalState.nyanDuration, paused: false)
        state = await audio.nyanPlayback
        XCTAssertTrue(state.isPlaying)
        XCTAssertLessThan(state.elapsed, 0.1, "A new effect resets the excerpt.")
        await audio.syncNyan(remaining: 1, paused: false)
        state = await audio.nyanPlayback
        XCTAssertTrue(state.isPlaying, "The song must still play after the former twenty-second cutoff.")
        XCTAssertEqual(state.elapsed, 26, accuracy: 0.1)
        await audio.syncNyan(remaining: 0, paused: false)
        state = await audio.nyanPlayback
        XCTAssertFalse(state.isPlaying)
        XCTAssertEqual(state.elapsed, 0)
        await audio.syncNyan(remaining: .nan, paused: false)
        state = await audio.nyanPlayback
        XCTAssertFalse(state.isPlaying)
        await audio.stop()
        await audio.syncNyan(remaining: SurvivalState.nyanDuration - 1, paused: false)
        state = await audio.nyanPlayback
        XCTAssertFalse(state.isPlaying, "A late state update must not restart a stopped audio session.")
        await audio.syncNyan(remaining: 0, paused: true)
    }

    @MainActor
    func testAllSpellsPlayRapidCastsAndResumeAfterInterruption() async throws {
        let audio = Encounter.shared.audio
        await audio.stop()
        await audio.start()
        let started = await audio.isActive
        let startError = await audio.errorMessage
        XCTAssertTrue(started, startError ?? "Audio session did not start.")
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)
        for kind in RuneKind.allCases {
            for _ in 0..<5 {
                let played = await audio.play(SpellCatalog.definition(for: kind).sound)
                XCTAssertTrue(played, kind.title)
            }
        }
        let sparksPlayed = await audio.play(SpellCatalog.sparks.sound)
        for kind: SummonKind in [.alan, .albert, .demon, .patronus] {
            let summoned = await audio.play(SpellCatalog.summon(kind).sound)
            XCTAssertTrue(summoned)
        }
        let playbackError = await audio.errorMessage
        XCTAssertTrue(sparksPlayed)
        XCTAssertNil(playbackError)

        await audio.handleInterruption(.began, shouldResume: false)
        let interrupted = await audio.isActive
        let castWhileInterrupted = await audio.play(SpellCatalog.demon.sound)
        XCTAssertFalse(interrupted)
        XCTAssertFalse(castWhileInterrupted)
        await audio.handleInterruption(.ended, shouldResume: true)
        let resumed = await audio.isActive
        let demonPlayed = await audio.play(SpellCatalog.demon.sound)
        XCTAssertTrue(resumed)
        XCTAssertTrue(demonPlayed)
        await audio.stop()
        let stopped = await audio.isActive
        let castAfterStop = await audio.play(SpellCatalog.lightning.sound)
        XCTAssertFalse(stopped)
        XCTAssertFalse(castAfterStop)
        // A late notification must not restart sound after the player leaves the room.
        await audio.handleInterruption(.ended, shouldResume: true)
        let remainedStopped = await audio.isActive
        XCTAssertFalse(remainedStopped)
    }
}
