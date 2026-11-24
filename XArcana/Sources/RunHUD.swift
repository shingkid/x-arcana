import UIKit

/// Readable at a glance, with no hit targets over the controller's drawing surface.
final class RunHUD: UIView {
    private let health = UILabel()
    private let mana = UILabel()
    private let progress = UILabel()
    private let score = UILabel()
    private let healthBar = UIProgressView(progressViewStyle: .default)
    private let manaBar = UIProgressView(progressViewStyle: .default)

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        accessibilityIdentifier = "runHUD"
        backgroundColor = Palette.ink.withAlphaComponent(0.92)
        layer.cornerRadius = 10
        for label in [health, mana, progress, score] {
            label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
            label.textColor = Palette.paper
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.8
            addSubview(label)
        }
        health.accessibilityIdentifier = "playerHealth"
        mana.accessibilityIdentifier = "playerMana"
        progress.accessibilityIdentifier = "playerLevel"
        score.accessibilityIdentifier = "playerScore"
        for (bar, color) in [
            (healthBar, UIColor(red: 0.95, green: 0.38, blue: 0.34, alpha: 1)),
            (manaBar, UIColor(red: 0.35, green: 0.72, blue: 1, alpha: 1)),
        ] {
            bar.progressTintColor = color
            bar.trackTintColor = Palette.paper.withAlphaComponent(0.16)
            bar.isAccessibilityElement = false
            addSubview(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 78) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset: CGFloat = 16
        let gap: CGFloat = 24
        let width = max(0, (bounds.width - inset * 2 - gap) / 2)
        let y: CGFloat = 10
        health.frame = CGRect(x: inset, y: y, width: width, height: 19)
        mana.frame = CGRect(x: inset + width + gap, y: y, width: width, height: 19)
        healthBar.frame = CGRect(x: inset, y: y + 24, width: width, height: 5)
        manaBar.frame = CGRect(x: inset + width + gap, y: y + 24, width: width, height: 5)
        progress.frame = CGRect(x: inset, y: y + 34, width: width, height: 18)
        score.frame = CGRect(x: inset + width + gap, y: y + 34, width: width, height: 18)
        score.textAlignment = .right
    }

    func show(_ run: RunSnapshot) {
        health.text = "HP  \(run.health.formatted(.number.precision(.fractionLength(0...1)))) / \(run.maxHealth)"
        let shield: String
        if let health = run.shieldHealth, health > 0 {
            shield = " · Shield \(health.formatted(.number.precision(.fractionLength(0...1)))) HP"
        } else if run.shieldHealth == nil, run.shieldRemaining > 0 {
            shield = " · Shield \(Int(ceil(run.shieldRemaining)))s"
        } else {
            shield =
                run.shieldCooldownRemaining > 0
                ? " · Shield ready in \(Int(ceil(run.shieldCooldownRemaining)))s" : ""
        }
        mana.text = "MANA  \(Int(run.mana.rounded(.down))) / \(Int(run.maxMana))\(shield)"
        progress.text = "Level \(run.wave)  ·  Best cleared \(run.bestWave)"
        score.text = "\(run.score) pts · \(run.kills) defeated · Nyan \(run.nyanKillsSinceCast)/20"
        healthBar.progress = Float(run.health) / Float(max(1, run.maxHealth))
        manaBar.progress = Float(run.mana / max(1, run.maxMana))
        health.accessibilityLabel =
            "Health, \(run.health.formatted(.number.precision(.fractionLength(0...1)))) of \(run.maxHealth)"
        mana.accessibilityLabel = "Mana, \(Int(run.mana)) of \(Int(run.maxMana))\(shield)"
        progress.accessibilityLabel = "Level \(run.wave), best cleared level \(run.bestWave)"
    }
}

