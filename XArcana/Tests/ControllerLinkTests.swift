import Network
import XCTest

@testable import XArcana

final class ControllerLinkTests: XCTestCase {
    func testRunSnapshotRoundTripAndLegacyHostCompatibility() throws {
        let state = HostState(status: "Ready", run: RunSnapshot(), setupStep: "world", canResetScores: true)
        XCTAssertEqual(try JSONDecoder().decode(HostState.self, from: JSONEncoder().encode(state)), state)
        let old = Data(
            "{\"status\":\"Ready\",\"mode\":\"wand\",\"isHolding\":false,\"battle\":\"\",\"headStatus\":\"\",\"isSeeThrough\":false,\"ready\":true}"
                .utf8)
        XCTAssertNil(try JSONDecoder().decode(HostState.self, from: old).run)
    }

    func testRestartCannotInterruptAnUncancelledWireGesture() throws {
        var validator = ControllerInputValidator()
        try validator.accept(WandInput(kind: .begin, gesture: 1, timestamp: 1))
        XCTAssertThrowsError(try validator.accept(WandInput(kind: .restartRun, timestamp: 2)))
        XCTAssertThrowsError(try validator.accept(WandInput(kind: .startRun, timestamp: 2)))
        XCTAssertThrowsError(try validator.accept(WandInput(kind: .nextSetupChoice, timestamp: 2)))
        XCTAssertThrowsError(try validator.accept(WandInput(kind: .confirmSetupChoice, timestamp: 2)))
        XCTAssertThrowsError(try validator.accept(WandInput(kind: .resetScores, timestamp: 2)))
        try validator.accept(WandInput(kind: .cancel, gesture: 1, timestamp: 2))
        try validator.accept(WandInput(kind: .restartRun, timestamp: 3))
        try validator.accept(WandInput(kind: .startRun, timestamp: 3.1))
        try validator.accept(WandInput(kind: .nextSetupChoice, timestamp: 3.2))
        try validator.accept(WandInput(kind: .confirmSetupChoice, timestamp: 3.3))
        try validator.accept(WandInput(kind: .resetScores, timestamp: 3.4))
        XCTAssertThrowsError(try validator.accept(WandInput(kind: .end, gesture: 1, timestamp: 4)))
    }

    func testFramingHandlesSplitAndCombinedPackets() throws {
        var decoder = ControllerFrameDecoder()
        XCTAssertTrue(try decoder.append(Data("{\"a\":".utf8)).isEmpty)
        let frames = try decoder.append(Data("1}\n{\"b\":2}\npartial".utf8))
        XCTAssertEqual(frames.map { String(decoding: $0, as: UTF8.self) }, ["{\"a\":1}", "{\"b\":2}"])
        XCTAssertEqual(try decoder.append(Data("\n".utf8)), [Data("partial".utf8)])
    }

    func testFramingRejectsEmptyAndOversizedMessages() throws {
        var empty = ControllerFrameDecoder()
        XCTAssertThrowsError(try empty.append(Data([10])))
        var oversized = ControllerFrameDecoder()
        XCTAssertThrowsError(try oversized.append(Data(repeating: 65, count: 4097)))
        var fragmented = ControllerFrameDecoder()
        XCTAssertTrue(try fragmented.append(Data(repeating: 65, count: 4096)).isEmpty)
        XCTAssertThrowsError(try fragmented.append(Data([65, 10])))
    }

    func testHandshakeVersionSessionAndSequenceValidation() throws {
        let session = UUID()
        var validator = ControllerPacketValidator(session: session)
        XCTAssertThrowsError(try validator.accept(.init(session: session, sequence: 1, kind: .ping)))
        var wrongVersion = ControllerPacket(session: session, sequence: 1, kind: .hello)
        wrongVersion.version = 2
        XCTAssertThrowsError(try validator.accept(wrongVersion))
        XCTAssertThrowsError(try validator.accept(.init(session: UUID(), sequence: 1, kind: .hello)))
        try validator.accept(.init(session: session, sequence: 1, kind: .hello))
        XCTAssertThrowsError(try validator.accept(.init(session: session, sequence: 1, kind: .ping)))
        XCTAssertThrowsError(try validator.accept(.init(session: session, sequence: 3, kind: .ping)))
        XCTAssertThrowsError(try validator.accept(.init(session: session, sequence: 2, kind: .hello)))
        try validator.accept(.init(session: session, sequence: 2, kind: .ping))
    }

