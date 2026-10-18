import Foundation

struct PlaybackState {
    enum Change: Equatable {
        case none
        case stopped
        case trackChanged
        case resumed
        case seeked
    }

    private(set) var trackID: String?
    private(set) var isPlaying = false
    private var position: TimeInterval?
    private var positionDate: Date?

    mutating func update(
        trackID: String,
        isMusicApp: Bool,
        isPlaying: Bool?,
        elapsedTime: TimeInterval?,
        timestamp: Date?
    ) -> Change {
        guard isMusicApp else {
            self = PlaybackState()
            return .stopped
        }

        let sameTrack = self.trackID == trackID
        let wasPlaying = self.isPlaying
        let playing = isPlaying ?? (sameTrack && wasPlaying)
        var didSeek = false

        if sameTrack, wasPlaying, playing,
           let elapsedTime, elapsedTime.isFinite, elapsedTime >= 0,
           let timestamp, let position, let positionDate,
           timestamp > positionDate {
            // MediaRemote repeats the position and its original timestamp in
            // metadata updates. Callback arrival time is not a position timestamp.
            didSeek = abs(elapsedTime - position - timestamp.timeIntervalSince(positionDate)) > 1.0
        }

        if !sameTrack {
            position = nil
            positionDate = nil
        }
        if let elapsedTime, elapsedTime.isFinite, elapsedTime >= 0,
           let timestamp, positionDate.map({ timestamp >= $0 }) ?? true {
            position = elapsedTime
            positionDate = timestamp
        }
        self.trackID = trackID
        self.isPlaying = playing

        guard playing else { return .stopped }
        if !sameTrack { return .trackChanged }
        if !wasPlaying { return .resumed }
        return didSeek ? .seeked : .none
    }
}
