import Foundation
import CoreAudio
struct SimpleConsole { let date: Date; let message: String }
let event = Date(timeIntervalSince1970: 100)
func stat(_ offset: Double, _ rate: Double) -> CMPlayerStats {
    CMPlayerStats(sampleRate: rate, bitDepth: 24, date: event.addingTimeInterval(offset), priority: 5)
}
func check(_ stats: [CMPlayerStats], _ expected: Double?, _ label: String) {
    precondition(RateSelection.candidate(stats, near: event)?.sampleRate == expected, label)
    print("PASS: \(label)")
}
check([stat(-4, 192000)], nil, "reject stale previous-track logs")
check([stat(4, 192000)], nil, "reject late next-track preload")
check([stat(1.8, 192000), stat(-0.1, 44100)], 44100, "prefer transition log over newer prefetch")
check([stat(-0.1, 44100), stat(1.8, 192000)], 44100, "selection independent of log ordering")
check([stat(0.8, 96000)], 96000, "accept delayed decoder log")
check([], nil, "missing logs do not invent fallback")
check([stat(0, 0)], nil, "reject invalid sample rate")
check([stat(0, .infinity), stat(0, .nan)], nil, "reject non-finite sample rates")
check([stat(0.5, 96000), stat(-0.5, 44100)], 44100, "tie prefers earlier log")

func entry(_ text: String, _ offset: Double = 0) -> SimpleConsole {
    SimpleConsole(date: event.addingTimeInterval(offset), message: text)
}
let prefix = "ACAppleLosslessDecoder.cpp Input format: "
let complete = entry(prefix + "2 ch, 96000 Hz, from 24-bit source")
let parsed = CMPlayerParser.parseCoreAudioConsoleLogs([complete])
precondition(parsed.count == 1 && parsed[0].sampleRate == 96000 && parsed[0].bitDepth == 24)
print("PASS: complete decoder line")
let incomplete = CMPlayerParser.parseCoreAudioConsoleLogs([
 entry(prefix + "2 ch, 192000 Hz"), entry(prefix + "from 16-bit source")])
precondition(incomplete.isEmpty)
print("PASS: never combine fields from different log entries")
let multiple = CMPlayerParser.parseCoreAudioConsoleLogs([
 entry(prefix + "2 ch, 192000 Hz, from 24-bit source", 1.8),
 entry(prefix + "2 ch, 44100 Hz, from 16-bit source", -0.1)])
precondition(multiple.count == 2)
precondition(RateSelection.candidate(multiple, near: event)?.sampleRate == 44100)
print("PASS: parse all candidates and reject newer prefetch")

let invalid = CMPlayerParser.parseCoreAudioConsoleLogs([
    entry(prefix + "2 ch, inf Hz, from 24-bit source"),
    entry(prefix + "2 ch, 96000 Hz, from 0-bit source"),
    entry(prefix + "2 ch, 96000 Hz, from 999-bit source")
])
precondition(invalid.isEmpty)
print("PASS: reject malformed decoder formats")

precondition(RateSelection.sampleRate(
    for: 176400, supported: [44100, 48000, 96000], preferMultiples: true
) == 44100)
precondition(RateSelection.sampleRate(
    for: 176400, supported: [44100, 48000, 96000], preferMultiples: false
) == 96000)
precondition(RateSelection.sampleRate(
    for: 192000, supported: [.nan, -1], preferMultiples: true
) == nil)
print("PASS: preserve sample-rate-family fallback without invalid device rates")

var pcm = AudioStreamBasicDescription()
pcm.mFormatID = kAudioFormatLinearPCM
pcm.mBitsPerChannel = 24
let ranged = AudioStreamRangedDescription(
    mFormat: pcm, mSampleRateRange: AudioValueRange(mMinimum: 44100, mMaximum: 192000)
)
let format = RateSelection.physicalFormat(at: 96000, bitDepth: 24, supported: [ranged])
precondition(format?.mSampleRate == 96000 && format?.mBitsPerChannel == 24)
precondition(RateSelection.physicalFormat(at: 384000, bitDepth: 24, supported: [ranged]) == nil)
print("PASS: select physical formats from advertised rate ranges")

var playback = PlaybackState()
func observe(
    _ track: String = "first",
    music: Bool = true,
    playing: Bool? = true,
    position: Double? = 0,
    at offset: Double? = 0
) -> PlaybackState.Change {
    playback.update(
        trackID: track, isMusicApp: music, isPlaying: playing,
        elapsedTime: position, timestamp: offset.map { event.addingTimeInterval($0) }
    )
}
precondition(observe() == .trackChanged)
precondition(observe(position: 0, at: 0) == .none)
precondition(observe(position: 0, at: 0) == .none)
precondition(observe(playing: nil, position: 0, at: 0) == .none)
precondition(observe(position: 10, at: 10) == .none)
print("PASS: metadata and stale MediaRemote position updates never trigger detection")