/// The glasses keep a compact reference visible while the wand is active.
final class RunSpellGuide: UIView {
    private let gestures = UILabel()
    private let voice = UILabel()
    private let casting = UILabel()

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        accessibilityIdentifier = "wandSpellGuide"
        isUserInteractionEnabled = false
        backgroundColor = Palette.ink.withAlphaComponent(0.94)
        layer.cornerRadius = 10
        for label in [gestures, voice] {
            label.font = .systemFont(ofSize: 14, weight: .medium)
            label.textAlignment = .center
            label.numberOfLines = 0
            addSubview(label)
        }
        casting.font = .systemFont(ofSize: 14, weight: .medium)
        casting.textAlignment = .center
        casting.textColor = Palette.paper.withAlphaComponent(0.8)
        casting.text = "Wave to strike · Hold to draw"
        casting.accessibilityIdentifier = "wandCastingGuide"
        addSubview(casting)
        gestures.textColor = Palette.paper
        voice.textColor = Palette.gold
        gestures.accessibilityIdentifier = "wandGestureGuide"
        voice.accessibilityIdentifier = "wandVoiceGuide"
        gestures.text = SpellCatalog.wandGestureGuide
        voice.text = SpellCatalog.wandVoiceGuide
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = max(0, bounds.width - 24)
        let firstHeight = gestures.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let secondHeight = voice.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let footerHeight: CGFloat = 17
        let top = max(6, (bounds.height - firstHeight - secondHeight - footerHeight - 8) / 2)
        gestures.frame = CGRect(x: 12, y: top, width: width, height: firstHeight)
        voice.frame = CGRect(x: 12, y: gestures.frame.maxY + 5, width: width, height: secondHeight)
        casting.frame = CGRect(x: 12, y: voice.frame.maxY + 3, width: width, height: footerHeight)
    }
}

final class RunOverView: UIView {
    var onRestart: (() -> Void)?
    private let details = UILabel()
    private let restart = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "runOver"
        backgroundColor = Palette.ink.withAlphaComponent(0.98)
        layer.cornerRadius = 18
        let title = UILabel()
        title.attributedText = NSAttributedString(string: "YOU DIED", attributes: [.kern: 4])
        title.font = UIFont(name: "Baskerville", size: 50) ?? .systemFont(ofSize: 50, weight: .regular)
        title.textColor = UIColor(red: 0.82, green: 0.12, blue: 0.09, alpha: 1)
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.7
        title.numberOfLines = 1
        title.textAlignment = .center
        title.accessibilityTraits = .header
        details.font = .monospacedDigitSystemFont(ofSize: 17, weight: .medium)
        details.textColor = Palette.paper
        details.numberOfLines = 0
        details.textAlignment = .center
        details.accessibilityIdentifier = "runResults"
        restart.setTitle("Play again\nOr double-tap your phone", for: .normal)
        restart.titleLabel?.font = .systemFont(ofSize: 23, weight: .semibold)
        restart.titleLabel?.numberOfLines = 2
        restart.titleLabel?.textAlignment = .center
        restart.setTitleColor(Palette.ink, for: .normal)
        restart.backgroundColor = Palette.gold
        restart.layer.cornerRadius = 12
        restart.accessibilityIdentifier = "restartRun"
        restart.heightAnchor.constraint(equalToConstant: 76).isActive = true
        restart.addTarget(self, action: #selector(playAgain), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [title, details, restart])
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ run: RunSnapshot?, connected: Bool = true) {
        isHidden = run?.isGameOver != true
        guard let run, run.isGameOver else { return }
        details.text =
            "\(run.score) points · Level \(run.wave)\n\(run.kills) defeated\n\nBest score \(run.bestScore)\nBest cleared level \(run.bestWave)"
        restart.isEnabled = connected
        restart.alpha = connected ? 1 : 0.5
    }

    @objc private func playAgain() { onRestart?() }
}

