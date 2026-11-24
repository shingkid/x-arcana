import AVFoundation
import OSLog

/// Plays cached spell layers through the user's current system audio output.
actor SpellAudio {
    enum Sound: String, CaseIterable {
        case zap, fireball, ice, shield, summon, sparks, revelio, lumos, patronus, demon, ambience, nyan

        /// These ceilings match the reproducible generator and are checked against the PCM files.
        var peakCeiling: Float {
            switch self {
            case .ambience: return 0.28
            case .nyan: return 0.50
            case .demon: return 0.52
            case .sparks: return 0.40
            default: return 0.64
            }
        }

        var playbackVolume: Float {
            switch self {
            case .ambience: return 0.24
            case .nyan: return 0.52
            case .demon: return 0.52
            case .sparks: return 0.58
            case .revelio, .lumos: return 0.56
            case .fireball: return 0.68
            case .zap: return 0.66
            default: return 0.62
            }
        }
    }

    /// Bound overlapping spell peaks without changing the device volume or audio route.
    static func mixGain(for activeSounds: [Sound]) -> Float {
        let total = activeSounds.filter { $0 != .ambience }.reduce(Float.zero) {
            $0 + $1.peakCeiling * $1.playbackVolume
        }
        // The ambience has a separate peak budget below 0.07, leaving further output headroom.
        return min(1, 0.78 / max(0.001, total))
    }

    private let session = AVAudioSession.sharedInstance()
    private let logger = Logger(subsystem: "XArcana", category: "Audio")
    private var players: [Sound: [AVAudioPlayer]] = [:]
    private var nyanRemaining: Double = 0
    private var nyanPaused = true
    private var nyanNeedsSeek = false
    private var wantsPlayback = false
    private var interrupted = false
    private var observers: [NSObjectProtocol] = []
    private(set) var isActive = false
    private(set) var errorMessage: String?

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    func start() {
        wantsPlayback = true
        guard !isActive, !interrupted else { return }
        if observers.isEmpty { observeSession() }
        do {
            if players.isEmpty { try loadSounds() }
            // Follow the selected output and preserve a voice session that is already recording.
            if session.category != .playAndRecord { try session.setCategory(.playback, mode: .default) }
            try session.setActive(true)
            guard let room = players[.ambience]?.first, room.play() else {
                throw NSError(
                    domain: "XArcanaAudio", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Room ambience could not start."])
            }
            isActive = true
            errorMessage = nil
            applyNyanState()
            let route = session.currentRoute.outputs.map(\.portName).joined(separator: ", ")
            logger.notice("X Arcana audio output: \(route, privacy: .public)")
        } catch {
            report(error)
        }
    }

    func stop() {
        wantsPlayback = false
        stopPlayers()
        do {
            if session.category != .playAndRecord { try session.setActive(false, options: .notifyOthersOnDeactivation) }
        } catch {
            report(error)
        }
    }

    @discardableResult
    func play(_ policy: SpellSoundPolicy) -> Bool {
        guard isActive else { return false }
        switch policy {
        case .simulationTimed(let sound):
            // Only simulation state may start or seek this player.
            return players[sound]?.first != nil
        case .onCast(let first, let layers):
            var played = play(first)
            for sound in layers {
                if !play(sound) { played = false }
            }
            return played
        }
    }

    /// The remaining simulation time owns playback across pause, disconnect, and restarts.
    func syncNyan(remaining: Double, paused: Bool) {
        let next = remaining.isFinite ? max(0, min(SurvivalState.nyanDuration, remaining)) : 0
        if next > 0 && (nyanRemaining <= 0 || next > nyanRemaining + 0.25) {
            nyanNeedsSeek = true
        }
        nyanRemaining = next
        nyanPaused = paused
        applyNyanState()
    }

    // Exposes actual player state for lifecycle tests without adding a second timing model.
    var nyanPlayback: (isPlaying: Bool, elapsed: Double) {
        let player = players[.nyan]?.first
        return (player?.isPlaying ?? false, player?.currentTime ?? 0)
    }

    private func applyNyanState() {
        guard let music = players[.nyan]?.first else { return }
        guard nyanRemaining > 0 else {
            music.stop()
            music.currentTime = 0
            nyanNeedsSeek = false
            rebalance()
            return
        }
        let elapsed = min(music.duration, SurvivalState.nyanDuration - nyanRemaining)
        if nyanPaused || !isActive {
            music.pause()
            if nyanNeedsSeek || abs(music.currentTime - elapsed) > 0.25 { music.currentTime = elapsed }
            nyanNeedsSeek = false
            rebalance()
            return
        }
        // Correct a real discontinuity, not each frame's normal scheduling jitter.
        if nyanNeedsSeek || abs(music.currentTime - elapsed) > 0.25 {
            music.currentTime = elapsed
        }
        nyanNeedsSeek = false
        if !music.isPlaying {
            rebalance(starting: .nyan)
            if !music.play() { errorMessage = "Could not play Nyan Cat." }
        } else {
            rebalance()
        }
    }

    private func rebalance(starting sound: Sound? = nil) {
        let active =
            players.flatMap { kind, voices in
                kind == .ambience ? [] : voices.filter(\.isPlaying).map { _ in kind }
            } + (sound.map { [$0] } ?? [])
        let gain = Self.mixGain(for: active)
        for (kind, voices) in players where kind != .ambience {
            for voice in voices where voice.isPlaying || kind == sound {
                voice.volume = kind.playbackVolume * gain
            }
        }
        players[.ambience]?.first?.volume = active.contains(.nyan) ? 0.07 : Sound.ambience.playbackVolume
    }

    private func loadSounds() throws {
        var loaded: [Sound: [AVAudioPlayer]] = [:]
        for sound in Sound.allCases {
            guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav", subdirectory: "Audio")
            else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "Audio/\(sound.rawValue).wav"])
            }
            let voices = sound == .ambience || sound == .demon || sound == .nyan ? 1 : 3
            loaded[sound] = try (0..<voices).map { _ in
                let player = try AVAudioPlayer(contentsOf: url)
                player.volume = sound.playbackVolume
                player.numberOfLoops = sound == .ambience ? -1 : 0
                guard player.prepareToPlay() else {
                    throw NSError(
                        domain: "XArcanaAudio", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Could not prepare \(sound.rawValue)."])
                }
                return player
            }
        }
        players = loaded
    }

    private func play(_ sound: Sound) -> Bool {
        guard let pool = players[sound],
            let player = pool.first(where: { !$0.isPlaying })
                ?? pool.min(by: {
                    $0.duration - $0.currentTime < $1.duration - $1.currentTime
                })
        else { return false }
        player.stop()
        player.currentTime = 0
        rebalance(starting: sound)
        guard player.play() else {
            errorMessage = "Could not play \(sound.rawValue)."
            logger.error("\(self.errorMessage ?? "Audio failed", privacy: .public)")
            return false
        }
        return true
    }

    private func stopPlayers() {
        for pool in players.values {
            for player in pool {
                player.stop()
                player.currentTime = 0
            }
        }
        isActive = false
    }

    func handleInterruption(_ type: AVAudioSession.InterruptionType, shouldResume: Bool) {
        if type == .began {
            interrupted = true
            stopPlayers()
        } else {
            interrupted = false
            if wantsPlayback && shouldResume { start() }
        }
    }

    private func resetAudio() {
        stopPlayers()
        players.removeAll()
        interrupted = false
        if wantsPlayback { start() }
    }

    private func observeSession() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification, object: session,
                queue: nil
            ) { [weak self] notification in
                guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                    let type = AVAudioSession.InterruptionType(rawValue: raw)
                else { return }
                let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let resume = AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
                Task { await self?.handleInterruption(type, shouldResume: resume) }
            })
        observers.append(
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification, object: session,
                queue: nil
            ) { [weak self] _ in
                Task { await self?.resetAudio() }
            })
    }

    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
        logger.error("\(error.localizedDescription, privacy: .public)")
    }
}
