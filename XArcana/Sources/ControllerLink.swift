import Foundation
import Network

struct WandInput: Codable, Equatable {
    enum Kind: String, Codable {
        case begin, sample, end, cancel, voice, sceneMode, restartRun, resetScores, startRun, nextSetupChoice,
            confirmSetupChoice
    }
    let kind: Kind
    let gesture: UInt64
    let timestamp: Double
    let yaw: Float?
    let pitch: Float?
    let command: String?
    let seeThrough: Bool?

    init(
        kind: Kind, gesture: UInt64 = 0, timestamp: Double = 0, yaw: Float? = nil,
        pitch: Float? = nil, command: String? = nil, seeThrough: Bool? = nil
    ) {
        self.kind = kind
        self.gesture = gesture
        self.timestamp = timestamp
        self.yaw = yaw
        self.pitch = pitch
        self.command = command
        self.seeThrough = seeThrough
    }
}

struct HostState: Codable, Equatable {
    let status: String
    let mode: String
    let isHolding: Bool
    let battle: String
    let headStatus: String
    let isSeeThrough: Bool
    let ready: Bool
    let run: RunSnapshot?
    let castPreview: String?
    let shieldReady: Bool?
    let setupStep: String?
    let canResetScores: Bool?

    init(
        status: String = "", mode: String = "wand", isHolding: Bool = false,
        battle: String = "", headStatus: String = "", isSeeThrough: Bool = false, ready: Bool = true,
        run: RunSnapshot? = nil, castPreview: String? = nil, shieldReady: Bool? = nil,
        setupStep: String? = nil, canResetScores: Bool? = nil
    ) {
        self.status = status
        self.mode = mode
        self.isHolding = isHolding
        self.battle = battle
        self.headStatus = headStatus
        self.isSeeThrough = isSeeThrough
        self.ready = ready
        self.run = run
        self.castPreview = castPreview
        self.shieldReady = shieldReady
        self.setupStep = setupStep
        self.canResetScores = canResetScores
    }
}

enum ControllerProtocolError: Error { case frame, packet, phase, overflow }

struct ControllerFrameDecoder {
    static let maximumBytes = 4096
    private var buffer = Data()

    mutating func append(_ data: Data) throws -> [Data] {
        // Network reads are bounded too. Reject oversized callers before allocating.
        guard data.count <= Self.maximumBytes else { throw ControllerProtocolError.frame }
        buffer.append(data)
        var frames: [Data] = []
        while let newline = buffer.firstIndex(of: 10) {
            let frame = Data(buffer[..<newline])
            guard !frame.isEmpty, frame.count <= Self.maximumBytes else { throw ControllerProtocolError.frame }
            frames.append(frame)
            buffer.removeSubrange(...newline)
        }
        guard buffer.count <= Self.maximumBytes else { throw ControllerProtocolError.frame }
        return frames
    }
}

struct ControllerPacket: Codable {
    enum Kind: String, Codable { case hello, input, state, ping }
    var version = 1
    let session: UUID
    let sequence: UInt64
    let kind: Kind
    var input: WandInput?
    var state: HostState?
}

struct ControllerPacketValidator {
    private(set) var session: UUID?
    private var sequence: UInt64 = 0

    init(session: UUID? = nil) { self.session = session }

    mutating func accept(_ packet: ControllerPacket) throws {
        guard packet.version == 1, sequence < UInt64.max, packet.sequence == sequence + 1,
            session == nil || session == packet.session
        else { throw ControllerProtocolError.packet }
        guard sequence == 0 ? packet.kind == .hello : packet.kind != .hello else {
            throw ControllerProtocolError.packet
        }
        switch packet.kind {
        case .hello, .ping:
            guard packet.input == nil, packet.state == nil else { throw ControllerProtocolError.packet }
        case .input:
            guard packet.input != nil, packet.state == nil else { throw ControllerProtocolError.packet }
        case .state:
            guard packet.input == nil, packet.state != nil else { throw ControllerProtocolError.packet }
        }
        session = packet.session
        sequence = packet.sequence
    }
}

struct ControllerInputValidator {
    private(set) var activeGesture: UInt64?
    private var lastGesture: UInt64 = 0
    private var lastTimestamp: Double = 0

