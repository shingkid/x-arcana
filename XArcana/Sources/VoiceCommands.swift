import AVFoundation
import Speech
import UIKit

enum VoiceCommand: String, Equatable, CaseIterable {
    case cast, shoot, summonAlbert, summonAlan, summonDemon, summonPatronus, lumos, revelio, nyan
}

/// Tracks consumed text so partial results do not cast the same command twice.
struct VoiceCommandParser {
    private var consumedCommands = 0
    private var consumedAudioStart: TimeInterval = -1
    private static let aliases = Dictionary(
        uniqueKeysWithValues: SpellCatalog.voiceAliases.map {
            (normalize($0.phrase), $0.command)
        })
    private static let pattern = try! NSRegularExpression(
        pattern: "\\b(?:"
            + aliases.keys.sorted { $0.count > $1.count }.map { phrase in
                phrase.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
                    .joined(separator: "\\W+")
            }.joined(separator: "|") + ")\\b", options: [.caseInsensitive])

    static func normalize(_ phrase: String) -> String {
        phrase.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    mutating func consume(_ transcript: String, wordTimes: [(range: NSRange, start: TimeInterval)] = [])
        -> [VoiceCommand]
    {
        let matches = Self.pattern.matches(in: transcript, range: NSRange(transcript.startIndex..., in: transcript))
        var commands: [VoiceCommand] = []
        for (index, match) in matches.enumerated() {
            if !wordTimes.isEmpty {
                // Audio timestamps survive revisions to words and punctuation before a command.
                guard
                    let start = wordTimes.first(where: { NSIntersectionRange($0.range, match.range).length > 0 })?
                        .start,
                    start > consumedAudioStart + 0.05
                else { continue }
                consumedAudioStart = start
            } else if index < consumedCommands {
                continue
            }
            guard let range = Range(match.range, in: transcript) else { continue }
            if let command = Self.aliases[Self.normalize(String(transcript[range]))] {
                commands.append(command)
            }
        }
        consumedCommands = max(consumedCommands, matches.count)
        return commands
    }
}

@MainActor
final class VoiceCommands {
    var onCommand: ((VoiceCommand) -> Void)?
    var onStatus: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var restart: Task<Void, Never>?
    private var permissionTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var parser = VoiceCommandParser()
    private var wantsListening = false
    private var interrupted = false
    private var hasTap = false
    private var generation = 0

    deinit {
        restart?.cancel()
        permissionTask?.cancel()
        recognition?.cancel()
        engine.stop()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    func start() {
        guard !wantsListening else { return }
        wantsListening = true
        observeSession()
        permissionTask = Task { [weak self] in
            let speech = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard !Task.isCancelled else { return }
            guard speech == .authorized else {
                self?.onStatus?("Voice is off. Enable Speech Recognition in Settings, or use the screen.")
                self?.wantsListening = false
                return
            }
            let microphone = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
            }
            guard let self, !Task.isCancelled, self.wantsListening else { return }
            guard microphone else {
                self.onStatus?("Voice is off. Enable Microphone in Settings, or use the screen.")
                self.wantsListening = false
                return
            }
            self.beginRecognition()
        }
    }

    func stop() {
        wantsListening = false
        permissionTask?.cancel()
        permissionTask = nil
        restart?.cancel()
        restart = nil
        endRecognition()
        // SpellAudio shares the session. Stopping input must not stop its playback.
    }

    private func beginRecognition() {
        guard wantsListening, !interrupted else { return }
        endRecognition()
        guard let recognizer, recognizer.isAvailable else {
            onStatus?("Voice is unavailable. Screen controls still work.")
            scheduleRestart(after: 4)
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord, mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth, .allowAirPlay, .mixWithOthers])
            try session.setActive(true)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw NSError(
                    domain: "XArcanaVoice", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No microphone is available."])
            }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .confirmation
            request.contextualStrings = SpellCatalog.voiceAliases.map(\.phrase)
            self.request = request
            parser = VoiceCommandParser()
            let currentGeneration = generation
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            hasTap = true
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let wordTimes =
                    result?.bestTranscription.segments.map {
                        (range: $0.substringRange, start: $0.timestamp)
                    } ?? []
                let finished = result?.isFinal == true || error != nil
                Task { @MainActor [weak self] in
                    guard let self, self.generation == currentGeneration, self.wantsListening else { return }
                    if let text {
                        for command in self.parser.consume(text, wordTimes: wordTimes) { self.onCommand?(command) }
                    }
                    if finished {
                        self.endRecognition()
                        self.scheduleRestart(after: error == nil ? 0.25 : 1.5)
                    }
                }
            }
            engine.prepare()
            try engine.start()
            onStatus?("Voice ready: \(SpellCatalog.voiceHelp).")
            // Speech tasks have a limited duration. Renew before the service cuts input.
            scheduleRestart(after: 50)
        } catch {
            endRecognition()
            onStatus?("Voice could not start. Screen controls still work.")
            scheduleRestart(after: 4)
        }
    }

    private func endRecognition() {
        generation += 1
        engine.stop()
        if hasTap {
            engine.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
        request?.endAudio()
        recognition?.cancel()
        recognition = nil
        request = nil
    }

    private func scheduleRestart(after seconds: Double) {
        restart?.cancel()
        restart = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.beginRecognition()
        }
    }

    private func observeSession() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil, queue: .main
            ) { [weak self] notification in
                let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                Task { @MainActor in
                    guard let self, let raw, let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                    self.interrupted = type == .began
                    if self.interrupted {
                        self.restart?.cancel()
                        self.endRecognition()
                    } else if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                        self.beginRecognition()
                    }
                }
            })
        observers.append(
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.endRecognition()
                    self.engine = AVAudioEngine()
                    self.beginRecognition()
                }
            })
        observers.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil, queue: .main
            ) { [weak self] notification in
                let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                guard
                    reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                        || reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue
                else { return }
                Task { @MainActor in
                    guard let self, self.wantsListening else { return }
                    self.endRecognition()
                    self.scheduleRestart(after: 0.5)
                }
            })
    }
}