    func testPacketPayloadMustMatchItsKind() throws {
        let session = UUID()
        var validator = ControllerPacketValidator()
        try validator.accept(.init(session: session, sequence: 1, kind: .hello))
        XCTAssertThrowsError(try validator.accept(.init(session: session, sequence: 2, kind: .input)))
        XCTAssertThrowsError(
            try validator.accept(.init(session: session, sequence: 2, kind: .ping, state: HostState())))
        try validator.accept(
            .init(session: session, sequence: 2, kind: .input, input: WandInput(kind: .voice, command: "cast")))
    }

    func testGesturePhasesRejectStaleOrMixedStrokes() throws {
        var validator = ControllerInputValidator()
        XCTAssertThrowsError(try validator.accept(WandInput(kind: .end, gesture: 1)))
        try validator.accept(WandInput(kind: .begin, gesture: 1, timestamp: 10))
        XCTAssertThrowsError(try validator.accept(WandInput(kind: .begin, gesture: 2, timestamp: 10)))
        XCTAssertThrowsError(
            try validator.accept(WandInput(kind: .sample, gesture: 2, timestamp: 11, yaw: 0, pitch: 0)))
        XCTAssertThrowsError(try validator.accept(WandInput(kind: .sample, timestamp: 11, yaw: 0, pitch: 0)))
        XCTAssertThrowsError(try validator.accept(WandInput(kind: .sample, gesture: 1, timestamp: 9, yaw: 0, pitch: 0)))
        try validator.accept(WandInput(kind: .sample, gesture: 1, timestamp: 11, yaw: 0.2, pitch: 0.1))
        try validator.accept(WandInput(kind: .end, gesture: 1, timestamp: 12, yaw: 0.3, pitch: 0.2))
        XCTAssertNil(validator.activeGesture)
        XCTAssertThrowsError(try validator.accept(WandInput(kind: .begin, gesture: 1, timestamp: 13)))
        try validator.accept(WandInput(kind: .begin, gesture: 2, timestamp: 13))
        try validator.accept(WandInput(kind: .cancel, gesture: 2, timestamp: 14))
        XCTAssertNil(validator.activeGesture)
    }

    func testInvalidNumbersAndMissingFieldsAreRejected() {
        for input in [
            WandInput(kind: .sample, yaw: .nan, pitch: 0),
            WandInput(kind: .sample, yaw: 0, pitch: .infinity),
            WandInput(kind: .sample, timestamp: .infinity, yaw: 0, pitch: 0),
            WandInput(kind: .sample, timestamp: -1, yaw: 0, pitch: 0),
            WandInput(kind: .sample, yaw: 0),
            WandInput(kind: .sample),
            WandInput(kind: .voice, command: String(repeating: "a", count: 129)),
            WandInput(kind: .voice), WandInput(kind: .sceneMode),
        ] {
            var validator = ControllerInputValidator()
            XCTAssertThrowsError(try validator.accept(input))
        }
    }

