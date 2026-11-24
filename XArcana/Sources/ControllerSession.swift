import UIKit

#if DEBUG && targetEnvironment(simulator)
    import Network
#endif

/// Owns phone input only. The Mac owns recognition, combat, rendering, and game audio.
@MainActor
final class ControllerSession: NSObject {
    static let shared = ControllerSession()

    var onChange: (() -> Void)?
    private(set) var state = HostState()
    private(set) var isConnected = false
    private(set) var connectionStatus = "Open X Arcana on your Mac."
    private(set) var voiceStatus = "Touch the pad to enable voice."
    private(set) var isHolding = false
    private(set) var status = "Connect to the Mac to cast."
    var isReady: Bool { isConnected && hasHostState && state.ready }
    var canStart: Bool { isReady && state.run?.hasStarted == false }
    var canPlay: Bool {
        isReady && state.run?.isGameOver != true && state.run?.hasStarted != false
            && (state.run?.countdownRemaining ?? 0) <= 0
    }
    var isBow: Bool { state.mode == "bow" }

    private let client = ControllerClient()
    private let motion = WandMotion()
    private let voice = VoiceCommands()
    private let feedback = UIImpactFeedbackGenerator(style: .medium)
    private var clock: CADisplayLink?
    private var voiceEnabled = false
    private var hasHostState = false
    private var nextGesture: UInt64 = 0
    private var gesture: UInt64 = 0
    private var gestureHadMotion = false

    #if DEBUG && targetEnvironment(simulator)
        // UI tests use the real transport against a server in the test runner.
        private var testPort: NWEndpoint.Port? {
            guard let value = ProcessInfo.processInfo.environment["EMBER_CONTROLLER_TEST_PORT"],
                let raw = UInt16(value), raw > 0
            else { return nil }
            return NWEndpoint.Port(rawValue: raw)
        }
    #endif

    private override init() {
        super.init()
        client.onState = { [weak self] state in
            guard let self else { return }
            let modeChanged = self.state.mode != state.mode
            let becameShieldReady = state.shieldReady == true && self.state.shieldReady != true
            self.state = state
            self.hasHostState = true
            if !self.canPlay || modeChanged { self.cancelDrawing() }
            if !self.isHolding { self.status = state.status }
            if self.isHolding, let preview = state.castPreview, !preview.isEmpty { self.status = preview }
            if self.isHolding && becameShieldReady {
                self.feedback.impactOccurred(intensity: 1)
                self.feedback.prepare()
            }
            self.onChange?()
        }
        client.onConnection = { [weak self] connected, message in
            guard let self else { return }
            self.isConnected = connected
            self.connectionStatus = message
            if !connected {
                self.hasHostState = false
                self.cancelDrawing()
                self.state = HostState()
                self.status = "Open X Arcana on your Mac and use the same Wi-Fi network."
            }
            self.onChange?()
        }
        voice.onCommand = { [weak self] command in self?.sendVoice(command) }
        voice.onStatus = { [weak self] message in
            self?.voiceStatus = message
            self?.onChange?()
        }
        motion.onFailure = { [weak self] in
            guard let self else { return }
            self.cancelDrawing()
            self.status = "Motion is unavailable. Tap to cycle setup choices, or cast sparks and shoot during play."
            self.onChange?()
        }
    }

