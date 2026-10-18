import Foundation

struct TrackIdentity: Equatable {
    let title: String
    let artist: String
    let album: String
}

struct MusicTrackSnapshot {
    let track: TrackIdentity
    let sampleRate: Double
    let isPlaying: Bool
}

struct MetadataRecoveryRequest: Equatable {
    let generation: Int
    let track: TrackIdentity

    func accepts(
        _ snapshot: MusicTrackSnapshot,
        generation: Int,
        track: TrackIdentity?,
        hasDecoderFormat: Bool
    ) -> Bool {
        self.generation == generation && self.track == track &&
            snapshot.track == self.track && snapshot.isPlaying &&
            snapshot.sampleRate.isFinite && snapshot.sampleRate > 0 && !hasDecoderFormat
    }
}

struct SourceAudioFormat: Equatable {
    enum Origin: Equatable {
        case decoder
        case musicMetadata
    }

    let sampleRate: Double
    let bitDepth: Int?
    let origin: Origin

    init(decoder stat: CMPlayerStats) {
        sampleRate = stat.sampleRate
        bitDepth = stat.bitDepth
        origin = .decoder
    }

    init(metadata snapshot: MusicTrackSnapshot) {
        sampleRate = snapshot.sampleRate
        bitDepth = nil
        origin = .musicMetadata
    }

    static func describe(sampleRate: Double?, bitDepth: Int?) -> String {
        guard let sampleRate else { return "Unknown" }
        let depth = bitDepth.map(String.init) ?? "?"
        return String(format: "%.1f kHz / %@ bit", sampleRate / 1000, depth)
    }

    var description: String {
        Self.describe(sampleRate: sampleRate, bitDepth: bitDepth)
    }

    func outputWarning(sampleRate: Double?, bitDepth: Int?) -> String? {
        var warnings: [String] = []
        if let sampleRate, sampleRate != self.sampleRate {
            warnings.append("The output sample rate differs from the source.")
        }
        if let sourceDepth = self.bitDepth, let bitDepth, bitDepth < sourceDepth {
            warnings.append("The output bit depth is lower than the source.")
        }
        return warnings.isEmpty ? nil : warnings.joined(separator: " ")
    }
}
