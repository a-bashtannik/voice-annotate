import AVFoundation
import Accelerate
import Foundation

struct AudioResult {
    /// 16 kHz mono float samples.
    var samples: [Float]
    /// Host time (seconds) of the first sample, if any audio arrived.
    var firstSampleHostTime: Double?

    static let sampleRate: Double = 16_000

    var duration: Double { Double(samples.count) / Self.sampleRate }
}

/// Records the default input device into a 16 kHz mono buffer (WhisperKit's input format).
final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioResult.sampleRate, channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var firstHostTime: Double?
    private var running = false

    /// Called on the main queue with the current RMS level (0…1, roughly perceptual).
    var onLevel: (@MainActor (Float) -> Void)?

    func start() throws {
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw AppError("No microphone input available")
        }
        guard let converter = AVAudioConverter(from: inFormat, to: targetFormat) else {
            throw AppError("Unsupported microphone format")
        }
        self.converter = converter
        lock.withLock {
            samples = []
            samples.reserveCapacity(Int(AudioResult.sampleRate) * 120)
            firstHostTime = nil
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, time in
            self?.handle(buffer, time: time)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        running = true
    }

    private func handle(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        lock.withLock {
            if firstHostTime == nil {
                firstHostTime = time.isHostTimeValid ? AVAudioTime.seconds(forHostTime: time.hostTime) : HostClock.now()
            }
        }
        guard let converter, buffer.frameLength > 0 else { return }
        let ratio = AudioResult.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64)
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let channel = out.floatChannelData, out.frameLength > 0 else { return }
        let n = Int(out.frameLength)
        let ptr = UnsafeBufferPointer(start: channel[0], count: n)
        var meanSquare: Float = 0
        vDSP_measqv(channel[0], 1, &meanSquare, vDSP_Length(n))
        lock.withLock { samples.append(contentsOf: ptr) }

        let rms = sqrt(meanSquare)
        let db = 20 * log10(max(rms, 1e-6))
        let level = max(0, min(1, (db + 55) / 45))
        if let onLevel {
            DispatchQueue.main.async { MainActor.assumeIsolated { onLevel(level) } }
        }
    }

    func stop() -> AudioResult {
        if running {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            running = false
        }
        return lock.withLock { AudioResult(samples: samples, firstSampleHostTime: firstHostTime) }
    }

    /// Writes samples as AAC .m4a.
    static func writeM4A(_ samples: [Float], to url: URL) throws {
        guard !samples.isEmpty else { return }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioResult.sampleRate, channels: 1, interleaved: false)!
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: AudioResult.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 48_000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let chunk = Int(AudioResult.sampleRate) * 10
        var offset = 0
        while offset < samples.count {
            let n = min(chunk, samples.count - offset)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)) else { break }
            buffer.frameLength = AVAudioFrameCount(n)
            samples.withUnsafeBufferPointer { src in
                buffer.floatChannelData![0].update(from: src.baseAddress! + offset, count: n)
            }
            try file.write(from: buffer)
            offset += n
        }
    }

    /// Loads any audio file as 16 kHz mono float samples.
    static func loadSamples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw AppError("Could not allocate audio buffer")
        }
        try file.read(into: inBuffer)
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioResult.sampleRate, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: inFormat, to: target) else { throw AppError("Unsupported audio format") }
        let capacity = AVAudioFrameCount(Double(inBuffer.frameLength) * AudioResult.sampleRate / inFormat.sampleRate + 1024)
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { throw AppError("Could not allocate audio buffer") }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return inBuffer
        }
        if status == .error { throw error ?? AppError("Audio conversion failed") }
        return Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
    }

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var ms: Float = 0
        vDSP_measqv(samples, 1, &ms, vDSP_Length(samples.count))
        return sqrt(ms)
    }
}
