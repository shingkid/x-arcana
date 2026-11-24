import SceneKit
import UIKit

@MainActor
final class Encounter: NSObject {
    static let shared = Encounter()
    private static let aimHint = "Wave without touching to strike. Hold, draw, and release to cast."

    let room = GameWorld()
    lazy var stage = GameStage(room: room)
    let audio = SpellAudio()
    private let startsImmediately: Bool
    private let recordStore: UserDefaults?
    lazy var combat = Combat(
        scene: room.scene, camera: room.camera, environment: room.environment,
        defaults: recordStore, startsImmediately: startsImmediately && room.errorMessage == nil)
    var simulationActive = true {
        didSet {
            combat.setPaused(!simulationActive)
            if !simulationActive {
                resetMovementInput()
                cancelDrawing()
                activeGesture = nil
            }
            syncMusic()
        }
    }
    var runSnapshot: RunSnapshot { combat.runSnapshot }
    var shieldReady: Bool {
        isHolding && spell.preview == .shield && runSnapshot.mana >= SpellCatalog.shield.manaCost
            && (runSnapshot.shieldHealth ?? 0) <= 0
            && runSnapshot.shieldCooldownRemaining <= 0 && !runSnapshot.isGameOver
    }
    var castPreview: String? {
        guard spell.isHolding, !runSnapshot.isGameOver else { return nil }
        guard let kind = spell.preview else { return "Drawing…" }
        if kind == .shield {
            if let health = runSnapshot.shieldHealth, health > 0 {
                return "Shield active · \(health) HP"
            }
            if runSnapshot.shieldCooldownRemaining > 0 {
                return "Shield recovers in \(Int(ceil(runSnapshot.shieldCooldownRemaining)))s"
            }
            if runSnapshot.mana < SpellCatalog.shield.manaCost {
                return "Shield needs \(Int(SpellCatalog.shield.manaCost)) mana"
            }
            return "Shield ready · Release"
        }
        return "\(kind.title) · Release"
    }
    private var bowHeld = false
    private(set) var fightingMode: WandPresentation.Mode = .wand
    private(set) var setupStep = "world"
    var battleStatus: String {
        "\(fightingMode == .wand ? "Wand" : "Bow") · \(combat.remaining) zombies · \(combat.kills) defeated"
    }
    private var spell = Spell()
    var isHolding: Bool { spell.isHolding || bowHeld }
    private(set) var status = Encounter.aimHint
    var onState: (() -> Void)?
    private var remoteAngles: SIMD2<Float>?
    private var remoteTime: TimeInterval = 0
    private var lastIdleMotionAt: TimeInterval?
    private var wandMelee = WandMelee()
    private var activeGesture: UInt64?
    private lazy var performance = ScenePerformance(scene: room.scene, camera: room.camera)
    weak var display: UIView?
    private var clock: CADisplayLink?
    private var lastAnnouncementTime: TimeInterval?
    var desktopInput: (() -> DesktopMovementInput)?
    private var desktopMovement = DesktopMovement()
    private var phoneWalking = PhoneWalking()
    private var pendingPosition: WandInput?
    private var lastPositionArrival: TimeInterval?
    private var meleeWalkingSuspendedUntil: TimeInterval = 0
    var phoneWalkingEnabled = false {
        didSet {
            phoneWalking.reset()
            pendingPosition = nil
            lastPositionArrival = nil
            desktopMovement.reset()
            walkingStatus = phoneWalkingEnabled ? "Phone walking: waiting for camera tracking" : ""
        }
    }
    private(set) var walkingStatus = ""

    func resetDesktopInput() { desktopMovement.reset() }

    func resetMovementInput() {
        resetMeleeInput()
        desktopMovement.reset()
        phoneWalking.rebase()
        pendingPosition = nil
        lastPositionArrival = nil
    }

    func recenterMovement() {
        resetMeleeInput()
        room.centerView()
        phoneWalking.reset()
        pendingPosition = nil
        desktopMovement.reset()
    }