/// Brief, queued announcements use game time so a disconnect does not hide them.
final class RunAnnouncementView: UIView {
    private struct Notice {
        let title: String
        let detail: String
    }
    private let title = UILabel()
    private let detail = UILabel()
    private var pending: [Notice] = []
    private var remaining: Double = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityIdentifier = "runAnnouncement"
        accessibilityTraits = .staticText
        backgroundColor = Palette.ink.withAlphaComponent(0.95)
        layer.cornerRadius = 12
        layer.borderColor = Palette.gold.cgColor
        layer.borderWidth = 1
        title.font = .systemFont(ofSize: 29, weight: .bold)
        title.textColor = Palette.gold
        title.textAlignment = .center
        detail.font = .systemFont(ofSize: 17, weight: .medium)
        detail.textColor = Palette.paper
        detail.textAlignment = .center
        detail.numberOfLines = 2
        let stack = UIStackView(arrangedSubviews: [title, detail])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func announce(title: String, detail: String) {
        let notice = Notice(title: title, detail: detail)
        if isHidden {
            show(notice)
        } else {
            if pending.count == 4 { pending.removeFirst() }
            pending.append(notice)
        }
    }

    func advance(deltaTime: Double) {
        guard !isHidden, deltaTime.isFinite, deltaTime > 0 else { return }
        remaining -= deltaTime
        guard remaining <= 0 else { return }
        if pending.isEmpty { clear() } else { show(pending.removeFirst()) }
    }

    func clear() {
        pending.removeAll()
        remaining = 0
        isHidden = true
        accessibilityLabel = nil
    }

    private func show(_ notice: Notice) {
        title.text = notice.title
        detail.text = notice.detail
        accessibilityLabel = "\(notice.title). \(notice.detail)"
        remaining = 3
        isHidden = false
        UIAccessibility.post(notification: .announcement, argument: accessibilityLabel)
    }
}

final class RunStartView: UIView {
    var onChoice: ((Int, Bool) -> Void)?
    private let title = UILabel()
    private let stepLabel = UILabel()
    private let detail = UILabel()
    private let hint = UILabel()
    private let first = UIButton(type: .system)
    private let second = UIButton(type: .system)
    private let choices = UIStackView()
    private let content = UIStackView()
    private let credit = UILabel()
    private var step = "world"
    private var seeThrough = false
    private var bow = false
    private(set) var hoveredChoice: Int?
    private(set) var isCountingDown = false

    var choiceFrames: [CGRect] {
        [first, second].map { $0.convert($0.bounds, to: self) }
    }

    func choice(at point: CGPoint) -> Int? {
        guard !isHidden, !isCountingDown, point.x.isFinite, point.y.isFinite else { return nil }
        return choiceFrames.firstIndex { $0.contains(point) }
    }