    mutating func accept(_ input: WandInput) throws {
        guard input.timestamp.isFinite, input.timestamp >= 0,
            input.yaw?.isFinite != false, input.pitch?.isFinite != false,
            (input.yaw == nil) == (input.pitch == nil),
            (input.command?.utf8.count ?? 0) <= 128
        else { throw ControllerProtocolError.packet }
        switch input.kind {
        case .begin:
            guard activeGesture == nil, input.gesture > lastGesture else { throw ControllerProtocolError.phase }
            activeGesture = input.gesture
            lastGesture = input.gesture
            lastTimestamp = input.timestamp
        case .sample:
            guard input.yaw != nil else { throw ControllerProtocolError.packet }
            if input.gesture == 0 {
                guard activeGesture == nil else { throw ControllerProtocolError.phase }
            } else {
                guard activeGesture == input.gesture, input.timestamp >= lastTimestamp else {
                    throw ControllerProtocolError.phase
                }
                lastTimestamp = input.timestamp
            }
        case .end, .cancel:
            guard activeGesture == input.gesture, input.timestamp >= lastTimestamp else {
                throw ControllerProtocolError.phase
            }
            activeGesture = nil
        case .voice:
            guard input.gesture == 0, let command = input.command, !command.isEmpty else {
                throw ControllerProtocolError.packet
            }
        case .sceneMode:
            guard input.gesture == 0, input.seeThrough != nil else { throw ControllerProtocolError.packet }
        case .restartRun, .resetScores, .startRun, .nextSetupChoice, .confirmSetupChoice:
            guard input.gesture == 0, activeGesture == nil else { throw ControllerProtocolError.phase }
        }
    }
}

// Assign packet sequences at transmission, after replacing stale idle motion.
struct ControllerOutbox {
    struct Item {
        let kind: ControllerPacket.Kind
        var input: WandInput?
        var state: HostState?
        var replaceable: Bool { kind == .state || (kind == .input && input?.kind == .sample && input?.gesture == 0) }
    }
    static let capacity = 256
    private(set) var items: [Item] = []

    mutating func append(_ item: Item) throws {
        if item.replaceable, let last = items.last, last.replaceable, last.kind == item.kind {
            items[items.count - 1] = item
            return
        }
        guard items.count < Self.capacity else { throw ControllerProtocolError.overflow }
        items.append(item)
    }

    mutating func pop() -> Item? { items.isEmpty ? nil : items.removeFirst() }
}

private func controllerParameters() -> NWParameters {
    let tcp = NWProtocolTCP.Options()
    tcp.noDelay = true
    let parameters = NWParameters(tls: nil, tcp: tcp)
    parameters.includePeerToPeer = true
    return parameters
}

// Each connection owns its buffers and callbacks. A cancelled connection cannot
// deliver events to its replacement. Network callbacks run on the main queue.
@MainActor
private final class ControllerChannel {
    let connection: NWConnection
    var onReady: (() -> Void)?
    var onPacket: ((ControllerPacket) throws -> Void)?
    var onClose: (() -> Void)?
    private(set) var session: UUID?
    private var validator: ControllerPacketValidator
    private var frames = ControllerFrameDecoder()
    private var outbox = ControllerOutbox()
    private var sequence: UInt64 = 0
    private var sending = false
    private var ready = false
    private var closed = false
    private var timer: Timer?
    private var lastReceived = ProcessInfo.processInfo.systemUptime

