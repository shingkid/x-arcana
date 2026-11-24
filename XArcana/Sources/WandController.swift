import UIKit

/// A single tactile surface. The glasses show all setup choices and combat information.
final class WandController: UIViewController, UIGestureRecognizerDelegate {
    private let session = ControllerSession.shared
    private let source = UILabel()
    private let status = UILabel()
    private let holdPrompt = UILabel()
    private let wand = WandTouchSurface()
    private let restart = UIButton(type: .system)
    private let resetScores = UIButton(type: .system)
    private var confirmingScoreReset = false
    private lazy var nextTap = UITapGestureRecognizer(target: self, action: #selector(nextChoice))
    private lazy var confirmTap = UITapGestureRecognizer(target: self, action: #selector(confirmChoice))

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = Palette.ink
        view.tintColor = Palette.gold
        confirmTap.numberOfTapsRequired = 2
        nextTap.delegate = self
        confirmTap.delegate = self
        nextTap.require(toFail: confirmTap)
        view.addGestureRecognizer(nextTap)
        view.addGestureRecognizer(confirmTap)

        wand.translatesAutoresizingMaskIntoConstraints = false
        wand.onBegin = { [weak self] in
            guard let self, self.session.canPlay else { return }
            self.session.beginDrawing()
        }
        wand.onEnd = { [weak self] in self?.session.endDrawing() }
        wand.onCancel = { [weak self] in self?.session.cancelDrawing() }
        view.addSubview(wand)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            wand.topAnchor.constraint(equalTo: safe.topAnchor),
            wand.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
            wand.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            wand.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            stack.topAnchor.constraint(equalTo: safe.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -24),
        ])
        let title = UILabel()
        configure(title, .largeTitle, color: Palette.paper)
        title.font = UIFont(
            descriptor: title.font.fontDescriptor.withDesign(.serif) ?? title.font.fontDescriptor, size: 0)
        title.text = "X Arcana"
        title.accessibilityTraits.insert(.header)
        let header = UIView()
        title.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(title)
        stack.addArrangedSubview(header)
        for button in [restart, resetScores] {
            button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(button)
        }
        restart.setTitle("Restart", for: .normal)
        restart.accessibilityIdentifier = "restartRun"
        restart.accessibilityHint =
            "Return to world and weapon selection for a level-one run. Your best score and wave record are kept."
        restart.addTarget(self, action: #selector(restartRun), for: .touchUpInside)
        resetScores.setTitle("Reset scores", for: .normal)
        resetScores.accessibilityIdentifier = "resetScores"
        resetScores.accessibilityHint = "Ask to erase all scores and return to world and weapon selection."
        resetScores.addTarget(self, action: #selector(confirmScoreReset), for: .touchUpInside)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            title.topAnchor.constraint(equalTo: header.topAnchor),
            title.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            restart.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            resetScores.topAnchor.constraint(equalTo: restart.topAnchor),
            restart.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            resetScores.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            resetScores.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            restart.trailingAnchor.constraint(equalTo: resetScores.leadingAnchor, constant: -16),
            restart.leadingAnchor.constraint(greaterThanOrEqualTo: header.leadingAnchor),
            restart.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            resetScores.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            restart.widthAnchor.constraint(greaterThanOrEqualToConstant: 88),
            resetScores.widthAnchor.constraint(greaterThanOrEqualToConstant: 118),
        ])
        configure(source, .subheadline, color: Palette.muted)
        source.accessibilityIdentifier = "controllerConnection"
        stack.addArrangedSubview(source)
        let space = UIView()
        space.setContentHuggingPriority(.defaultLow, for: .vertical)
        stack.addArrangedSubview(space)
        configure(holdPrompt, .title1, color: Palette.gold)
        holdPrompt.accessibilityIdentifier = "holdPrompt"
        stack.addArrangedSubview(holdPrompt)
        configure(status, .body, color: Palette.paper)
        status.accessibilityIdentifier = "castStatus"
        stack.addArrangedSubview(status)
        NotificationCenter.default.addObserver(
            self, selector: #selector(cancelTouch),
            name: UIApplication.willResignActiveNotification, object: nil)
        session.onChange = { [weak self] in self?.showState() }
        showState()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancelTouch()
    }

    @objc private func cancelTouch() { wand.resetTouch() }

    private func configure(_ label: UILabel, _ style: UIFont.TextStyle, color: UIColor) {
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
    }

    func showState() {
        source.text = session.connectionStatus
        let ended = session.state.run?.isGameOver == true
        let canRestart = ended && session.isReady
        restart.isHidden = session.state.run?.hasStarted != true
        restart.isEnabled = session.isReady && !restart.isHidden && !confirmingScoreReset
        resetScores.isHidden = restart.isHidden || session.state.canResetScores != true
        resetScores.isEnabled = restart.isEnabled && !resetScores.isHidden
        // Recognizers never delay a live draw or bow touch.
        nextTap.isEnabled = session.canStart && !confirmingScoreReset
        confirmTap.isEnabled = (session.canStart || canRestart) && !confirmingScoreReset
        wand.allowsDrawing = session.canPlay && !confirmingScoreReset
        wand.isEnabled = (session.canPlay || session.canStart || canRestart) && !confirmingScoreReset
        wand.onConfirm = session.canStart || canRestart ? { [weak self] in self?.confirmChoice() } : nil
        wand.onNextChoice = session.canStart ? { [weak self] in self?.session.cycleSetupChoice(forceCycle: true) } : nil
        wand.accessibilityCustomActions =
            session.canStart
            ? [
                UIAccessibilityCustomAction(
                    name: "Next choice in glasses", target: wand,
                    selector: #selector(WandTouchSurface.nextAccessibilityChoice))
            ] : nil
        status.text = session.voiceStatus.contains("Settings") ? session.voiceStatus : session.status
        if !session.isConnected {
            holdPrompt.text = "Open the Mac app"
        } else if !session.isReady {
            holdPrompt.text = "Mac scene is loading"
        } else if ended {
            holdPrompt.text = "Double-tap anywhere to play again"
        } else if session.canStart {
            let step = session.state.setupStep == "weapon" ? "weapon" : "world"
            holdPrompt.text = "Choose your \(step) in the glasses"
            status.text =
                "Point the phone at a choice, then tap to preview.\nDouble-tap to confirm. No motion? Tap to cycle."
        } else if let remaining = session.state.run?.countdownRemaining, remaining > 0 {
            holdPrompt.text = "\(Int(ceil(remaining))) · Get ready"
        } else if session.isBow {
            holdPrompt.text = session.isHolding ? "Lift to shoot" : "Tap anywhere to shoot"
        } else {
            holdPrompt.text = session.isHolding ? "Lift to cast" : "Hold anywhere"
        }
        wand.accessibilityLabel = holdPrompt.text
        wand.accessibilityHint =
            session.canStart
            ? "Point and tap to preview. Double-tap to confirm. With VoiceOver, use the Next choice action to cycle, then activate to confirm."
            : canRestart
                ? "Activate to return to world and weapon selection."
                : session.canPlay
                    ? (session.isBow
                        ? "Tap and release to fire. Say cast to select the wand."
                        : "Hold while moving the phone, then lift to cast. With VoiceOver, activate once to hold and again to release.")
                    : "Keep the controller connected to the Mac."
        if !session.isHolding { wand.resetTouch() }
        wand.showHolding(session.isHolding)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Utility buttons never participate in setup or game-over double taps.
        guard let touched = touch.view else { return true }
        return ![restart, resetScores].contains { touched === $0 || touched.isDescendant(of: $0) }
    }

    @objc private func restartRun() {
        guard session.isReady, session.state.run?.hasStarted == true else { return }
        nextTap.isEnabled = false
        confirmTap.isEnabled = false
        wand.resetTouch()
        session.restartRun()
    }

    @objc private func confirmScoreReset() {
        guard session.isReady, session.state.run?.hasStarted == true,
            session.state.canResetScores == true, !confirmingScoreReset
        else { return }
        confirmingScoreReset = true
        wand.resetTouch()
        showState()
        let alert = UIAlertController(
            title: "Clear all scores?",
            message:
                "Your best score and wave record will be erased. Choose your world and weapon again before the new level-1 run.",
            preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
                self?.confirmingScoreReset = false
                self?.showState()
            })
        alert.addAction(
            UIAlertAction(title: "Clear scores", style: .destructive) { [weak self] _ in
                guard let self else { return }
                self.confirmingScoreReset = false
                self.session.resetScores()
                self.showState()
            })
        present(alert, animated: true)
    }

    @objc private func nextChoice() {
        guard session.canStart else { return }
        session.cycleSetupChoice()
    }

    @objc private func confirmChoice() {
        if session.canStart {
            session.confirmSetupChoice()
        } else if session.isReady, session.state.run?.isGameOver == true {
            session.restartRun()
        }
    }
}