    func hover(_ index: Int?) {
        guard hoveredChoice != index else { return }
        hoveredChoice = index
        updateChoices()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "runStart"
        backgroundColor = Palette.ink.withAlphaComponent(0.94)
        layer.cornerRadius = 20
        layer.borderWidth = 1
        layer.borderColor = Palette.gold.withAlphaComponent(0.6).cgColor
        title.textColor = Palette.gold
        title.textAlignment = .center
        title.accessibilityIdentifier = "startCountdown"
        for label in [detail, hint, stepLabel] {
            label.textColor = Palette.paper
            label.textAlignment = .center
            label.numberOfLines = 0
        }
        stepLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        stepLabel.textColor = Palette.muted
        detail.font = .systemFont(ofSize: 18, weight: .medium)
        detail.accessibilityIdentifier = "setupExplanation"
        hint.font = .systemFont(ofSize: 16, weight: .medium)
        hint.textColor = Palette.gold
        choices.axis = .horizontal
        choices.distribution = .fillEqually
        choices.spacing = 16
        for (index, button) in [first, second].enumerated() {
            button.tag = index
            button.titleLabel?.font = .systemFont(ofSize: 21, weight: .semibold)
            button.titleLabel?.textAlignment = .center
            button.titleLabel?.numberOfLines = 2
            button.layer.cornerRadius = 10
            button.layer.borderWidth = 3
            button.clipsToBounds = true
            button.accessibilityIdentifier = "setupChoice" + String(index)
            button.accessibilityHint = "Preview this choice. Double-click to confirm, or double-tap the phone."
            button.heightAnchor.constraint(equalToConstant: 88).isActive = true
            button.addTarget(self, action: #selector(previewChoice(_:)), for: .touchUpInside)
            choices.addArrangedSubview(button)
        }
        credit.text = "Cat design: Chris Torres · Music: daniwell (Momone Momo)"
        credit.font = .systemFont(ofSize: 11, weight: .regular)
        credit.textColor = Palette.muted
        credit.textAlignment = .center
        credit.numberOfLines = 2
        let stack = content
        for item in [title, stepLabel, choices, detail, hint, credit] { stack.addArrangedSubview(item) }
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        let double = UITapGestureRecognizer(target: self, action: #selector(confirmChoice(_:)))
        double.numberOfTapsRequired = 2
        addGestureRecognizer(double)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        let compact = bounds.height < 420
        content.spacing = compact ? 8 : 14
        detail.isHidden = compact && !isCountingDown
        credit.isHidden = compact || isCountingDown
        if !isCountingDown {
            title.font = UIFont(name: "Baskerville", size: compact ? 30 : 42) ?? .systemFont(ofSize: compact ? 30 : 42)
        }
        hint.font = .systemFont(ofSize: compact ? 13 : 16, weight: .medium)
        super.layoutSubviews()
    }

    @objc private func previewChoice(_ sender: UIButton) {
        guard !isCountingDown else { return }
        onChoice?(sender.tag, false)
    }

    @objc private func confirmChoice(_ recognizer: UITapGestureRecognizer) {
        guard let index = choice(at: recognizer.location(in: self)) else { return }
        onChoice?(index, true)
    }

    func showChoices(step: String, seeThrough: Bool, bow: Bool) {
        self.step = step
        self.seeThrough = seeThrough
        self.bow = bow
        updateChoices()
    }

    private func updateChoices() {
        guard !isCountingDown else { return }
        let world = step == "world"
        let selectedSecond = world ? seeThrough : bow
        stepLabel.text = world ? "1 OF 2 · CHOOSE YOUR WORLD" : "2 OF 2 · CHOOSE YOUR WEAPON"
        first.setTitle(world ? "Fantasy world\nVR" : "Wand", for: .normal)
        second.setTitle(world ? "See-through\nAR" : "Bow", for: .normal)
        for (index, button) in [first, second].enumerated() {
            let selected = (index == 1) == selectedSecond
            button.backgroundColor = selected ? Palette.gold : Palette.paper.withAlphaComponent(0.06)
            button.setTitleColor(selected ? Palette.ink : Palette.paper, for: .normal)
            button.layer.borderColor = hoveredChoice == index ? UIColor.white.cgColor : UIColor.clear.cgColor
            button.accessibilityValue = [selected ? "Selected" : nil, hoveredChoice == index ? "Pointing" : nil]
                .compactMap { $0 }.joined(separator: ", ")
            button.accessibilityTraits = selected ? [.button, .selected] : .button
        }
        if world {
            detail.text =
                seeThrough
                ? "Remove the light shield. See your room through the Air 2 lenses.\nThe Mac stays black. Zombies arrive after the countdown."
                : "Enter a magical hall. Look around to explore the fantasy world."
        } else {
            detail.text =
                bow
                ? "Aim with the phone and tap to fire an arrow.\nSay “cast” to switch to the wand."
                : "Wave to strike · Hold to draw\nZ lightning · O fire · V ice\nHold still for shield\nRelease to cast. Say “shoot” for the bow."
        }
        hint.text = "Point the phone at a choice, then tap to preview.\nDouble-tap to confirm. No motion? Tap to cycle."
    }

    func show(_ run: RunSnapshot) {
        isHidden = run.isGameOver || (run.hasStarted && run.countdownRemaining <= 0)
        guard !isHidden else {
            hover(nil)
            return
        }
        isCountingDown = run.countdownRemaining > 0
        for item in [stepLabel, choices, hint] { item.isHidden = isCountingDown }
        if isCountingDown {
            hoveredChoice = nil
            title.font = .monospacedDigitSystemFont(ofSize: 92, weight: .medium)
            title.text = String(Int(ceil(run.countdownRemaining)))
            detail.text = "Ready your \(bow ? "bow" : "wand")"
        } else {
            title.font = UIFont(name: "Baskerville", size: 42) ?? .systemFont(ofSize: 42, weight: .medium)
            title.text = "X Arcana"
            updateChoices()
        }
    }
}
