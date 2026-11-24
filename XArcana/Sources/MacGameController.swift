#if targetEnvironment(macCatalyst)
    import GameController
    import UIKit

    /// The world outlives controller connections and Mac window focus changes.
    @MainActor
    final class MacGameController: UIViewController {
        private let encounter = Encounter.shared
        private let server = ControllerServer()
        private lazy var head = HeadLink(room: encounter.room) { [weak self] in self?.publish() }
        private let connectionLabel = UILabel()
        private let metricsLabel = UILabel()
        private let movementLabel = UILabel()
        private let walking = UIButton(type: .system)
        private let rate = UISegmentedControl(items: ["60 fps", "120 fps"])
        private var connected = false
        private var ready = false
        private var heartbeat: Timer?

        override func viewDidLoad() {
            super.viewDidLoad()
            overrideUserInterfaceStyle = .dark
            // Black emits no light on the Air 2; the room is seen through its lenses.
            view.backgroundColor = .black
            view.tintColor = Palette.gold
            encounter.simulationActive = false
            encounter.display = view
            encounter.attach()
            encounter.stage.accessibilityIdentifier = "macGameWorld"
            encounter.onState = { [weak self] in self?.publish() }
            encounter.desktopInput = { [weak self] in self?.readDesktopInput() ?? DesktopMovementInput() }
            let bar = UIStackView()
            bar.axis = .horizontal
            bar.alignment = .center
            bar.spacing = 18
            bar.backgroundColor = Palette.ink.withAlphaComponent(0.9)
            bar.isLayoutMarginsRelativeArrangement = true
            bar.layoutMargins = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
            bar.layer.cornerRadius = 10
            bar.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(bar)
            connectionLabel.textColor = Palette.paper
            connectionLabel.font = .systemFont(ofSize: 14, weight: .medium)
            connectionLabel.numberOfLines = 2
            connectionLabel.accessibilityIdentifier = "macConnection"
            bar.addArrangedSubview(connectionLabel)
            let spacer = UIView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            bar.addArrangedSubview(spacer)
            metricsLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            metricsLabel.textColor = Palette.muted
            metricsLabel.accessibilityIdentifier = "frameRate"
            bar.addArrangedSubview(metricsLabel)
            rate.selectedSegmentIndex = 0
            rate.addTarget(self, action: #selector(changeRate), for: .valueChanged)
            rate.accessibilityIdentifier = "renderRate"
            rate.setContentHuggingPriority(.required, for: .horizontal)
            bar.addArrangedSubview(rate)
            walking.setTitle("Phone walking: off", for: .normal)
            walking.accessibilityIdentifier = "phoneWalking"
            walking.accessibilityHint =
                "Experimental camera tracking. Hold the phone near your torso with its rear camera facing forward. Movement pauses while drawing."
            walking.addTarget(self, action: #selector(toggleWalking), for: .touchUpInside)
            walking.setContentHuggingPriority(.required, for: .horizontal)
            bar.addArrangedSubview(walking)
            let center = UIButton(type: .system)
            center.setTitle("Center view", for: .normal)
            center.addTarget(self, action: #selector(centerView), for: .touchUpInside)
            bar.addArrangedSubview(center)
            NSLayoutConstraint.activate([
                bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
                bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            ])
            movementLabel.font = .systemFont(ofSize: 12, weight: .medium)
            movementLabel.textColor = Palette.paper
            movementLabel.backgroundColor = Palette.ink.withAlphaComponent(0.9)
            movementLabel.numberOfLines = 2
            movementLabel.accessibilityIdentifier = "movementGuide"
            movementLabel.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(movementLabel)
            NSLayoutConstraint.activate([
                movementLabel.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 6),
                movementLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 8),
                movementLabel.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor, constant: -8),
            ])
            server.onInput = { [weak self] input in
                guard let self, self.ready else { return }
                self.encounter.receive(input)
                if input.kind != .sample { self.publish() }
            }
            server.onConnection = { [weak self] connected in
                guard let self else { return }
                self.connected = connected
                self.encounter.simulationActive = connected
                if !connected { self.encounter.controllerDisconnected() }
                self.publish()
            }
            publish()
            // Allow the loading state to appear before decoding and warming GPU resources.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.encounter.prepare { [weak self] in
                    guard let self else { return }
                    self.ready = true
                    self.encounter.start()
                    self.head.start()
                    self.server.start()
                    self.publish()
                    self.heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                        MainActor.assumeIsolated { self?.publish() }
                    }
                }
            }
        }

        @objc private func centerView() { encounter.recenterMovement() }
        @objc private func changeRate() { encounter.setFrameRate(rate.selectedSegmentIndex == 1 ? 120 : 60) }

        @objc private func toggleWalking() {
            encounter.phoneWalkingEnabled.toggle()
            publish()
        }

        private func readDesktopInput() -> DesktopMovementInput {
            guard let window = view.window, window.isKeyWindow,
                window.windowScene?.activationState == .foregroundActive,
                let keyboard = GCKeyboard.coalesced?.keyboardInput
            else {
                encounter.resetDesktopInput()
                return DesktopMovementInput()
            }
            func down(_ key: GCKeyCode) -> Float { keyboard.button(forKeyCode: key)?.isPressed == true ? 1 : 0 }
            let modifiers: [GCKeyCode] = [.leftGUI, .rightGUI, .leftControl, .rightControl, .leftAlt, .rightAlt]
            guard !modifiers.contains(where: { down($0) > 0 }) else {
                encounter.resetDesktopInput()
                return DesktopMovementInput()
            }
            return DesktopMovementInput(
                move: SIMD2(down(.keyD) - down(.keyA), down(.keyW) - down(.keyS)),
                look: SIMD2(down(.rightArrow) - down(.leftArrow), down(.upArrow) - down(.downArrow)))
        }

        private func publish() {
            let tracking = encounter.room.trackingMessage
            connectionLabel.text =
                ready
                ? "\(connected ? "iPhone connected" : "Open X Arcana on your iPhone") · \(tracking)"
                : "Preparing X Arcana…"
            let timing = encounter.stage.frameTiming
            metricsLabel.text =
                ready && timing.fps > 0 ? String(format: "%.0f fps · %.1f ms", timing.fps, timing.p95 * 1000) : ""
            let headTracked = encounter.room.isHeadTracked
            walking.isHidden = !ready
            walking.isEnabled = ready && connected
            walking.setTitle(encounter.phoneWalkingEnabled ? "Phone walking: on" : "Phone walking: off", for: .normal)
            movementLabel.text =
                encounter.phoneWalkingEnabled
                ? encounter.walkingStatus
                : (headTracked
                    ? "Air 2 tracks head turns. Enable Phone walking for experimental position tracking."
                    : "WASD to move · Arrow keys to look · iPhone to cast")
            movementLabel.isHidden = !ready
            server.broadcast(
                HostState(
                    status: encounter.status,
                    mode: encounter.fightingMode == .wand ? "wand" : "bow", isHolding: encounter.isHolding,
                    battle: encounter.battleStatus, headStatus: tracking,
                    isSeeThrough: encounter.room.isSeeThrough, ready: ready, run: encounter.runSnapshot,
                    castPreview: encounter.castPreview, shieldReady: encounter.shieldReady,
                    setupStep: encounter.runSnapshot.hasStarted ? nil : encounter.setupStep, canResetScores: true,
                    supportsPhonePosition: true, phoneWalkingEnabled: encounter.phoneWalkingEnabled))
        }
    }
#endif
