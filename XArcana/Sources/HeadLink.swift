import Foundation
import Network
import simd

struct HeadPoseFilter {
    private(set) var orientation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
    private var lastTime: TimeInterval?

    mutating func reset(at time: TimeInterval?) {
        orientation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        lastTime = time
    }

    mutating func update(_ relativePose: simd_quatf, at time: TimeInterval) -> simd_quatf {
        let elapsed = max(0, time - (lastTime ?? time))
        lastTime = time
        var pose = simd_normalize(relativePose)
        if pose.real < 0 { pose = simd_quatf(vector: -pose.vector) }
        let angle = pose.angle
        let target =
            angle > 0.000001
            ? simd_quatf(angle: angle - 0.12 * sin(angle), axis: pose.axis)
            : pose
        let difference = orientation.inverse * target
        // Ignore less than 0.07 degrees of motion after reducing rotational gain.
        guard simd_length(difference.imag) > 0.0006 else { return orientation }
        #if targetEnvironment(macCatalyst)
            let weight = Float(1 - exp(-elapsed / 0.018))
        #else
            let weight = Float(1 - exp(-elapsed / 0.045))
        #endif
        orientation = simd_normalize(simd_slerp(orientation, target, weight))
        return orientation
    }
}

/// Keeps the view level even if the glasses are laid on their side between sessions.
enum HeadHorizon {
    static func upright(_ pose: simd_quatf, previous: simd_quatf) -> simd_quatf {
        let forward = pose.act(SIMD3<Float>(0, 0, -1))
        let horizontal = hypot(forward.x, forward.z)
        let prior = previous.act(SIMD3<Float>(0, 0, -1))
        let yaw = horizontal > 0.001 ? atan2(-forward.x, -forward.z) : atan2(-prior.x, -prior.z)
        let pitch = max(-Float.pi / 2 + 0.002, min(Float.pi / 2 - 0.002, asin(max(-1, min(1, forward.y)))))
        return simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
    }
}

struct HeadSample: Decodable {
    let yaw: Float
    let pitch: Float
    let roll: Float
    let gravityPitch: Float?
    let gravityRoll: Float?
    let heading: Float?

    init(
        yaw: Float, pitch: Float, roll: Float, gravityPitch: Float? = nil, gravityRoll: Float? = nil,
        heading: Float? = nil
    ) {
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
        self.gravityPitch = gravityPitch
        self.gravityRoll = gravityRoll
        self.heading = heading
    }

    var gravityReferenced: Bool { gravityPitch != nil && gravityRoll != nil && heading != nil }

    var orientation: simd_quatf? {
        let yaw = gravityReferenced ? heading! : yaw
        let pitch = gravityReferenced ? gravityPitch! : pitch
        let roll = gravityReferenced ? gravityRoll! : roll
        guard [yaw, pitch, roll].allSatisfy({ $0.isFinite && abs($0) <= .pi + 0.01 }) else { return nil }
        return simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: roll, axis: SIMD3(0, 0, 1))
    }
}

struct HeadBridgeStatus: Decodable {
    enum State: String, Decodable {
        case waitingForGlasses, calibrating, streaming
    }
    let state: State

    var message: String? {
        switch state {
        case .waitingForGlasses: return "Mac connected · plug Air 2 into Mac"
        case .calibrating: return "Mac connected · keep Air 2 still for five seconds"
        case .streaming: return nil
        }
    }
}

// All Network.framework callbacks and SceneKit updates run on the main queue.
final class HeadLink {
    private let room: GameWorld
    private let notify: () -> Void
    private let decoder = JSONDecoder()
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var endpoints: Set<NWEndpoint> = []
    private var selected: NWEndpoint?
    private var buffer = Data()
    private var watchdog: Timer?
    private var lastSample: TimeInterval = 0
    private var lastPacket: TimeInterval = 0

    init(room: GameWorld, notify: @escaping () -> Void) {
        self.room = room
        self.notify = notify
    }

