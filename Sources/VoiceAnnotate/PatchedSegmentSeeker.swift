import CoreML
import Foundation
import WhisperKit

/// WhisperKit's `SegmentSeeker` with a fix (WhisperKit 1.1.1).
///
/// Word timings with a prompt (the custom vocabulary): alignment rows are indexed from the
/// start of the decoder sequence, which begins with `<|startofprev|>` and the prompt, but the
/// tokens they are matched with start at `<|startoftranscript|>`. Every word then reads the
/// timing of a row `prompt + 1` too early, moving mark references onto earlier words.
/// Dropping those rows first lines them up again.
struct PatchedSegmentSeeker: SegmentSeeking {
    private let seeker = SegmentSeeker()

    func findSeekPointAndSegments(
        decodingResult: DecodingResult,
        options: DecodingOptions,
        allSegmentsCount: Int,
        currentSeek seek: Int,
        segmentSize: Int,
        sampleRate: Int,
        timeToken: Int,
        specialToken: Int,
        tokenizer: WhisperTokenizer
    ) -> (Int, [TranscriptionSegment]?) {
        seeker.findSeekPointAndSegments(
            decodingResult: decodingResult, options: options, allSegmentsCount: allSegmentsCount,
            currentSeek: seek, segmentSize: segmentSize, sampleRate: sampleRate,
            timeToken: timeToken, specialToken: specialToken, tokenizer: tokenizer
        )
    }

    func addWordTimestamps(
        segments: [TranscriptionSegment],
        alignmentWeights: MLMultiArray,
        tokenizer: WhisperTokenizer,
        seek: Int,
        segmentSize: Int,
        prependPunctuations: String,
        appendPunctuations: String,
        lastSpeechTimestamp: Float,
        options: DecodingOptions,
        timings: TranscriptionTimings
    ) throws -> [TranscriptionSegment]? {
        let rows = Self.promptRows(options: options, tokenizer: tokenizer)
        return try seeker.addWordTimestamps(
            segments: segments,
            alignmentWeights: rows == 0 ? alignmentWeights : Self.dropRows(rows, from: alignmentWeights),
            tokenizer: tokenizer, seek: seek, segmentSize: segmentSize,
            prependPunctuations: prependPunctuations, appendPunctuations: appendPunctuations,
            lastSpeechTimestamp: lastSpeechTimestamp, options: options, timings: timings
        )
    }

    /// Rows taken by `<|startofprev|>` and the prompt, trimmed like `prefillDecoderInputs` does.
    private static func promptRows(options: DecodingOptions, tokenizer: WhisperTokenizer) -> Int {
        let prompt = (options.promptTokens ?? [])
            .suffix(Constants.maxTokenContext / 2 - 1)
            .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        return prompt.isEmpty ? 0 : prompt.count + 1
    }

    /// Copies by row stride: Core ML pads rows, 1500 columns are stored 1504 apart.
    private static func dropRows(_ count: Int, from weights: MLMultiArray) throws -> MLMultiArray {
        let rows = weights.shape[0].intValue
        let columns = weights.shape[1].intValue
        let shifted = try MLMultiArray(shape: weights.shape, dataType: weights.dataType, initialValue: FloatType(0))
        let sourceStride = weights.strides[0].intValue
        let targetStride = shifted.strides[0].intValue
        let scalarSize = MemoryLayout<FloatType>.stride
        weights.withUnsafeBytes { source in
            shifted.withUnsafeMutableBytes { target, _ in
                for row in 0..<max(0, rows - count) {
                    memcpy(
                        target.baseAddress! + row * targetStride * scalarSize,
                        source.baseAddress! + (row + count) * sourceStride * scalarSize,
                        columns * scalarSize
                    )
                }
            }
        }
        return shifted
    }
}
