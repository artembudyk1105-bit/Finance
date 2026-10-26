import Foundation
import Speech
import AVFoundation

/// Распознавание речи на устройстве (без интернета, если язык поддерживается) + уровень громкости для волны
@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var level: Float = 0
    @Published var isRecording = false

    /// Автоостановка после паузы — для запуска с кнопки действия, когда кнопку не удерживают
    var autoStopOnSilence = false
    var onFinish: ((String) -> Void)?

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceWork: DispatchWorkItem?
    private var stopping = false

    enum VoiceError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Распознавание речи недоступно" }
    }

    static func requestPermissions() async -> Bool {
        let speech: Bool = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    func start(locale: String) throws {
        cleanup()
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable else {
            throw VoiceError.unavailable
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }

        let engine = AVAudioEngine()
        Self.installTap(on: engine.inputNode, request: req) { [weak self] lvl in
            Task { @MainActor in self?.level = lvl }
        }
        engine.prepare()
        try engine.start()

        transcript = ""
        level = 0
        stopping = false
        isRecording = true
        self.engine = engine
        self.request = req
        task = Self.recognize(recognizer, req) { [weak self] text, done in
            Task { @MainActor in self?.handle(text: text, done: done) }
        }
        if autoStopOnSilence { armSilence(seconds: 6) }
    }

    /// Пользователь отпустил кнопку: дожидаемся финального результата
    func stop() {
        guard isRecording, !stopping else { return }
        stopping = true
        stopAudio()
        request?.endAudio()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.finish() }
    }

    func cancel() {
        onFinish = nil
        finish()
    }

    private func handle(text: String?, done: Bool) {
        guard isRecording else { return }
        if let text, !text.isEmpty {
            transcript = text
            if autoStopOnSilence && !stopping { armSilence(seconds: 1.6) }
        }
        if done { finish() }
    }

    private func armSilence(seconds: Double) {
        silenceWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.stop() }
        silenceWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    private func finish() {
        guard isRecording else { return }
        isRecording = false
        let text = transcript
        let cb = onFinish
        onFinish = nil
        cleanup()
        cb?(text)
    }

    private func stopAudio() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning { engine.stop() }
        }
        engine = nil
    }

    private func cleanup() {
        silenceWork?.cancel()
        silenceWork = nil
        stopAudio()
        task?.cancel()
        task = nil
        request = nil
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Колбэки звука и распознавания приходят не на главном потоке — держим их вне MainActor
    nonisolated private static func installTap(on input: AVAudioInputNode, request: SFSpeechAudioBufferRecognitionRequest,
                                               level: @escaping @Sendable (Float) -> Void) {
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            level(rms(buffer))
        }
    }

    nonisolated private static func recognize(_ recognizer: SFSpeechRecognizer, _ request: SFSpeechAudioBufferRecognitionRequest,
                                              update: @escaping @Sendable (String?, Bool) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            update(result?.bestTranscription.formattedString, error != nil || (result?.isFinal ?? false))
        }
    }

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let ch = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { sum += ch[i] * ch[i] }
        return min(1, sqrt(sum / Float(n)) * 14)
    }
}
