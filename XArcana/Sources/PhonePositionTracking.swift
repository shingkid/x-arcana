import Foundation

#if !targetEnvironment(macCatalyst)
    import ARKit
    import AVFoundation
#endif

/// Keeps delayed permission callbacks and rune movement out of a later tracking session.
struct PhonePositionLifecycle {
    private(set) var request: UUID?
    private(set) var isHolding = false
    private(set) var resumeAfter: TimeInterval = 0

    @discardableResult
    mutating func setEnabled(_ enabled: Bool) -> Bool {
        guard enabled != (request != nil) else { return false }
        request = enabled ? UUID() : nil
        isHolding = false
        resumeAfter = 0
        return true
    }

    mutating func setHolding(_ holding: Bool, at time: TimeInterval) {
        if isHolding && !holding { resumeAfter = time + 0.8 }
        isHolding = holding
    }

    func isCurrent(_ request: UUID) -> Bool { self.request == request }

    func quality(_ quality: PhonePositionSample.Quality, at time: TimeInterval) -> PhonePositionSample.Quality {
        guard quality == .tracking || quality == .limited else { return quality }
        return isHolding || time < resumeAfter ? .suspended : quality
    }

    /// Camera forward is -Z. Match the Mac's yaw convention: forward -Z has heading zero.
    static func heading(cameraBackwardX: Float, cameraBackwardZ: Float) -> Float {
        atan2(cameraBackwardX, cameraBackwardZ)
    }
}

/// Tracks the rear camera pose without a camera view or transmitted camera images.
@MainActor
final class PhonePositionTracking: NSObject {
    var onSample: ((PhonePositionSample, TimeInterval) -> Void)?
    var onStatusChange: ((String) -> Void)?
    private(set) var status = "Phone walking is off."
    private var lifecycle = PhonePositionLifecycle()
    private var origin = UUID()
    private var lastPosition = SIMD3<Float>.zero
    private var lastHeading: Float = 0
    private var lastTimestamp: TimeInterval = 0
    private var lastFrameSent: TimeInterval = 0
    private var lastQuality: PhonePositionSample.Quality = .unavailable

    #if !targetEnvironment(macCatalyst)
        private var arSession: ARSession?
        private var interrupted = false
    #endif

    func configure(enabled: Bool, holding: Bool) {
        let changed = lifecycle.setEnabled(enabled)
        let wasHolding = lifecycle.isHolding
        lifecycle.setHolding(holding, at: ProcessInfo.processInfo.systemUptime)
        if changed {
            if enabled {
                origin = UUID()
                lastPosition = .zero
                lastHeading = 0
                lastFrameSent = 0
                startIfPermitted()
            } else {
                stopCamera()
                setStatus("Phone walking is off.")
            }
        } else if enabled && wasHolding != holding {
            emit(quality: .suspended)
            setStatus(holding ? "Walking paused while drawing." : "Lower the phone to resume walking.")
        }
    }

    func stop() { configure(enabled: false, holding: false) }

    private func setStatus(_ message: String) {
        guard status != message else { return }
        status = message
        onStatusChange?(message)
    }

    private func emit(quality: PhonePositionSample.Quality, timestamp: TimeInterval? = nil) {
        guard lifecycle.request != nil else { return }
        let time = timestamp ?? ProcessInfo.processInfo.systemUptime
        let sample = PhonePositionSample(
            session: origin, x: lastPosition.x, y: lastPosition.y, z: lastPosition.z,
            heading: lastHeading, quality: lifecycle.quality(quality, at: time))
        guard sample.isValid else { return }
        // A lifecycle event can occur between a camera capture and its delegate callback.
        let orderedTime = max(time, lastTimestamp + 0.000001)
        lastTimestamp = orderedTime
        lastQuality = sample.quality
        onSample?(sample, orderedTime)
    }