    func updateDesktopMovement(_ input: DesktopMovementInput, deltaTime: TimeInterval) {
        let canMove =
            simulationActive && !room.isHeadTracked && room.errorMessage == nil
            && runSnapshot.hasStarted && runSnapshot.countdownRemaining <= 0 && !runSnapshot.isGameOver
        var accepted = desktopMovement.update(input, enabled: canMove)
        if phoneWalkingEnabled { accepted.move = .zero }
        room.moveDesktop(accepted, deltaTime: deltaTime)
    }

    private func receivePosition(_ input: WandInput) {
        guard let position = input.position else { return }
        let now = CACurrentMediaTime()
        if let lastPositionArrival, now - lastPositionArrival > 0.3 { phoneWalking.rebase() }
        lastPositionArrival = now
        // Preserve quality and origin changes while coalescing buffered position samples.
        if position.quality != .tracking
            || (pendingPosition != nil && pendingPosition?.position?.session != position.session)
        {
            phoneWalking.rebase()
        }
        pendingPosition = input
    }

    func updatePhoneMovement() {
        guard let input = pendingPosition, let position = input.position else { return }
        pendingPosition = nil
        let enabled =
            phoneWalkingEnabled && simulationActive && !isHolding
            && CACurrentMediaTime() >= meleeWalkingSuspendedUntil
            && runSnapshot.hasStarted && runSnapshot.countdownRemaining <= 0 && !runSnapshot.isGameOver
        let displacement = phoneWalking.update(
            position, at: input.timestamp, viewHeading: room.viewHeading, enabled: enabled)
        room.movePlayer(by: displacement)
        let next: String
        switch position.quality {
        case .tracking: next = enabled ? "Phone walking on · camera facing forward" : "Phone walking paused"
        case .suspended: next = "Phone walking paused · lower the wand to your torso"
        case .limited: next = "Phone walking paused · point camera at a well-lit room"
        case .unavailable: next = "Phone walking unavailable · check camera permission"
        }
        if walkingStatus != next {
            walkingStatus = next
            onState?()
        }
    }

    init(startsImmediately: Bool = false, defaults: UserDefaults? = .standard) {
        self.startsImmediately = startsImmediately
        self.recordStore = defaults
        super.init()
    }

    /// Input times belong to the controller clock. Never mix them with the Mac simulation clock.
    func receive(_ input: WandInput) {
        if input.kind == .position {
            receivePosition(input)
            return
        }
        if input.kind == .restartRun {
            restartRun()
            return
        }
        if input.kind == .resetScores {
            resetScores()
            return
        }
        // Idle motion aims the wand and can strike only during unheld wand play.
        if input.kind == .sample, input.gesture == 0 {
            guard clock != nil, simulationActive, activeGesture == nil, !runSnapshot.isGameOver,
                room.errorMessage == nil
            else {
                resetMeleeInput()
                return
            }
            if let yaw = input.yaw, let pitch = input.pitch, yaw.isFinite, pitch.isFinite {
                remoteAngles = SIMD2(yaw, pitch)
                lastIdleMotionAt = CACurrentMediaTime()
            } else {
                remoteAngles = nil
                lastIdleMotionAt = nil
            }
            stage.aimWand(angles: runSnapshot.hasStarted ? remoteAngles : setupAngles)
            let enabled =
                fightingMode == .wand && !isHolding
                && runSnapshot.hasStarted && runSnapshot.countdownRemaining <= 0
            if wandMelee.sample(angles: remoteAngles, at: input.timestamp, enabled: enabled),
                combat.melee(toward: stage.aimedWorldPoint())
            {
                // Arm swings must not become experimental walking displacement.
                meleeWalkingSuspendedUntil = CACurrentMediaTime() + 0.5
                phoneWalking.rebase()
                pendingPosition = nil
                lastPositionArrival = nil
                stage.animateMelee()
                setStatus("Wand strike. Wave again, or hold to draw a spell.")
            }
            return
        }
        if input.kind == .nextSetupChoice || input.kind == .confirmSetupChoice || input.kind == .startRun {
            guard canConfigureSetup else { return }
            if input.kind == .nextSetupChoice {
                stage.aimWand(angles: setupAngles)
                if stage.hasSetupPointer && input.command != "cycle" {
                    guard let index = stage.hoveredSetupChoice else {
                        setStatus("Point at a choice in the glasses, then tap to preview.")
                        return
                    }
                    previewSetupChoice(index)
                } else {
                    previewSetupChoice(
                        setupStep == "world" ? (room.isSeeThrough ? 0 : 1) : (fightingMode == .bow ? 0 : 1))
                }
            } else {
                confirmSetupChoice()
            }
            return
        }
        guard !runSnapshot.isGameOver || input.kind == .cancel || input.kind == .sceneMode else { return }
        guard
            (runSnapshot.hasStarted && runSnapshot.countdownRemaining <= 0) || input.kind == .cancel
                || input.kind == .sceneMode
        else { return }
        if input.kind == .begin || input.kind == .sample || input.kind == .end {
            if let yaw = input.yaw, let pitch = input.pitch, yaw.isFinite, pitch.isFinite {
                remoteAngles = SIMD2(yaw, pitch)
            } else {
                remoteAngles = nil
            }
        }
        switch input.kind {
        case .begin:
            guard activeGesture == nil else { return }
            remoteTime = input.timestamp
            activeGesture = input.gesture
            beginDrawing()
        case .sample:
            guard input.gesture == 0 || input.gesture == activeGesture else { return }
            if input.gesture != 0, input.timestamp >= remoteTime {
                remoteTime = input.timestamp
                spell.sample(remoteAngles, at: remoteTime)
                stage.showRune(points: spell.trace, at: spell.point)
            }
        case .end:
            guard input.gesture == activeGesture else { return }
            remoteTime = max(remoteTime, input.timestamp)
            endDrawing()
            activeGesture = nil
        case .cancel:
            cancelDrawing()
            activeGesture = nil
        case .voice:
            if let value = input.command, let command = VoiceCommand(rawValue: value) { handleVoice(command) }
        case .sceneMode:
            if let enabled = input.seeThrough { setSeeThrough(enabled) }
        case .restartRun, .resetScores, .startRun, .nextSetupChoice, .confirmSetupChoice, .position:
            break
        }
    }