    init(connection: NWConnection, session: UUID? = nil) {
        self.connection = connection
        self.session = session
        validator = ControllerPacketValidator(session: session)
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                switch state {
                case .ready:
                    self.ready = true
                    self.onReady?()
                    self.receive()
                case .failed, .cancelled: self.close()
                default: break
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                if ProcessInfo.processInfo.systemUptime - self.lastReceived > 4 {
                    self.close()
                } else if self.ready, self.sequence > 0 {
                    _ = self.enqueue(.init(kind: .ping))
                }
            }
        }
        connection.start(queue: .main)
    }

    @discardableResult
    func enqueue(_ item: ControllerOutbox.Item) -> Bool {
        guard !closed, ready, session != nil else { return false }
        do { try outbox.append(item) } catch {
            close()
            return false
        }
        pump()
        return !closed
    }

    private func pump() {
        guard !closed, !sending, let session, let item = outbox.pop() else { return }
        guard sequence < UInt64.max else {
            close()
            return
        }
        sequence += 1
        let packet = ControllerPacket(
            session: session, sequence: sequence, kind: item.kind,
            input: item.input, state: item.state)
        guard var data = try? JSONEncoder().encode(packet), data.count <= ControllerFrameDecoder.maximumBytes else {
            close()
            return
        }
        data.append(10)
        sending = true
        connection.send(
            content: data,
            completion: .contentProcessed { [weak self] error in
                MainActor.assumeIsolated {
                    guard let self, !self.closed else { return }
                    self.sending = false
                    if error != nil { self.close() } else { self.pump() }
                }
            })
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: ControllerFrameDecoder.maximumBytes) {
            [weak self] data, _, complete, error in
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                do {
                    if let data {
                        for frame in try self.frames.append(data) {
                            let packet = try JSONDecoder().decode(ControllerPacket.self, from: frame)
                            try self.validator.accept(packet)
                            self.session = packet.session
                            try self.onPacket?(packet)
                            if self.closed { return }
                            self.lastReceived = ProcessInfo.processInfo.systemUptime
                        }
                    }
                    if complete || error != nil { self.close() } else { self.receive() }
                } catch { self.close() }
            }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        timer?.invalidate()
        timer = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        outbox = ControllerOutbox()
        frames = ControllerFrameDecoder()
        let callback = onClose
        onClose = nil
        onPacket = nil
        onReady = nil
        callback?()
    }
}

@MainActor
final class ControllerServer {
    var onInput: ((WandInput) -> Void)?
    var onConnection: ((Bool) -> Void)?
    var port: UInt16? { listening ? listener?.port?.rawValue : nil }
    private var listener: NWListener?
    private var listening = false
    private var channel: ControllerChannel?
    private var inputs = ControllerInputValidator()
    private var state = HostState()
    private var connected = false
    private var running = false
    private var retry: Timer?

    func start() {
        guard !running else { return }
        running = true
        listen()
    }

    private func listen() {
        guard running, listener == nil else { return }
        do {
            let listener = try NWListener(using: controllerParameters(), on: .any)
            self.listener = listener
            listener.service = NWListener.Service(name: nil, type: RuntimeIdentifiers.controllerService)
            listener.stateUpdateHandler = { [weak self, weak listener] status in
                MainActor.assumeIsolated {
                    guard let self, let listener, self.listener === listener else { return }
                    if case .ready = status { self.listening = true }
                    if case .failed = status {
                        self.listening = false
                        self.listener = nil
                        listener.cancel()
                        self.channel?.close()
                        self.scheduleRetry()
                    }
                }
            }
            listener.newConnectionHandler = { [weak self, weak listener] connection in
                MainActor.assumeIsolated {
                    guard let self, let listener, self.running, self.listener === listener,
                        self.channel == nil
                    else {
                        connection.cancel()
                        return
                    }
                    self.accept(connection)
                }
            }
            listener.start(queue: .main)
        } catch { scheduleRetry() }
    }

    private func scheduleRetry() {
        guard running, retry == nil else { return }
        retry = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.retry = nil
                self?.listen()
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        let channel = ControllerChannel(connection: connection)
        self.channel = channel
        inputs = ControllerInputValidator()
        channel.onPacket = { [weak self, weak channel] packet in
            guard let self, let channel, self.channel === channel else { return }
            switch packet.kind {
            case .hello:
                self.connected = true
                channel.enqueue(.init(kind: .hello))
                self.onConnection?(true)
                channel.enqueue(.init(kind: .state, state: self.state))
            case .input:
                guard self.connected, let input = packet.input else { throw ControllerProtocolError.packet }
                try self.inputs.accept(input)
                self.onInput?(input)
            case .ping: break
            case .state: throw ControllerProtocolError.packet
            }
        }
        channel.onClose = { [weak self, weak channel] in
            guard let self, let channel, self.channel === channel else { return }
            self.channel = nil
            if let gesture = self.inputs.activeGesture {
                self.onInput?(WandInput(kind: .cancel, gesture: gesture))
            }
            self.inputs = ControllerInputValidator()
            if self.connected {
                self.connected = false
                self.onConnection?(false)
            }
        }
        channel.start()
    }