    func testIdleMotionCoalescesButStrokeSamplesAndReleaseStayOrdered() throws {
        var outbox = ControllerOutbox()
        for i in 0..<1000 {
            try outbox.append(.init(kind: .input, input: WandInput(kind: .sample, yaw: Float(i), pitch: 0)))
        }
        XCTAssertEqual(outbox.items.count, 1)
        XCTAssertEqual(outbox.pop()?.input?.yaw, 999)
        let stroke = [
            WandInput(kind: .begin, gesture: 1, yaw: 0, pitch: 0),
            WandInput(kind: .sample, gesture: 1, yaw: 0.2, pitch: 0.1),
            WandInput(kind: .sample, gesture: 1, yaw: 0.4, pitch: 0.3),
            WandInput(kind: .end, gesture: 1, yaw: 0.6, pitch: 0.5),
        ]
        for input in stroke { try outbox.append(.init(kind: .input, input: input)) }
        XCTAssertEqual(outbox.items.compactMap(\.input), stroke)
        XCTAssertEqual(outbox.items.last?.input?.yaw, 0.6)
    }

    func testQueueOverflowIsAnErrorAndDoesNotRemoveStrokeData() throws {
        var outbox = ControllerOutbox()
        for _ in 0..<ControllerOutbox.capacity {
            try outbox.append(.init(kind: .input, input: WandInput(kind: .sample, gesture: 1, yaw: 0, pitch: 0)))
        }
        XCTAssertThrowsError(try outbox.append(.init(kind: .input, input: WandInput(kind: .end, gesture: 1))))
        XCTAssertEqual(outbox.items.count, ControllerOutbox.capacity)
    }

    func testFinalAnglesAndHostStateRoundTrip() throws {
        let packet = ControllerPacket(
            session: UUID(), sequence: 5, kind: .input,
            input: WandInput(kind: .end, gesture: 7, timestamp: 0.25, yaw: 1.5, pitch: -0.2))
        let decoded = try JSONDecoder().decode(ControllerPacket.self, from: JSONEncoder().encode(packet))
        XCTAssertEqual(decoded.input, packet.input)
        let state = HostState(
            status: "Ready", mode: "bow", isHolding: true, battle: "3 enemies",
            headStatus: "Tracking", isSeeThrough: true, ready: false)
        XCTAssertEqual(try JSONDecoder().decode(HostState.self, from: JSONEncoder().encode(state)), state)
    }

    @MainActor
    func testLoopbackDeliversOrderedStrokeAndCancelsOnDisconnect() async throws {
        let server = ControllerServer()
        let client = ControllerClient()
        defer {
            client.stop()
            server.stop()
        }
        server.start()
        for _ in 0..<100 where server.port == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        let port = try XCTUnwrap(server.port, "Listener did not become ready")
        let connected = expectation(description: "Handshake")
        var isConnected = false
        client.onConnection = { ready, _ in
            isConnected = ready
            if ready { connected.fulfill() }
        }
        client.connect(to: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!))
        await fulfillment(of: [connected], timeout: 5)
        guard isConnected else { return }
        let received = expectation(description: "Ordered stroke")
        received.expectedFulfillmentCount = 4
        var inputs: [WandInput] = []
        server.onInput = { input in
            inputs.append(input)
            received.fulfill()
        }
        let stroke = [
            WandInput(kind: .begin, gesture: 1, timestamp: 1, yaw: 0, pitch: 0),
            WandInput(kind: .sample, gesture: 1, timestamp: 2, yaw: 0.3, pitch: 0.4),
            WandInput(kind: .end, gesture: 1, timestamp: 3, yaw: 0.5, pitch: 0.6),
            WandInput(kind: .begin, gesture: 2, timestamp: 4, yaw: 0.5, pitch: 0.6),
        ]
        for input in stroke { XCTAssertTrue(client.send(input)) }
        await fulfillment(of: [received], timeout: 5)
        XCTAssertEqual(inputs, stroke)
        let cancelled = expectation(description: "Disconnect cancels active stroke")
        server.onInput = { input in
            XCTAssertEqual(input.kind, .cancel)
            XCTAssertEqual(input.gesture, 2)
            cancelled.fulfill()
        }
        client.stop()
        await fulfillment(of: [cancelled], timeout: 5)
        XCTAssertFalse(client.send(WandInput(kind: .voice, command: "shoot")))
    }
}
