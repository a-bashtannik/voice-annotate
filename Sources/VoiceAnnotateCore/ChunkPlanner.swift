import Accelerate
import Foundation

/// Decides where to cut a growing recording so finished pieces can be transcribed while
/// recording continues. Cuts land in the quietest stretch (a pause between words), so no
/// word is split between two pieces.
public enum ChunkPlanner {
    /// A piece is at least this long, so Whisper gets enough context.
    public static let minSeconds = 15.0
    /// Without a pause, a piece is cut at its quietest point by this length (Whisper's window).
    public static let maxSeconds = 30.0
    static let windowSeconds = 0.3
    static let hopSeconds = 0.05

    /// Offset (in samples) at which to cut `samples`, or nil to wait for more audio.
    public static func cutPoint(_ samples: [Float], sampleRate: Double, minSeconds: Double = minSeconds, maxSeconds: Double = maxSeconds) -> Int? {
        let hop = max(1, Int(sampleRate * hopSeconds))
        let windowHops = max(1, Int((windowSeconds / hopSeconds).rounded()))
        let n = samples.count
        let firstHop = Int(minSeconds * sampleRate) / hop
        let lastHop = min(n, Int(maxSeconds * sampleRate)) / hop
        guard lastHop - firstHop >= windowHops else { return nil }

        // Mean square per hop over the search range, then the quietest window of hops.
        var energy = [Float](repeating: 0, count: lastHop - firstHop)
        var overall: Float = 0
        samples.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            for i in energy.indices {
                vDSP_measqv(base + (firstHop + i) * hop, 1, &energy[i], vDSP_Length(hop))
            }
            vDSP_measqv(base, 1, &overall, vDSP_Length(n))
        }
        var sum = energy[0..<windowHops].reduce(0, +)
        var best = sum, bestStart = 0
        if energy.count > windowHops {
            for start in 1...(energy.count - windowHops) {
                sum += energy[start + windowHops - 1] - energy[start - 1]
                if sum < best {
                    best = sum
                    bestStart = start
                }
            }
        }
        let quiet = sqrt(max(0, best) / Float(windowHops))
        // A pause is quiet relative to the speech around it (mic gain varies a lot).
        let threshold = max(0.003, 0.3 * sqrt(overall))
        guard quiet <= threshold || n >= Int(maxSeconds * sampleRate) else { return nil }
        return (firstHop + bestStart + windowHops / 2) * hop
    }
}