    func start() {
        guard watchdog == nil else { return }
        discover()
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.browser == nil { self.discover() }
            let now = ProcessInfo.processInfo.systemUptime
            if self.connection != nil, now - self.lastPacket > 3 {
                self.disconnect()
            } else if self.room.isHeadTracked, now - self.lastSample > 2 {
                self.room.setHeadPose(nil)
                self.status("Mac connected · waiting for Air 2 motion data")
            }
            self.connectIfPossible()
        }
    }

    private func discover() {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjour(type: RuntimeIdentifiers.headService, domain: "local."), using: parameters)
        self.browser = browser
        status("Looking for the Mac head tracker")
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            guard let self, let browser, self.browser === browser else { return }
            switch state {
            case .waiting(let error):
                if case .dns(let code) = error, code == -65570 {
                    self.status("Allow Local Network in Settings for head tracking", needsPermission: true)
                } else {
                    self.status("Waiting for the local network")
                }
            case .failed:
                self.endpoints = []
                self.disconnect()
                self.browser = nil
                browser.cancel()
            default: break
            }
        }
        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            guard let self, let browser, self.browser === browser else { return }
            self.endpoints = Set(results.map(\.endpoint))
            if let selected = self.selected, !self.endpoints.contains(selected) { self.disconnect() }
            self.connectIfPossible()
        }
        browser.start(queue: .main)
    }

    private func connectIfPossible() {
        guard connection == nil, let endpoint = endpoints.first else { return }
        guard endpoints.count == 1 else {
            status("More than one Mac head tracker is available")
            return
        }
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = true
        let link = NWConnection(to: endpoint, using: parameters)
        selected = endpoint
        connection = link
        lastPacket = ProcessInfo.processInfo.systemUptime
        status("Connecting to the Mac head tracker")
        link.stateUpdateHandler = { [weak self, weak link] state in
            guard let self, let link, self.connection === link else { return }
            switch state {
            case .ready: self.receive(on: link)
            case .failed, .cancelled: self.disconnect()
            default: break
            }
        }
        link.start(queue: .main)
    }

    private func receive(on link: NWConnection) {
        link.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak link] data, _, done, error in
            guard let self, let link, self.connection === link else { return }
            if let data {
                self.buffer.append(data)
                var newest: simd_quatf?
                var gravityReferenced = false
                var sensorMessage: String?
                while let newline = self.buffer.firstIndex(of: 10) {
                    let line = self.buffer[..<newline]
                    if line.count <= 256, let sample = try? self.decoder.decode(HeadSample.self, from: line),
                        let pose = sample.orientation
                    {
                        newest = pose
                        gravityReferenced = sample.gravityReferenced
                        sensorMessage = nil
                        self.lastPacket = ProcessInfo.processInfo.systemUptime
                    } else if line.count <= 256,
                        let state = try? self.decoder.decode(HeadBridgeStatus.self, from: line)
                    {
                        self.lastPacket = ProcessInfo.processInfo.systemUptime
                        if let message = state.message {
                            newest = nil
                            sensorMessage = message
                        }
                    }
                    self.buffer.removeSubrange(...newline)
                }
                if let newest {
                    self.lastSample = ProcessInfo.processInfo.systemUptime
                    self.room.setHeadPose(newest, gravityReferenced: gravityReferenced)
                    self.status("Head tracking on")
                } else if let sensorMessage {
                    self.room.setHeadPose(nil)
                    self.status(sensorMessage)
                }
            }
            if done || error != nil || self.buffer.count > 256 { self.disconnect() } else { self.receive(on: link) }
        }
    }

    private func status(_ message: String, needsPermission: Bool = false) {
        guard room.trackingMessage != message || room.needsLocalNetworkPermission != needsPermission else { return }
        room.trackingMessage = message
        room.needsLocalNetworkPermission = needsPermission
        notify()
    }

    private func disconnect() {
        let link = connection
        connection = nil
        selected = nil
        link?.cancel()
        buffer.removeAll(keepingCapacity: true)
        room.setHeadPose(nil)
        status("Looking for the Mac head tracker")
    }

    func stop() {
        watchdog?.invalidate()
        watchdog = nil
        let previous = browser
        browser = nil
        previous?.cancel()
        endpoints = []
        disconnect()
        status("Head tracking offline")
    }
}