    func controllerDisconnected() {
        wandMelee.reset(newController: true)
        resetMovementInput()
        cancelDrawing()
        activeGesture = nil
        remoteAngles = nil
        lastIdleMotionAt = nil
        stage.clearSetupPointer()
    }

    func prepare(completion: @escaping () -> Void) {
        let nodes =
            ZombieAppearance.prewarm(identities: Combat.identities)
            + RuneEffects.prewarm() + PortraitSummons.prewarm() + SpellVFX.prewarm()
        performance.prepare()
        stage.prepare(nodes: nodes, completion: completion)
    }

    func attach() {
        guard let host = display else { return }
        stage.external = display != nil
        stage.onRestart = { [weak self] in self?.restartRun() }
        stage.onSetupChoice = { [weak self] index, confirm in
            guard let self, self.canConfigureSetup else { return }
            self.previewSetupChoice(index)
            if confirm { self.confirmSetupChoice() }
        }
        if stage.superview !== host {
            cancelDrawing()
            stage.removeFromSuperview()
            stage.frame = host.bounds
            stage.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            host.addSubview(stage)
        }
        refresh()
    }

    func start() {
        guard clock == nil else { return }
        // Combat counters update independently so incoming curses do not erase casting feedback.
        combat.onStatus = { [weak self] _ in self?.onState?() }
        combat.onChange = { [weak self] in self?.runDidChange() }
        combat.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .waveCleared(let wave):
                self.stage.announce(
                    title: "Level \(wave) cleared!", detail: "+250 bonus score · Next level in 20 seconds")
            case .waveStarted(let wave):
                self.stage.announce(
                    title: "Level \(wave)", detail: "Survive the horde · Health and mana full")
            }
        }
        combat.setPaused(!simulationActive)
        Task { await audio.start() }
        let clock = CADisplayLink(target: self, selector: #selector(updateFrame))
        clock.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        clock.add(to: .main, forMode: .common)
        self.clock = clock
        setStatus(runSnapshot.hasStarted ? modeHint : setupHint)
    }

    func stop() {
        resetMovementInput()
        clock?.invalidate()
        clock = nil
        Task { await audio.stop() }
        cancelDrawing()
        activeGesture = nil
        remoteAngles = nil
        lastIdleMotionAt = nil
    }

    func beginDrawing() {
        resetMeleeInput()
        guard clock != nil, simulationActive, !runSnapshot.isGameOver,
            runSnapshot.hasStarted, runSnapshot.countdownRemaining <= 0,
            !isHolding, room.errorMessage == nil
        else { return }
        if fightingMode == .bow {
            bowHeld = true
            setStatus("Lift to release an arrow.")
            return
        }
        stage.aimWand(angles: remoteAngles)
        spell.begin(at: stage.aimedWorldPoint(distance: 2), angles: remoteAngles, time: inputTime)
        stage.showRune(points: spell.trace, at: spell.point)
        setStatus("Drawing. Lift your finger to cast.")
    }

    func endDrawing() {
        guard simulationActive, !runSnapshot.isGameOver else {
            cancelDrawing()
            return
        }
        if bowHeld {
            bowHeld = false
            if combat.shoot(toward: stage.aimedWorldPoint()) {
                stage.animateShot()
                setStatus("Arrow released.")
            } else {
                setStatus("Bow ready. Tap to shoot.")
            }
            return
        }
        guard let result = spell.release(angles: remoteAngles, at: inputTime) else { return }
        stage.showRune(points: [], at: nil)
        castSpell(SpellCatalog.definition(for: result.kind), at: result.point)
    }

    /// Both invocation paths commit gameplay before presentation or sound.
    @discardableResult
    func castSpell(_ definition: SpellDefinition, at point: SIMD3<Float>) -> Bool {
        guard clock != nil, simulationActive, room.errorMessage == nil, !runSnapshot.isGameOver,
            runSnapshot.hasStarted, runSnapshot.countdownRemaining <= 0
        else { return false }
        let context = SpellCastContext(combat: combat, world: room, origin: point, target: stage.aimedWorldPoint())
        switch definition.effect(context) {
        case .accepted:
            definition.presentation.perform(context: context, on: stage)
            Task { await audio.play(definition.sound) }
            setStatus(definition.acceptedFeedback)
            return true
        case .rejected(let message, let sparks):
            if sparks { RuneEffects.sparkBurst(in: room.scene, at: point, facing: room.camera) }
            setStatus(message)
            return false
        }
    }

    func cancelDrawing() {
        resetMeleeInput()
        guard isHolding else { return }
        bowHeld = false
        spell.cancel()
        stage.showRune(points: [], at: nil)
        setStatus(modeHint)
    }

    func setSeeThrough(_ enabled: Bool) {
        cancelDrawing()
        room.setSeeThrough(enabled)
        stage.setNeedsLayout()
        setStatus(enabled ? "See-through AR. Look around from one position." : modeHint)
    }

    @objc private func updateFrame() {
        let now = CACurrentMediaTime()
        let delta = min(0.05, max(0, now - (lastAnnouncementTime ?? now)))
        lastAnnouncementTime = now
        if simulationActive {
            updateDesktopMovement(desktopInput?() ?? DesktopMovementInput(), deltaTime: delta)
            updatePhoneMovement()
            combat.update(at: now)
            if !runSnapshot.isGameOver { stage.advanceAnnouncements(deltaTime: delta) }
        }
        room.setTransfigurationPhase(combat.transfigurationPhase)
        performance.update(at: CACurrentMediaTime())
        stage.showCastPreview(castPreview)
        if !spell.isHolding {
            stage.aimWand(angles: runSnapshot.hasStarted ? remoteAngles : setupAngles)
            return
        }
        stage.showRune(points: spell.trace, at: spell.point)
    }

    func handleVoice(_ command: VoiceCommand) {
        guard clock != nil, simulationActive, !runSnapshot.isGameOver,
            runSnapshot.hasStarted, runSnapshot.countdownRemaining <= 0
        else { return }
        if let definition = SpellCatalog.definition(for: command) {
            cancelDrawing()
            castSpell(definition, at: room.castingPoint())
        } else if command == .cast {
            selectMode(.wand)
        } else if command == .shoot {
            selectMode(.bow)
        }
    }

    func restartRun() {
        beginNewRun(clearRecords: false)
    }

    func resetScores() {
        beginNewRun(clearRecords: true)
    }

    private func beginNewRun(clearRecords: Bool) {
        guard clock != nil, simulationActive, room.errorMessage == nil, runSnapshot.hasStarted else { return }
        cancelDrawing()
        activeGesture = nil
        remoteAngles = nil
        lastIdleMotionAt = nil
        spell = Spell()
        resetMovementInput()
        phoneWalking.reset()
        room.resetPlayerPosition()
        setupStep = "world"
        stage.clearSetupPointer()
        stage.clearAnnouncements()
        if clearRecords { combat.resetScores() } else { combat.restart() }
        room.setSeeThrough(false)
        selectMode(.wand)
        setStatus(setupHint)
    }

    private func runDidChange() {
        room.setTransfigurationPhase(combat.transfigurationPhase)
        if runSnapshot.isGameOver {
            resetMovementInput()
            stage.clearAnnouncements()
            cancelDrawing()
            activeGesture = nil
            status = "YOU DIED. Double-tap your phone to play again."
        } else if !runSnapshot.hasStarted {
            status = setupHint
        } else if runSnapshot.countdownRemaining > 0 {
            cancelDrawing()
            activeGesture = nil
            status = "\(Int(ceil(runSnapshot.countdownRemaining)))…"
        } else if status.hasSuffix("…") || status.hasPrefix("Point the phone") {
            status = modeHint
        }
        syncMusic()
        stage.showRun(runSnapshot)
        refresh()
    }

    private func syncMusic() {
        let remaining = runSnapshot.nyanRemaining
        let paused = !simulationActive || runSnapshot.isGameOver
        Task { await audio.syncNyan(remaining: remaining, paused: paused) }
    }

    private func resetMeleeInput() {
        meleeWalkingSuspendedUntil = 0
        wandMelee.reset()
        stage.resetMelee()
    }

    private var canConfigureSetup: Bool {
        clock != nil && simulationActive && room.errorMessage == nil && !runSnapshot.hasStarted
            && !runSnapshot.isGameOver
    }

    private var setupAngles: SIMD2<Float>? {
        guard let lastIdleMotionAt, CACurrentMediaTime() - lastIdleMotionAt <= 0.35 else { return nil }
        return remoteAngles
    }

    private var setupHint: String {
        let choice = setupStep == "world" ? "world" : "weapon"
        return "Point the phone at a \(choice), then tap to preview. Double-tap to confirm. No motion? Tap to cycle."
    }

    private func previewSetupChoice(_ index: Int) {
        guard canConfigureSetup, (0...1).contains(index) else { return }
        if setupStep == "world" { setSeeThrough(index == 1) } else { selectMode(index == 1 ? .bow : .wand) }
        setStatus(setupHint)
    }

    private func confirmSetupChoice() {
        guard canConfigureSetup else { return }
        if setupStep == "world" {
            setupStep = "weapon"
            setStatus(setupHint)
        } else {
            stage.clearSetupPointer()
            _ = combat.startRun()
        }
    }

    private var inputTime: TimeInterval { activeGesture == nil ? CACurrentMediaTime() : remoteTime }

    func setFrameRate(_ rate: Int) {
        stage.setFrameRate(rate)
        clock?.preferredFrameRateRange = CAFrameRateRange(
            minimum: Float(rate), maximum: Float(rate), preferred: Float(rate))
    }

    private var modeHint: String {
        fightingMode == .wand ? Self.aimHint : "Tap anywhere to shoot. Say ‘cast’ to use the wand."
    }

    private func selectMode(_ mode: WandPresentation.Mode) {
        cancelDrawing()
        fightingMode = mode
        stage.setMode(mode)
        setStatus(modeHint)
    }

    private func setStatus(_ message: String) {
        status = message
        refresh()
    }

    private func refresh() {
        stage.showSetup(step: setupStep, seeThrough: room.isSeeThrough, bow: fightingMode == .bow)
        stage.setCaption(room.errorMessage ?? status)
        stage.showCastPreview(castPreview)
        stage.showRun(runSnapshot)
        onState?()
    }
}