precondition(observe(position: 25, at: 11) == .seeked)
precondition(observe(position: 1, at: 12) == .seeked)
precondition(observe(position: 0, at: 0) == .none)
precondition(observe(position: 2, at: 13) == .none)
precondition(observe(position: 2, at: nil) == .none)
print("PASS: detect real seeks without trusting old or missing position timestamps")

precondition(observe(playing: false, position: 2, at: 13) == .stopped)
precondition(!playback.isPlaying)
precondition(observe(position: 2, at: 20) == .resumed)
precondition(observe("second", position: 0, at: 21) == .trackChanged)
precondition(observe("browser", music: false) == .stopped)
precondition(!playback.isPlaying)
precondition(observe("second", position: 2, at: 23) == .trackChanged)
print("PASS: pause, resume, track changes and non-Music playback gate detection")

let identity = TrackIdentity(title: "Current", artist: "Artist", album: "Album")
let metadata = MusicTrackSnapshot(track: identity, sampleRate: 192000, isPlaying: true)
let request = MetadataRecoveryRequest(generation: 7, track: identity)
precondition(request.accepts(metadata, generation: 7, track: identity, hasDecoderFormat: false))
precondition(!request.accepts(metadata, generation: 8, track: identity, hasDecoderFormat: false))
precondition(!request.accepts(metadata, generation: 7, track: identity, hasDecoderFormat: true))
precondition(!request.accepts(
    MusicTrackSnapshot(track: identity, sampleRate: 192000, isPlaying: false),
    generation: 7, track: identity, hasDecoderFormat: false
))
print("PASS: startup metadata is accepted only for active, current detection without a decoder result")

let otherRecording = TrackIdentity(title: "Current", artist: "Another Artist", album: "Album")
precondition(!request.accepts(
    MusicTrackSnapshot(track: otherRecording, sampleRate: 96000, isPlaying: true),
    generation: 7, track: identity, hasDecoderFormat: false
))
precondition(!request.accepts(metadata, generation: 7, track: otherRecording, hasDecoderFormat: false))
precondition(!request.accepts(
    MusicTrackSnapshot(track: identity, sampleRate: .nan, isPlaying: true),
    generation: 7, track: identity, hasDecoderFormat: false
))
print("PASS: same-name recordings, changed tracks and invalid metadata cannot change the current format")

let metadataFormat = SourceAudioFormat(metadata: metadata)
precondition(metadataFormat.bitDepth == nil)
precondition(metadataFormat.outputWarning(sampleRate: 192000, bitDepth: 16) == nil)
let decodedFormat = SourceAudioFormat(decoder: stat(0, 96000))
precondition(decodedFormat.outputWarning(sampleRate: 96000, bitDepth: 16) != nil)
precondition(decodedFormat.outputWarning(sampleRate: 96000, bitDepth: 24) == nil)
precondition(decodedFormat.outputWarning(sampleRate: 48000, bitDepth: 24) != nil)
print("PASS: source/output reductions are visible without inventing metadata bit depth")

var mixedPlayback = PlaybackState()
for (index, rate) in [44100.0, 96000, 192000, 44100].enumerated() {
    let trackID = "mixed-\(index)"
    let time = event.addingTimeInterval(Double(index) * 30)
    precondition(mixedPlayback.update(
        trackID: trackID, isMusicApp: true, isPlaying: true,
        elapsedTime: 0, timestamp: time
    ) == .trackChanged)
    let candidates = [
        CMPlayerStats(sampleRate: 192000, bitDepth: 24, date: time.addingTimeInterval(-5), priority: 5),
        CMPlayerStats(sampleRate: rate, bitDepth: 24, date: time, priority: 5),
        CMPlayerStats(sampleRate: 96000, bitDepth: 24, date: time.addingTimeInterval(4), priority: 5)
    ]
    precondition(RateSelection.candidate(candidates, near: time)?.sampleRate == rate)
    precondition(mixedPlayback.update(
        trackID: trackID, isMusicApp: true, isPlaying: true,
        elapsedTime: 0, timestamp: time
    ) == .none)
}
print("PASS: mixed-rate transitions ignore old formats, late preloads and same-track metadata updates")