/// The first contact begins immediately; extra fingers stay in the same gesture.
/// The last lift ends the stroke, even outside the bounds. System cancellation discards it.
private final class WandTouchSurface: UIControl {
    var onConfirm: (() -> Void)?
    var onNextChoice: (() -> Void)?
    var allowsDrawing = false
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    var onCancel: (() -> Void)?
    private var gestureActive = false
    private var touchesDown = Set<UITouch>()
    private var accessibilityHolding = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isAccessibilityElement = true
        accessibilityIdentifier = "drawRune"
        accessibilityLabel = "Hold anywhere to draw a rune"
        accessibilityHint =
            "Hold while moving the iPhone. Lift to cast. With VoiceOver, double-tap to start, then double-tap to cast."
        accessibilityTraits = .button
        layer.cornerRadius = 18
        showHolding(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    func showHolding(_ holding: Bool) {
        accessibilityHolding = holding
        accessibilityValue = holding ? "Holding" : "Ready"
        backgroundColor = Palette.gold.withAlphaComponent(holding ? 0.15 : 0.035)
        layer.borderColor = Palette.gold.withAlphaComponent(holding ? 1 : 0.55).cgColor
        layer.borderWidth = holding ? 3 : 1
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard allowsDrawing else { return }
        let alreadyDown = !touchesDown.isEmpty
        touchesDown.formUnion(touches)
        guard !alreadyDown, !touchesDown.isEmpty, !accessibilityHolding else { return }
        gestureActive = true
        onBegin?()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesDown.subtract(touches)
        guard touchesDown.isEmpty, gestureActive else { return }
        gestureActive = false
        onEnd?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesDown.subtract(touches)
        cancelTouch()
    }

    func cancelTouch() {
        let wasActive = gestureActive || accessibilityHolding
        gestureActive = false
        if wasActive { onCancel?() }
    }

    func resetTouch() {
        cancelTouch()
        touchesDown.removeAll()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            resetTouch()
        }
    }

    @objc func nextAccessibilityChoice() -> Bool {
        guard isEnabled, let onNextChoice else { return false }
        onNextChoice()
        return true
    }

    override func accessibilityActivate() -> Bool {
        guard isEnabled, touchesDown.isEmpty else { return false }
        if let onConfirm {
            onConfirm()
            return true
        }
        guard allowsDrawing else { return false }
        if accessibilityHolding { onEnd?() } else { onBegin?() }
        return true
    }
}