    private func startIfPermitted() {
        #if targetEnvironment(macCatalyst) || targetEnvironment(simulator)
            setStatus("Phone walking is unavailable on this device.")
            emit(quality: .unavailable)
        #else
            guard ARWorldTrackingConfiguration.isSupported else {
                setStatus("Phone walking is unavailable on this device.")
                emit(quality: .unavailable)
                return
            }
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                startCamera()
            case .notDetermined:
                guard let request = lifecycle.request else { return }
                setStatus("Allow camera access for phone walking.")
                emit(quality: .unavailable)
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    Task { @MainActor in
                        guard let self, self.lifecycle.isCurrent(request) else { return }
                        if granted { self.startCamera() } else { self.cameraDenied() }
                    }
                }
            case .denied, .restricted:
                cameraDenied()
            @unknown default:
                cameraDenied()
            }
        #endif
    }

    private func stopCamera() {
        #if !targetEnvironment(macCatalyst)
            arSession?.delegate = nil
            arSession?.pause()
            arSession = nil
        #endif
    }

    #if !targetEnvironment(macCatalyst)
        private func cameraDenied() {
            setStatus("Allow Camera in Settings to use phone walking.")
            emit(quality: .unavailable)
        }

        private func startCamera() {
            guard lifecycle.request != nil, arSession == nil else { return }
            let session = ARSession()
            session.delegateQueue = .main
            session.delegate = self
            arSession = session
            runWithNewOrigin(session)
        }

        private func runWithNewOrigin(_ session: ARSession) {
            interrupted = false
            origin = UUID()
            lastPosition = .zero
            lastHeading = 0
            lastFrameSent = 0
            setStatus("Finding the room. Hold the phone near your torso.")
            emit(quality: .limited)
            let configuration = ARWorldTrackingConfiguration()
            configuration.worldAlignment = .gravity
            configuration.isLightEstimationEnabled = false
            configuration.isAutoFocusEnabled = true
            session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }
    #endif
}

#if !targetEnvironment(macCatalyst)
    extension PhonePositionTracking: ARSessionDelegate {
        nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
            MainActor.assumeIsolated {
                guard self.arSession === session, !self.interrupted, self.lifecycle.request != nil else { return }
                let quality: PhonePositionSample.Quality
                switch frame.camera.trackingState {
                case .normal: quality = .tracking
                case .limited: quality = .limited
                case .notAvailable: quality = .unavailable
                }
                let effectiveQuality = self.lifecycle.quality(quality, at: frame.timestamp)
                guard effectiveQuality != self.lastQuality || frame.timestamp - self.lastFrameSent >= 1.0 / 30.0 else {
                    return
                }
                let transform = frame.camera.transform
                let position = transform.columns.3
                let heading = PhonePositionLifecycle.heading(
                    cameraBackwardX: transform.columns.2.x, cameraBackwardZ: transform.columns.2.z)
                guard [position.x, position.y, position.z, heading].allSatisfy(\.isFinite),
                    abs(position.x) <= 1_000, abs(position.y) <= 1_000, abs(position.z) <= 1_000
                else {
                    self.emit(quality: .unavailable, timestamp: frame.timestamp)
                    self.setStatus("Phone tracking is unavailable. Toggle walking to retry.")
                    return
                }
                self.lastPosition = SIMD3(position.x, position.y, position.z)
                self.lastHeading = heading
                self.lastFrameSent = frame.timestamp
                self.emit(quality: quality, timestamp: frame.timestamp)
                switch effectiveQuality {
                case .tracking: self.setStatus("Walking tracks the phone near your torso.")
                case .limited: self.setStatus("Tracking is limited. Keep the rear camera uncovered.")
                case .unavailable: self.setStatus("Phone tracking is unavailable.")
                case .suspended:
                    self.setStatus(
                        self.lifecycle.isHolding
                            ? "Walking paused while drawing." : "Lower the phone to resume walking.")
                }
            }
        }

        nonisolated func sessionWasInterrupted(_ session: ARSession) {
            MainActor.assumeIsolated {
                guard self.arSession === session else { return }
                self.interrupted = true
                self.emit(quality: .unavailable)
                self.setStatus("Phone tracking was interrupted.")
            }
        }

        nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            MainActor.assumeIsolated {
                guard self.arSession === session, !self.interrupted else { return }
                switch camera.trackingState {
                case .normal: break
                case .limited: self.emit(quality: .limited)
                case .notAvailable: self.emit(quality: .unavailable)
                }
            }
        }

        nonisolated func sessionInterruptionEnded(_ session: ARSession) {
            MainActor.assumeIsolated {
                guard self.arSession === session, self.lifecycle.request != nil else { return }
                self.runWithNewOrigin(session)
            }
        }

        nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
            MainActor.assumeIsolated {
                guard self.arSession === session else { return }
                self.emit(quality: .unavailable)
                self.setStatus("Phone tracking failed. Toggle walking off and on to retry.")
                self.stopCamera()
            }
        }

        nonisolated func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { false }
    }
#endif
