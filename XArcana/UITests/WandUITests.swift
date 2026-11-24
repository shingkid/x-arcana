import Network
import XCTest

#if !targetEnvironment(macCatalyst)

    // This server fixture verifies the real wire messages. Spell and combat behavior
    // remain covered by unit tests against the game itself.
    final class WandUITests: XCTestCase {
        private let app = XCUIApplication()
        private var host: ControllerWireFixture?
        private var inputs: [WandInput] { host?.snapshot.inputs ?? [] }
        private var connections: [Bool] { host?.snapshot.connections ?? [] }
        private var releases: Int { host?.snapshot.releases ?? 0 }

        override func tearDownWithError() throws {
            app.terminate()
            host?.stop()
            host = nil
            try super.tearDownWithError()
        }

        @MainActor
        func testSingleTapCyclesAndDoubleTapConfirmsTwoSetupStepsWithoutCasting() async throws {
            try await launchConnectedApp()
            var waiting = RunSnapshot()
            waiting.hasStarted = false
            host?.publish(run: waiting)
            try await expectText("Choose your world", in: "holdPrompt")
            XCTAssertFalse(element("restartRun").exists)
            XCTAssertFalse(element("resetScores").exists)
            XCTAssertEqual(app.buttons.count, 1)
            let pad = element("drawRune")
            pad.tap()
            try await waitUntil("World cycle") { self.inputs.filter { $0.kind == .nextSetupChoice }.count == 1 }
            XCTAssertFalse(inputs.contains { $0.kind == .confirmSetupChoice || $0.kind == .startRun })
            XCTAssertTrue(edges.isEmpty)
            pad.doubleTap()
            try await expectText("Choose your weapon", in: "holdPrompt")
            XCTAssertEqual(inputs.filter { $0.kind == .confirmSetupChoice }.count, 1)
            XCTAssertEqual(
                inputs.filter { $0.kind == .nextSetupChoice }.count, 1, "Double-tap must not cycle the choice")
            pad.tap()
            try await waitUntil("Weapon cycle") { self.inputs.filter { $0.kind == .nextSetupChoice }.count == 2 }
            pad.doubleTap()
            try await expectText("Get ready", in: "holdPrompt")
            pad.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            try await expectText("Tap anywhere to shoot", in: "holdPrompt")
            XCTAssertEqual(inputs.filter { $0.kind == .confirmSetupChoice }.count, 2)
            XCTAssertTrue(edges.isEmpty, "Setup and countdown touches cannot leak into gameplay")
            pad.tap()
            try await waitUntil("Fresh bow tap after countdown") { self.releases == 1 }
            XCTAssertEqual(edges.map(\.kind), [.begin, .end])
            attachScreen(named: "Full phone surface after two-stage setup")
        }

        @MainActor
        func testPhoneHasOneFullSurfaceWithoutMenusOrVitals() async throws {
            try await launchConnectedApp()
            for identifier in [
                "roomPreview", "runeGuide", "fightingMode", "sceneMode", "runHUD", "playerHealth", "playerMana",
            ] {
                XCTAssertFalse(element(identifier).exists, identifier)
            }
            XCTAssertTrue(element("controllerConnection").exists)
            try await expectText("Hold anywhere", in: "holdPrompt")
            XCTAssertTrue(element("drawRune").isHittable)
            XCTAssertEqual(app.segmentedControls.count, 0)
            XCTAssertEqual(app.buttons.count, 3, "Only the full surface and two utility buttons are controls")
            XCTAssertTrue(app.buttons["resetScores"].isHittable)
            XCTAssertTrue(app.buttons["restartRun"].isHittable)
            XCTAssertGreaterThanOrEqual(app.buttons["restartRun"].frame.height, 44)
            XCTAssertEqual(app.scrollViews.count, 0, "Scrolling must not intercept a held touch")
            let pad = element("drawRune").frame
            XCTAssertEqual(pad.minX, app.frame.minX, accuracy: 1)
            XCTAssertEqual(pad.maxX, app.frame.maxX, accuracy: 1)
            XCTAssertGreaterThan(pad.height, app.frame.height * 0.85)
            attachScreen(named: "Single full-screen phone control")
        }

        @MainActor
        func testRestartAfterCancelledHoldRestoresLevelOneAndKeepsRecords() async throws {
            try await launchConnectedApp()
            var advanced = RunSnapshot()
            advanced.level = 4
            advanced.health = 37
            advanced.mana = 22
            advanced.bestScore = 2300
            advanced.bestWave = 7
            host?.publish(run: advanced)
            // Simulate host cancellation while the finger remains down.
            host?.cancelNextHold()
            element("drawRune").coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.55)).press(forDuration: 1.2)
            try await waitUntil("Held gesture cancelled") { self.edges.map(\.kind) == [.begin, .cancel] }
            publish(status: "Mac ready for gestures.")
            try await expectText("Hold anywhere", in: "holdPrompt")
            app.buttons["restartRun"].tap()
            try await waitUntil("Reset command") { self.inputs.filter { $0.kind == .restartRun }.count == 1 }
            let commands = inputs.filter { [.begin, .end, .cancel, .restartRun].contains($0.kind) }
            XCTAssertEqual(commands.map(\.kind), [.begin, .cancel, .restartRun])
            XCTAssertEqual(host?.snapshot.run.level, 1)
            XCTAssertEqual(host?.snapshot.run.health, 100)
            XCTAssertEqual(host?.snapshot.run.mana, 100)
            XCTAssertEqual(host?.snapshot.run.bestScore, 2300)
            XCTAssertEqual(host?.snapshot.run.bestWave, 7)
            try await expectText("Choose your world", in: "holdPrompt")
            XCTAssertEqual(host?.snapshot.run.hasStarted, false)
            XCTAssertEqual(host?.snapshot.run.countdownRemaining, 0)
            XCTAssertEqual(releases, 0)
            try await confirmRestartSetup()
            element("drawRune").tap()
            try await waitUntil("Fresh gesture after reset") { self.releases == 1 }
            XCTAssertEqual(edges.map(\.kind), [.begin, .cancel, .begin, .end])
            attachScreen(named: "Phone surface with Restart and Reset scores")
        }

        @MainActor
        func testResetScoresRequiresConfirmationAndErasesOnlyFixtureRecords() async throws {
            try await launchConnectedApp()
            var advanced = RunSnapshot()
            advanced.level = 3
            advanced.score = 450
            advanced.bestScore = 2300
            advanced.bestWave = 7
            host?.publish(run: advanced)
            app.buttons["resetScores"].tap()
            let alert = app.alerts["Clear all scores?"]
            XCTAssertTrue(alert.waitForExistence(timeout: 3))
            XCTAssertFalse(inputs.contains { $0.kind == .resetScores || $0.kind == .restartRun })
            alert.buttons["Cancel"].tap()
            try await assertNoNewEdges(for: 0.4)
            XCTAssertFalse(inputs.contains { $0.kind == .resetScores || $0.kind == .restartRun })
            XCTAssertEqual(host?.snapshot.run.bestScore, 2300)
            XCTAssertEqual(host?.snapshot.run.level, 3)
            app.buttons["resetScores"].tap()
            XCTAssertTrue(alert.waitForExistence(timeout: 3))
            alert.buttons["Clear scores"].tap()
            try await waitUntil("One confirmed score reset") {
                self.inputs.filter { $0.kind == .resetScores }.count == 1
            }
            XCTAssertEqual(host?.snapshot.run.bestScore, 0)
            XCTAssertEqual(host?.snapshot.run.bestWave, 0)
            XCTAssertEqual(host?.snapshot.run.score, 0)
            XCTAssertEqual(host?.snapshot.run.level, 1)
            XCTAssertEqual(host?.snapshot.run.health, 100)
            XCTAssertEqual(host?.snapshot.run.mana, 100)
            XCTAssertTrue(edges.isEmpty, "Utility actions must not cast")
            try await expectText("Choose your world", in: "holdPrompt")
            XCTAssertEqual(host?.snapshot.run.hasStarted, false)
            XCTAssertEqual(host?.snapshot.run.countdownRemaining, 0)
        }

        @MainActor
        func testLegacyHostHidesScoreResetButKeepsRestart() async throws {
            try await launchConnectedApp()
            host?.publish(resetCapability: nil)
            try await waitUntil("Legacy score-reset control hidden") { !self.element("resetScores").exists }
            XCTAssertTrue(app.buttons["restartRun"].isHittable)
            XCTAssertEqual(app.buttons.count, 2)
        }

        @MainActor
        func testEveryCornerAndEdgeSendsExactlyOneHoldAndRelease() async throws {
            try await launchConnectedApp()
            let positions = [
                CGVector(dx: 0.01, dy: 0.01), CGVector(dx: 0.99, dy: 0.01),
                CGVector(dx: 0.01, dy: 0.99), CGVector(dx: 0.99, dy: 0.99),
                CGVector(dx: 0.01, dy: 0.50), CGVector(dx: 0.99, dy: 0.50),
                CGVector(dx: 0.50, dy: 0.01), CGVector(dx: 0.50, dy: 0.99),
            ]
            var lastGesture: UInt64 = 0
            for (index, position) in positions.enumerated() {
                element("drawRune").coordinate(withNormalizedOffset: position).press(forDuration: 0.08)
                try await waitUntil("Release \(index + 1)") { self.releases == index + 1 }
                let edges = inputs.filter { $0.kind == .begin || $0.kind == .end || $0.kind == .cancel }
                XCTAssertEqual(edges.count, (index + 1) * 2)
                let pair = Array(edges.suffix(2))
                XCTAssertEqual(pair.map(\.kind), [.begin, .end])
                XCTAssertEqual(pair[0].gesture, pair[1].gesture)
                XCTAssertGreaterThan(pair[0].gesture, lastGesture)
                lastGesture = pair[0].gesture
                XCTAssertEqual(element("drawRune").value as? String, "Ready")
            }
            try await assertNoNewEdges(for: 0.5)
        }

        @MainActor
        func testHeldDragAcrossSurfaceReleasesOnce() async throws {
            try await launchConnectedApp()
            let pad = element("drawRune")
            // Every point belongs to the same uninterrupted touch surface.
            let start = pad.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.48))
            let end = pad.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.9))
            start.press(forDuration: 0.3, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            try await waitUntil("One release") { self.releases == 1 }
            XCTAssertEqual(edges.map(\.kind), [.begin, .end])
            XCTAssertEqual(edges.first?.gesture, edges.last?.gesture)
            XCTAssertEqual(pad.value as? String, "Ready")
            try await assertNoNewEdges(for: 0.5)
            attachScreen(named: "Controller after held drag")
        }

        @MainActor
        func testHostNotReadyCancelsHeldTouchAndSuppressesItsRelease() async throws {
            try await launchConnectedApp()
            host?.cancelNextHold()
            element("drawRune").coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.55))
                .press(forDuration: 1.5)
            try await waitUntil("Host cancellation") { self.inputs.contains { $0.kind == .cancel } }
            XCTAssertEqual(edges.map(\.kind), [.begin, .cancel])
            XCTAssertEqual(edges.first?.gesture, edges.last?.gesture)
            XCTAssertEqual(releases, 0)
            XCTAssertEqual(element("drawRune").value as? String, "Ready")
            try await assertNoNewEdges(for: 0.4)
            publish(status: "Mac ready for gestures.")
            try await expectText("Hold anywhere", in: "holdPrompt")
            element("drawRune").coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.55)).tap()
            try await waitUntil("Fresh gesture after cancellation") { self.releases == 1 }
            XCTAssertEqual(edges.map(\.kind), [.begin, .cancel, .begin, .end])
        }

        @MainActor
        func testHostWeaponChangesUpdateFullSurfaceWithoutInputLeak() async throws {
            try await launchConnectedApp()
            host?.publish(mode: "bow")
            try await expectText("Tap anywhere to shoot", in: "holdPrompt")
            XCTAssertTrue(edges.isEmpty)
            element("drawRune").tap()
            try await waitUntil("Bow tap release") { self.releases == 1 }
            host?.publish(mode: "wand")
            try await expectText("Hold anywhere", in: "holdPrompt")
            XCTAssertEqual(edges.map(\.kind), [.begin, .end])
            XCTAssertFalse(inputs.contains { $0.kind == .voice || $0.kind == .sceneMode })
        }

        @MainActor
        func testBackgroundDisconnectsAndForegroundRequiresFreshTouch() async throws {
            try await launchConnectedApp()
            element("drawRune").coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.55)).tap()
            try await waitUntil("Initial release") { self.releases == 1 }
            XCUIDevice.shared.press(.home)
            try await waitUntil("Background disconnect") { self.connections.last == false }
            let count = edges.count
            app.activate()
            try await waitUntil("Foreground reconnect") { self.connections.filter { $0 }.count == 2 }
            try await expectText("Connected to your Mac", in: "controllerConnection")
            try await expectText("Hold anywhere", in: "holdPrompt")
            try await assertNoNewEdges(for: 0.4)
            XCTAssertEqual(edges.count, count)
            element("drawRune").coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.55)).tap()
            try await waitUntil("Fresh release after reconnect") { self.releases == 2 }
            XCTAssertEqual(edges.map(\.kind), [.begin, .end, .begin, .end])
        }

        @MainActor
        func testIdleControllerDoesNotCastOrRequestVoiceAccess() async throws {
            try await launchConnectedApp()
            try await assertNoNewEdges(for: 2)
            XCTAssertTrue(edges.isEmpty)
            XCTAssertEqual(element("drawRune").value as? String, "Ready")
            XCTAssertFalse(element("roomPreview").exists)
            XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
            XCTAssertFalse(app.alerts.firstMatch.exists)
        }

        @MainActor
        private func launchConnectedApp() async throws {
            continueAfterFailure = true
            let host = try ControllerWireFixture()
            self.host = host
            host.start()
            try await waitUntil("Loopback listener") { host.snapshot.port != nil }
            let port = try XCTUnwrap(host.snapshot.port)
            app.launchEnvironment["EMBER_CONTROLLER_TEST_PORT"] = String(port)
            XCUIDevice.shared.orientation = .portrait
            app.launch()
            try await waitUntil("Phone handshake", timeout: 12) { self.connections.last == true }
            try await expectText("Connected to your Mac", in: "controllerConnection")
            try await expectText("Hold anywhere", in: "holdPrompt")
        }

        @MainActor
        func testVitalsStayOnGlassesAndPhoneKeepsGameOverRestart() async throws {
            try await launchConnectedApp()
            XCTAssertFalse(element("runHUD").exists)
            XCTAssertFalse(element("playerHealth").exists)
            XCTAssertFalse(element("playerMana").exists)
            var run = RunSnapshot()
            run.health = 42
            run.mana = 36
            run.score = 900
            run.level = 2
            host?.publish(run: run)
            XCTAssertFalse(element("runHUD").exists)
            XCTAssertFalse(element("roomPreview").exists)
            run.health = 0
            run.isGameOver = true
            host?.publish(run: run)
            try await expectText("Double-tap anywhere to play again", in: "holdPrompt")
            XCTAssertTrue(element("restartRun").exists)
            element("drawRune").tap()
            try await assertNoNewEdges(for: 0.4)
            XCTAssertFalse(inputs.contains { $0.kind == .restartRun })
            attachScreen(named: "Full surface restart prompt")
            element("drawRune").doubleTap()
            try await waitUntil("One restart command") { self.inputs.filter { $0.kind == .restartRun }.count == 1 }
            try await expectText("Choose your world", in: "holdPrompt")
            XCTAssertTrue(edges.isEmpty)
            XCTAssertFalse(element("runOver").exists)
            attachScreen(named: "Controller without vitals after restart")
        }

        @MainActor
        func testDeathWhileHoldingCancelsAndRequiresFreshGestureAfterRestart() async throws {
            try await launchConnectedApp()
            host?.endRunOnNextHold()
            element("drawRune").coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.55))
                .press(forDuration: 1.5)
            try await waitUntil("Death cancelled held rune") { self.inputs.contains { $0.kind == .cancel } }
            XCTAssertEqual(edges.map(\.kind), [.begin, .cancel])
            XCTAssertEqual(releases, 0)
            element("drawRune").doubleTap()
            try await expectText("Choose your world", in: "holdPrompt")
            try await confirmRestartSetup()
            element("drawRune").coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.55)).tap()
            try await waitUntil("Fresh release after restart") { self.releases == 1 }
            XCTAssertEqual(edges.map(\.kind), [.begin, .cancel, .begin, .end])
        }

        @MainActor
        private func confirmRestartSetup() async throws {
            XCTAssertFalse(element("restartRun").exists)
            element("drawRune").doubleTap()
            try await expectText("Choose your weapon", in: "holdPrompt")
            XCTAssertEqual(host?.snapshot.run.hasStarted, false)
            element("drawRune").doubleTap()
            try await expectText("Get ready", in: "holdPrompt")
            try await expectText("Hold anywhere", in: "holdPrompt")
        }

        private func publish(status: String, ready: Bool = true) {
            host?.publish(status: status, ready: ready)
        }

        @MainActor
        private var edges: [WandInput] { inputs.filter { [.begin, .end, .cancel].contains($0.kind) } }

        @MainActor
        private func assertNoNewEdges(for seconds: TimeInterval) async throws {
            let count = edges.count
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            XCTAssertEqual(edges.count, count, "No duplicate touch edges may arrive later.")
        }

        @MainActor
        private func waitUntil(
            _ description: String, timeout: TimeInterval = 6,
            condition: () -> Bool
        ) async throws {
            let deadline = ProcessInfo.processInfo.systemUptime + timeout
            while !condition(), ProcessInfo.processInfo.systemUptime < deadline {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            guard condition() else {
                XCTFail("\(description). Fixture: \(host?.snapshot.failure ?? "no transport error")")
                throw FixtureWaitError.timeout
            }
        }

        private enum FixtureWaitError: Error { case timeout }

        @MainActor
        private func expectText(
            _ text: String, in identifier: String,
            file: StaticString = #filePath, line: UInt = #line
        ) async throws {
            try await waitUntil("Expected \(text) in \(identifier)") {
                let item = self.element(identifier)
                guard item.exists else { return false }
                return item.label.localizedCaseInsensitiveContains(text)
                    || (item.value as? String)?.localizedCaseInsensitiveContains(text) == true
            }
        }

        private func element(_ identifier: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        }

        private func attachScreen(named name: String) {
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = name
            capture.lifetime = .keepAlways
            add(capture)
        }
    }

    // XCUI actions can block the test actor for several seconds. This wire fixture
    // runs independently, so UI automation cannot starve transport heartbeats.
    // It shares the production framing and validation rules but renders no game.
    private final class ControllerWireFixture {
        struct Snapshot {
            var port: UInt16?
            var inputs: [WandInput] = []
            var connections: [Bool] = []
            var releases = 0
            var failure: String?
            var run = RunSnapshot()
        }

        private let queue = DispatchQueue(label: "xarcana.controller.ui-fixture")
        private let listener: NWListener
        private var connection: NWConnection?
        private var timer: DispatchSourceTimer?
        private var storage = Snapshot()
        private var frames = ControllerFrameDecoder()
        private var packets = ControllerPacketValidator()
        private var inputs = ControllerInputValidator()
        private var session: UUID?
        private var sequence: UInt64 = 0
        private var lastReceived = ProcessInfo.processInfo.systemUptime
        private var mode = "wand"
        private var seeThrough = false
        private var cancelHold = false
        private var endRunOnHold = false
        private var canResetScores: Bool? = true
        private var setupStep: String?
        private var run = RunSnapshot()
        private var state = HostState(status: "Mac ready for gestures.", run: RunSnapshot(), canResetScores: true)
        private var stopped = false
        private var countdownGeneration: UInt64 = 0

        var snapshot: Snapshot { queue.sync { storage } }

        init() throws {
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            listener = try NWListener(using: NWParameters(tls: nil, tcp: tcp), on: .any)
        }

        func start() {
            listener.stateUpdateHandler = { [weak self] state in
                guard let self, !self.stopped else { return }
                switch state {
                case .ready: self.storage.port = self.listener.port?.rawValue
                case .failed(let error): self.storage.failure = String(describing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: queue)
            queue.async { [self] in
                let timer = DispatchSource.makeTimerSource(queue: queue)
                self.timer = timer
                timer.schedule(deadline: .now() + 1, repeating: 1)
                timer.setEventHandler { [weak self] in
                    guard let self, let connection = self.connection else { return }
                    if ProcessInfo.processInfo.systemUptime - self.lastReceived > 4 {
                        self.storage.failure = "Heartbeat timed out"
                        self.disconnect(connection)
                    } else if self.session != nil {
                        self.send(.ping)
                    }
                }
                timer.resume()
            }
        }

        func stop() {
            queue.sync {
                stopped = true
                timer?.cancel()
                timer = nil
                listener.cancel()
                if let connection { disconnect(connection) }
            }
        }

        func cancelNextHold() { queue.sync { cancelHold = true } }
        func endRunOnNextHold() { queue.sync { endRunOnHold = true } }

        func publish(run: RunSnapshot) {
            queue.sync {
                countdownGeneration &+= 1
                self.run = run
                self.setupStep = run.hasStarted ? nil : "world"
                updateState(status: run.isGameOver ? "Run ended." : "Mac ready for gestures.")
            }
        }

        func publish(resetCapability: Bool?) {
            queue.sync {
                canResetScores = resetCapability
                updateState(status: "Mac ready for gestures.")
            }
        }

        func publish(mode: String) {
            queue.sync {
                self.mode = mode
                updateState(status: "Mac mode: \(mode).")
            }
        }

        func publish(status: String, ready: Bool = true) {
            queue.sync { updateState(status: status, ready: ready) }
        }

        private func accept(_ connection: NWConnection) {
            guard !stopped, self.connection == nil else {
                connection.cancel()
                return
            }
            self.connection = connection
            frames = ControllerFrameDecoder()
            packets = ControllerPacketValidator()
            inputs = ControllerInputValidator()
            session = nil
            sequence = 0
            lastReceived = ProcessInfo.processInfo.systemUptime
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                guard let self, let connection, self.connection === connection else { return }
                switch state {
                case .ready: self.receive(connection)
                case .failed(let error):
                    self.storage.failure = String(describing: error)
                    self.disconnect(connection)
                case .cancelled: self.disconnect(connection)
                default: break
                }
            }
            connection.start(queue: queue)
        }

        private func receive(_ connection: NWConnection) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: ControllerFrameDecoder.maximumBytes) {
                [weak self, weak connection] data, _, complete, error in
                guard let self, let connection, self.connection === connection else { return }
                do {
                    if let data {
                        for frame in try self.frames.append(data) {
                            let packet = try JSONDecoder().decode(ControllerPacket.self, from: frame)
                            try self.packets.accept(packet)
                            self.lastReceived = ProcessInfo.processInfo.systemUptime
                            switch packet.kind {
                            case .hello:
                                self.session = packet.session
                                self.storage.connections.append(true)
                                self.send(.hello)
                                self.send(.state, state: self.state)
                            case .input:
                                guard let input = packet.input else { throw ControllerProtocolError.packet }
                                try self.inputs.accept(input)
                                self.record(input)
                            case .ping: break
                            case .state: throw ControllerProtocolError.packet
                            }
                        }
                    }
                    if complete || error != nil { self.disconnect(connection) } else { self.receive(connection) }
                } catch {
                    self.storage.failure = String(describing: error)
                    self.disconnect(connection)
                }
            }
        }

        private func record(_ input: WandInput) {
            storage.inputs.append(input)
            switch input.kind {
            case .begin:
                if endRunOnHold {
                    endRunOnHold = false
                    run.health = 0
                    run.isGameOver = true
                    updateState(status: "Run ended.")
                } else if cancelHold {
                    cancelHold = false
                    updateState(status: "Mac scene is loading.", ready: false)
                }
            case .end:
                storage.releases += 1
                updateState(status: "Mac received release \(storage.releases).")
            case .cancel: updateState(status: "Mac cancelled gesture.", ready: run.isGameOver)
            case .voice:
                if input.command == "shoot" { mode = "bow" }
                if input.command == "cast" { mode = "wand" }
                updateState(status: "Mac mode: \(mode).")
            case .sceneMode:
                seeThrough = input.seeThrough ?? false
                updateState(status: seeThrough ? "Mac see-through mode." : "Mac fantasy hall mode.")
            case .sample, .position: break
            case .nextSetupChoice:
                guard !run.hasStarted else { break }
                if setupStep == "weapon" { mode = mode == "wand" ? "bow" : "wand" } else { seeThrough.toggle() }
                updateState(status: "Preview choice in glasses.")
            case .confirmSetupChoice, .startRun:
                guard !run.hasStarted else { break }
                if setupStep == "weapon" {
                    beginCountdown()
                } else {
                    setupStep = "weapon"
                    updateState(status: "Choose a weapon.")
                }
            case .restartRun:
                let bestScore = run.bestScore
                let bestWave = run.bestWave
                run = RunSnapshot()
                run.bestScore = bestScore
                run.bestWave = bestWave
                returnToSetup()
            case .resetScores:
                guard canResetScores == true, run.hasStarted else { break }
                run = RunSnapshot()
                returnToSetup()
            }
        }

        private func returnToSetup() {
            countdownGeneration &+= 1
            setupStep = "world"
            mode = "wand"
            seeThrough = false
            run.hasStarted = false
            run.countdownRemaining = 0
            updateState(status: "Choose your world.")
        }

        private func beginCountdown() {
            countdownGeneration &+= 1
            let generation = countdownGeneration
            setupStep = nil
            run.hasStarted = true
            run.countdownRemaining = 3
            updateState(status: "3…")
            for second in 1...3 {
                queue.asyncAfter(deadline: .now() + Double(second)) { [weak self] in
                    guard let self, !self.stopped, self.countdownGeneration == generation, self.run.hasStarted else {
                        return
                    }
                    self.run.countdownRemaining = Double(3 - second)
                    self.updateState(status: second == 3 ? "Mac ready for gestures." : "\(3 - second)…")
                }
            }
        }

        private func updateState(status: String, ready: Bool = true) {
            storage.run = run
            state = HostState(
                status: status, mode: mode, isSeeThrough: seeThrough, ready: ready, run: run, setupStep: setupStep,
                canResetScores: canResetScores)
            if session != nil { send(.state, state: state) }
        }

        private func send(_ kind: ControllerPacket.Kind, state: HostState? = nil) {
            guard let session, let connection else { return }
            sequence += 1
            let packet = ControllerPacket(session: session, sequence: sequence, kind: kind, state: state)
            guard var data = try? JSONEncoder().encode(packet) else { return }
            data.append(10)
            connection.send(
                content: data,
                completion: .contentProcessed { [weak self, weak connection] error in
                    guard let self, let connection, self.connection === connection, let error else { return }
                    self.storage.failure = String(describing: error)
                    self.disconnect(connection)
                })
        }

        private func disconnect(_ connection: NWConnection) {
            guard self.connection === connection else { return }
            if let gesture = inputs.activeGesture {
                storage.inputs.append(WandInput(kind: .cancel, gesture: gesture))
            }
            if session != nil { storage.connections.append(false) }
            self.connection = nil
            session = nil
            connection.stateUpdateHandler = nil
            connection.cancel()
        }
    }
#endif
