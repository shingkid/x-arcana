import Foundation
import Network
import simd
import Darwin

func log(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

struct Pose: Encodable {
    let yaw: Double
    let pitch: Double
    let roll: Double
    let gravityPitch: Double
    let gravityRoll: Double
    let heading: Double
}

struct SensorStatus: Encodable {
    let state: String
}

final class Client {
    let connection: NWConnection
    var sending = false
    init(_ connection: NWConnection) { self.connection = connection }
}

final class Bridge {
    private var listener: NWListener?
    private var clients: [UUID: Client] = [:]
    private var reference: simd_quatd?
    private var sequence = 0
    private var sensorState = "waitingForGlasses"
    private var heartbeat: DispatchSourceTimer?
    private let probe: Bool
    init(probe: Bool) { self.probe = probe }

    func start() throws {
        if !probe {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            let listener = try NWListener(using: parameters)
            listener.service = NWListener.Service(name: "X Arcana Head Tracking", type: "_ember-head._tcp")
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: log("Head tracking available on local port \(listener.port?.rawValue ?? 0).")
                case .failed(let error): log("Local connection failed: \(error)"); exit(1)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                guard self.clients.count < 4 else { connection.cancel(); return }
                let id = UUID()
                let client = Client(connection)
                self.clients[id] = client
                connection.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        log("Head tracking client connected: \(connection.endpoint).")
                        self?.sendStatus()
                    case .failed, .cancelled: self?.clients.removeValue(forKey: id)
                    default: break
                    }
                }
                connection.start(queue: .main)
            }
            self.listener = listener
            listener.start(queue: .main)
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now(), repeating: 1)
            timer.setEventHandler { [weak self] in
                self?.sendStatus()
            }
            heartbeat = timer
            timer.resume()
        }
        DispatchQueue.global(qos: .userInteractive).async { [self] in readSensor() }
    }

    private func readSensor() {
        while true {
            if readSession() { return }
            if probe { exit(1) }
            Thread.sleep(forTimeInterval: 2)
        }
    }

    private func setSensorState(_ state: String) {
        DispatchQueue.main.async { [self] in
            guard sensorState != state else { return }
            sensorState = state
            reference = nil
            sendStatus()
        }
    }

    private func readSession() -> Bool {
        let status = xarcana_sensor_open()
        guard status == 0 else {
            xarcana_sensor_close()
            setSensorState("waitingForGlasses")
            if probe { log("Cannot open Air 2 sensor (SDK error \(status)).") }
            return false
        }
        defer { xarcana_sensor_close() }
        log("Air 2 connected. Keep the glasses still for five seconds.")
        setSensorState("calibrating")
        let started = ProcessInfo.processInfo.systemUptime
        var lastSample: UInt64 = 0
        var lastSent: UInt64 = 0
        var lastReceived = started
        var samples = 0
        while true {
            var sample = XArcanaQuaternion()
            let status = xarcana_sensor_read(&sample)
            guard status == 0 else {
                log("Air 2 disconnected (SDK error \(status)). Waiting for reconnection.")
                setSensorState("waitingForGlasses")
                return false
            }
            let now = ProcessInfo.processInfo.systemUptime
            if sample.timestamp != 0 && sample.timestamp != lastSample {
                lastSample = sample.timestamp
                lastReceived = now
                samples += 1
                if now - started >= 5 && sample.timestamp - lastSent >= 11_111_111 {
                    lastSent = sample.timestamp
                    let q = simd_quatd(ix: sample.x, iy: sample.y, iz: sample.z, r: sample.w)
                    guard q.vector.x.isFinite, q.vector.y.isFinite, q.vector.z.isFinite, q.vector.w.isFinite,
                          simd_length(q.vector) > 0.5 else {
                        log("Invalid sensor orientation. Reconnecting.")
                        setSensorState("waitingForGlasses")
                        return false
                    }
                    DispatchQueue.main.async { [self] in publish(simd_normalize(q)) }
                }
            }
            if now - lastReceived > 2 {
                log("No fresh Air 2 samples. Waiting for reconnection.")
                setSensorState("waitingForGlasses")
                return false
            }
            if probe && now - started >= 8 {
                log("Sensor probe complete: \(samples) real samples in eight seconds.")
                xarcana_sensor_close()
                exit(samples > 0 ? 0 : 1)
            }
        }
    }

    private func publish(_ orientation: simd_quatd) {
        if reference == nil {
            reference = orientation
            sensorState = "streaming"
            log("Air 2 head tracking ready.")
        }
        let q = simd_normalize(reference!.inverse * orientation)
        let m = simd_double3x3(q)
        let gravity = simd_double3x3(orientation)
        let pose = Pose(yaw: atan2(m.columns.2.x, m.columns.2.z),
                        pitch: asin(max(-1, min(1, -m.columns.2.y))),
                        roll: atan2(m.columns.0.y, m.columns.1.y),
                        gravityPitch: asin(max(-1, min(1, -gravity.columns.2.y))),
                        gravityRoll: atan2(gravity.columns.0.y, gravity.columns.1.y),
                        heading: atan2(gravity.columns.2.x, gravity.columns.2.z))
        guard let encoded = try? JSONEncoder().encode(pose) else { return }
        let line = encoded + Data([10])
        sequence += 1
        if probe && sequence % 30 == 0 { FileHandle.standardOutput.write(line) }
        send(line)
    }

    private func sendStatus() {
        guard let encoded = try? JSONEncoder().encode(SensorStatus(state: sensorState)) else { return }
        send(encoded + Data([10]))
    }

    private func send(_ line: Data) {
        for client in clients.values where !client.sending {
            guard case .ready = client.connection.state else { continue }
            client.sending = true
            client.connection.send(content: line, completion: .contentProcessed { error in
                client.sending = false
                if error != nil { client.connection.cancel() }
            })
        }
    }
}

let lockPath = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent().appendingPathComponent(".ember-head.lock").path
let lockDescriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
guard lockDescriptor >= 0, flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
    log("Head tracking is already running, or its local lock file is unavailable.")
    exit(1)
}
let bridge = Bridge(probe: CommandLine.arguments.contains("--probe"))
log("Head tracker is running. Plug Air 2 into this Mac. Close this window to stop.")
do { try bridge.start(); dispatchMain() }
catch { log("Head tracking could not start: \(error)"); exit(1) }