    func start() {
        guard clock == nil else { return }
        motion.start()
        #if DEBUG && targetEnvironment(simulator)
            if let port = testPort {
                client.connect(to: .hostPort(host: "127.0.0.1", port: port))
            } else {
                client.start()
            }
        #else
            client.start()
        #endif
        if voiceEnabled { startVoice() }
        let clock = CADisplayLink(target: self, selector: #selector(sampleMotion))
        clock.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        clock.add(to: .main, forMode: .common)
        self.clock = clock
        feedback.prepare()
    }

    func stop() {
        cancelDrawing()
        clock?.invalidate()
        clock = nil
        motion.stop()
        voice.stop()
        client.stop()
        isConnected = false
        hasHostState = false
        connectionStatus = "Open X Arcana on your Mac."
        status = "Connect to the Mac to cast."
        onChange?()
    }

    private func startVoice() {
        #if DEBUG && targetEnvironment(simulator)
            if testPort != nil { return }
        #endif
        voice.start()
    }

    func beginDrawing() {
        guard clock != nil, !isHolding else { return }
        if !voiceEnabled {
            voiceEnabled = true
            startVoice()
        }
        // The start screen owns confirmation. A single touch must never start a run.
        if canStart { return }
        guard canPlay else {
            if state.run?.isGameOver == true {
                status = "Run ended. Choose Play again."
                onChange?()
                return
            }
            status =
                isConnected
                ? "Wait for the Mac scene to be ready." : "Open X Arcana on your Mac and use the same Wi-Fi network."
            onChange?()
            return
        }
        nextGesture &+= 1
        if nextGesture == 0 { nextGesture = 1 }
        gesture = nextGesture
        guard sendMotion(.begin, gesture: gesture) else { return }
        isHolding = true
        status = isBow ? "Lift to release an arrow." : "Drawing. Lift your finger to cast."
        feedback.impactOccurred(intensity: 0.45)
        feedback.prepare()
        onChange?()
    }

    func endDrawing() {
        guard isHolding else { return }
        let releasedGesture = gesture
        isHolding = false
        gesture = 0
        if sendMotion(.end, gesture: releasedGesture) {
            status = isBow ? "Arrow sent to Mac." : "Rune sent to Mac."
            feedback.impactOccurred()
            feedback.prepare()
        }
        onChange?()
    }

    func cancelDrawing() {
        guard isHolding else { return }
        let cancelledGesture = gesture
        isHolding = false
        gesture = 0
        if isConnected {
            _ = client.send(
                WandInput(
                    kind: .cancel, gesture: cancelledGesture,
                    timestamp: ProcessInfo.processInfo.systemUptime))
        }
        status = "Gesture cancelled. Hold again when ready."
        onChange?()
    }

    func setSeeThrough(_ enabled: Bool) {
        cancelDrawing()
        guard isReady else { return }
        _ = send(
            WandInput(
                kind: .sceneMode, timestamp: ProcessInfo.processInfo.systemUptime,
                seeThrough: enabled))
    }

    func confirmStart() {
        guard clock != nil, canStart else { return }
        if !voiceEnabled {
            voiceEnabled = true
            startVoice()
        }
        _ = send(WandInput(kind: .startRun, timestamp: ProcessInfo.processInfo.systemUptime))
        status = "Confirming the choice in the glasses…"
        onChange?()
    }

    func cycleSetupChoice(forceCycle: Bool = false) {
        guard clock != nil, canStart, state.setupStep != nil else { return }
        _ = send(
            WandInput(
                kind: .nextSetupChoice, timestamp: ProcessInfo.processInfo.systemUptime,
                command: forceCycle ? "cycle" : nil))
    }

    func confirmSetupChoice() {
        guard clock != nil, canStart else { return }
        if !voiceEnabled {
            voiceEnabled = true
            startVoice()
        }
        let kind: WandInput.Kind = state.setupStep == nil ? .startRun : .confirmSetupChoice
        _ = send(WandInput(kind: kind, timestamp: ProcessInfo.processInfo.systemUptime))
    }

    func sendVoice(_ command: VoiceCommand) {
        guard clock != nil, canPlay else { return }
        cancelDrawing()
        _ = send(
            WandInput(
                kind: .voice, timestamp: ProcessInfo.processInfo.systemUptime,
                command: command.rawValue))
    }

    @objc private func sampleMotion() {
        guard canPlay || canStart else { return }
        _ = sendMotion(.sample, gesture: canStart ? 0 : gesture)
    }

    func restartRun() {
        guard isReady, state.run?.hasStarted == true else { return }
        cancelDrawing()
        _ = send(WandInput(kind: .restartRun, timestamp: ProcessInfo.processInfo.systemUptime))
    }

    func resetScores() {
        guard isReady, state.run?.hasStarted == true, state.canResetScores == true else { return }
        cancelDrawing()
        _ = send(WandInput(kind: .resetScores, timestamp: ProcessInfo.processInfo.systemUptime))
    }

    @discardableResult
    private func sendMotion(_ kind: WandInput.Kind, gesture: UInt64) -> Bool {
        let angles = motion.relativeAngles()
        if kind == .begin { gestureHadMotion = angles != nil }
        // A missing motion sample is not a direction. Touch edges still support sparks and bow taps.
        if kind == .sample && angles == nil {
            // A held gesture cannot use cached motion after tracking stops.
            if isHolding && gestureHadMotion { cancelDrawing() }
            return true
        }
        if kind == .sample && isHolding { gestureHadMotion = true }
        return send(
            WandInput(
                kind: kind, gesture: gesture,
                timestamp: ProcessInfo.processInfo.systemUptime,
                yaw: angles?.x, pitch: angles?.y))
    }

    private func send(_ input: WandInput) -> Bool {
        guard client.send(input) else {
            // Failed sends are discarded. A reconnect always requires a fresh touch.
            isHolding = false
            gesture = 0
            status = "Connection interrupted. Open X Arcana on your Mac."
            onChange?()
            return false
        }
        return true
    }
}