    func broadcast(_ state: HostState) {
        self.state = state
        if connected { channel?.enqueue(.init(kind: .state, state: state)) }
    }

    func stop() {
        running = false
        retry?.invalidate()
        retry = nil
        let previous = listener
        listening = false
        listener = nil
        previous?.cancel()
        channel?.close()
    }
}

@MainActor
final class ControllerClient {
    var onState: ((HostState) -> Void)?
    var onConnection: ((Bool, String) -> Void)?
    private var browser: NWBrowser?
    private var endpoints: Set<NWEndpoint> = []
    private var selected: NWEndpoint?
    private var channel: ControllerChannel?
    private var inputs = ControllerInputValidator()
    private var timer: Timer?
    private var connected = false
    private var nextAttempt: TimeInterval = 0
    private var lastStatus: String?

    func start() {
        guard timer == nil else { return }
        discover()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.browser == nil { self.discover() }
                self.connectIfPossible()
            }
        }
    }

    private func status(_ message: String) {
        guard lastStatus != message else { return }
        lastStatus = message
        onConnection?(connected, message)
    }

    private func discover() {
        let browser = NWBrowser(
            for: .bonjour(type: RuntimeIdentifiers.controllerService, domain: "local."),
            using: controllerParameters())
        self.browser = browser
        status("Looking for X Arcana on your Mac")
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            MainActor.assumeIsolated {
                guard let self, let browser, self.browser === browser else { return }
                switch state {
                case .waiting(let error):
                    if case .dns(let code) = error, code == -65570 {
                        self.status("Allow Local Network in Settings to connect")
                    } else {
                        self.status("Waiting for the local network")
                    }
                case .failed:
                    self.browser = nil
                    browser.cancel()
                    self.endpoints = []
                    self.channel?.close()
                default: break
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            MainActor.assumeIsolated {
                guard let self, let browser, self.browser === browser else { return }
                self.endpoints = Set(results.map(\.endpoint))
                if let selected = self.selected, !self.endpoints.contains(selected) { self.channel?.close() }
                self.connectIfPossible()
            }
        }
        browser.start(queue: .main)
    }

    private func connectIfPossible() {
        guard channel == nil, ProcessInfo.processInfo.systemUptime >= nextAttempt else { return }
        guard endpoints.count == 1, let endpoint = endpoints.first else {
            if endpoints.count > 1 { status("More than one Mac is available. Close the other X Arcana hosts.") }
            return
        }
        connect(to: endpoint)
    }

    // Internal endpoint entry also permits a loopback integration test without Bonjour permissions.
    func connect(to endpoint: NWEndpoint) {
        guard channel == nil else { return }
        selected = endpoint
        inputs = ControllerInputValidator()
        let channel = ControllerChannel(
            connection: NWConnection(to: endpoint, using: controllerParameters()), session: UUID())
        self.channel = channel
        status("Connecting to your Mac")
        channel.onReady = { [weak channel] in channel?.enqueue(.init(kind: .hello)) }
        channel.onPacket = { [weak self, weak channel] packet in
            guard let self, let channel, self.channel === channel else { return }
            switch packet.kind {
            case .hello:
                self.connected = true
                self.status("Connected to your Mac")
            case .state:
                guard self.connected, let state = packet.state else { throw ControllerProtocolError.packet }
                self.onState?(state)
            case .ping: break
            case .input: throw ControllerProtocolError.packet
            }
        }
        channel.onClose = { [weak self, weak channel] in
            guard let self, let channel, self.channel === channel else { return }
            self.channel = nil
            self.selected = nil
            self.connected = false
            self.inputs = ControllerInputValidator()
            self.nextAttempt = ProcessInfo.processInfo.systemUptime + 1
            self.status("Disconnected. Looking for your Mac")
        }
        channel.start()
    }

    @discardableResult
    func send(_ input: WandInput) -> Bool {
        guard connected, let channel else { return false }
        do { try inputs.accept(input) } catch {
            channel.close()
            return false
        }
        return channel.enqueue(.init(kind: .input, input: input))
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        let previous = browser
        browser = nil
        previous?.cancel()
        endpoints = []
        channel?.close()
        nextAttempt = 0
        status("Controller offline")
    }
}
