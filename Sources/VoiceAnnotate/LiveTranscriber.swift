import Foundation
import VoiceAnnotateCore

/// Audio that is still being recorded (`AudioRecorder`, or a replayed file in dev commands).
protocol LiveSampleSource: AnyObject, Sendable {
    var sampleCount: Int { get }
    func samples(from start: Int, count: Int) -> [Float]
}

/// Transcribes a recording in pieces while it is still running, cutting at pauses
/// (`ChunkPlanner`), so finishing only has to transcribe the last few seconds.
@MainActor
final class LiveTranscriber {
    private let recorder: LiveSampleSource
    private let model: String
    private let vocabulary: String
    /// Samples already handed to transcription.
    private var committed = 0
    private var output = TranscriptionOutput(words: [], segments: [])
    private var inFlight: Task<Void, Never>?
    private var failed = false
    private var timer: Timer?

    init(recorder: LiveSampleSource, model: String, vocabulary: String) {
        self.recorder = recorder
        self.model = model
        self.vocabulary = vocabulary
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        // One piece at a time; if transcription falls behind, the next piece is cut later.
        guard inFlight == nil, !failed else { return }
        let rate = AudioResult.sampleRate
        let available = recorder.sampleCount - committed
        guard Double(available) >= ChunkPlanner.minSeconds * rate else { return }
        let slice = recorder.samples(from: committed, count: Int(ChunkPlanner.maxSeconds * rate))
        guard let cut = ChunkPlanner.cutPoint(slice, sampleRate: rate) else { return }
        let offset = committed
        committed += cut
        inFlight = Task { [weak self] in
            await self?.transcribe(Array(slice[..<cut]), offset: offset)
            self?.inFlight = nil
        }
    }

    private func transcribe(_ samples: [Float], offset: Int) async {
        do {
            let out = try await Transcriber.shared.transcribe(samples, model: model, vocabulary: vocabulary)
            let t = Double(offset) / AudioResult.sampleRate
            output.words += out.words.map { Word(text: $0.text, start: $0.start + t, end: $0.end + t) }
            output.segments += out.segments.map { SpeechSegment(text: $0.text, start: $0.start + t, end: $0.end + t) }
        } catch {
            Log.transcribe.error("Live transcription failed: \(error.localizedDescription, privacy: .public)")
            failed = true
        }
    }

    /// Transcribes what is left of `samples` (the full recording) and returns the whole
    /// transcript, or nil if a piece failed (the caller then transcribes everything at once).
    func finish(samples: [Float]) async -> TranscriptionOutput? {
        timer?.invalidate()
        timer = nil
        await inFlight?.value
        guard !failed else { return nil }
        if committed < samples.count {
            let started = Date()
            let tail = Array(samples[committed...])
            await transcribe(tail, offset: committed)
            Log.transcribe.info("Finished live transcription: \(String(format: "%.1f", Double(tail.count) / AudioResult.sampleRate), privacy: .public)s tail in \(String(format: "%.2f", Date().timeIntervalSince(started)), privacy: .public)s")
        }
        return failed ? nil : output
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        inFlight?.cancel()
    }
}
