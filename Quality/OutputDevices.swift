//
//  OutputDevices.swift
//  Quality
//
//  Created by Vincent Neo on 20/4/22.
//

import Combine
import CoreAudio
import Foundation
import MediaRemoteAdapter
import OSLog
import SimplyCoreAudio

class OutputDevices: ObservableObject {
    @Published var selectedOutputDevice: AudioDevice? {
        didSet {
            if oldValue?.id != selectedOutputDevice?.id {
                outputDeviceDidChange()
            }
        }
    }
    @Published var defaultOutputDevice: AudioDevice?
    @Published var outputDevices = [AudioDevice]()
    @Published var currentSampleRate: Float64?
    @Published var currentBitDepth: Int?
    @Published var enableBitDepthDetection = Defaults.shared.userPreferBitDepthDetection
    @Published private(set) var statusMessage: String? = "Waiting for Apple Music playback."
    @Published private(set) var sourceFormat: SourceAudioFormat?
    @Published private(set) var isMusicPlaying = false
    @Published private(set) var isReadingMusic = false

    private let coreAudio = SimplyCoreAudio()
    private let processQueue = DispatchQueue(label: "sampleRateDetection", qos: .utility)
    private let metadataQueue = DispatchQueue(label: "musicMetadata", qos: .utility)
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LosslessSwitcher", category: "Audio")
    private var cancellables = Set<AnyCancellable>()
    private var playback = PlaybackState()
    private var currentTrack: MediaTrack?
    private var metadataRequest: MetadataRecoveryRequest?
    private var detectionEvent: Date?
    private var detectionGeneration = 0
    private var previousSampleRate: Float64?
    private var previousBitDepth: Int?

    var outputFormatDescription: String {
        SourceAudioFormat.describe(sampleRate: currentSampleRate.map { $0 * 1000 }, bitDepth: currentBitDepth)
    }

    var sourceOutputWarning: String? {
        sourceFormat?.outputWarning(sampleRate: currentSampleRate.map { $0 * 1000 }, bitDepth: currentBitDepth)
    }

    init() {
        outputDevices = coreAudio.allOutputDevices
        defaultOutputDevice = coreAudio.defaultOutputDevice
        selectedOutputDevice = Defaults.shared.selectedDeviceUID.flatMap { uid in
            outputDevices.first { $0.uid == uid }
        }
        getDeviceSampleRate()

        NotificationCenter.default.publisher(for: .deviceListChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.outputDevices = self.coreAudio.allOutputDevices
                self.selectedOutputDevice = Defaults.shared.selectedDeviceUID.flatMap { uid in
                    self.outputDevices.first { $0.uid == uid }
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .defaultOutputDeviceChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.defaultOutputDevice = self.coreAudio.defaultOutputDevice
                if self.selectedOutputDevice == nil {
                    self.outputDeviceDidChange()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .deviceNominalSampleRateDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let device = notification.object as? AudioDevice,
                      device.id == (self.selectedOutputDevice ?? self.defaultOutputDevice)?.id else { return }
                self.getDeviceSampleRate()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .streamPhysicalFormatDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let stream = notification.object as? AudioStream,
                      let device = self.selectedOutputDevice ?? self.defaultOutputDevice,
                      device.streams(scope: .output)?
                        .contains(where: { $0.id == stream.id }) == true else { return }
                self.getDeviceSampleRate()
            }
            .store(in: &cancellables)

        Defaults.shared.$userPreferBitDepthDetection
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                guard let self else { return }
                self.enableBitDepthDetection = newValue
                self.outputDeviceDidChange()
            }
            .store(in: &cancellables)

        Defaults.shared.$userPreferSampleRateMultiples
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.outputDeviceDidChange() }
            .store(in: &cancellables)
    }

    func stopDetection() {
        detectionGeneration += 1
    }

    func reportError(_ message: String) {
        logger.error("\(message, privacy: .public)")
        statusMessage = message
    }

    func getDeviceSampleRate() {
        guard let device = selectedOutputDevice ?? defaultOutputDevice,
              let sampleRate = device.nominalSampleRate, sampleRate.isFinite, sampleRate > 0 else {
            currentSampleRate = nil
            currentBitDepth = nil
            previousSampleRate = nil
            previousBitDepth = nil
            reportError("Cannot read the current audio output format.")
            return
        }
        updateSampleRate(
            sampleRate,
            bitDepth: device.streams(scope: .output)?.first?.physicalFormat.flatMap {
                $0.mBitsPerChannel > 0 ? Int($0.mBitsPerChannel) : nil
            }
        )
    }

    private func outputDeviceDidChange() {
        stopDetection()
        getDeviceSampleRate()
        guard playback.isPlaying else { return }
        if let sourceFormat {
            apply(sourceFormat)
        } else if let detectionEvent {
            beginDetection(at: detectionEvent)
        }
    }

    private func beginDetection(at event: Date) {
        stopDetection()
        detectionEvent = event
        if sourceFormat == nil {
            statusMessage = "Detecting Music's lossless format..."
        }
        let generation = detectionGeneration
        let delays = [0.35, 1.0, 2.0, 3.0]
        for (index, delay) in delays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.detectionGeneration == generation else { return }
                self.processQueue.async { [weak self] in
                    guard let self else { return }
                    do {
                        let entries = try Console.getRecentEntries(
                            type: .coreAudio, since: event.addingTimeInterval(-1.5)
                        )
                        let stats = CMPlayerParser.parseCoreAudioConsoleLogs(entries)
                        let candidate = RateSelection.candidate(stats, near: event)
                        DispatchQueue.main.async { [weak self] in
                            guard let self, self.detectionGeneration == generation else { return }
                            if let candidate {
                                let format = SourceAudioFormat(decoder: candidate)
                                self.sourceFormat = format
                                self.apply(format)
                            } else if index == delays.count - 1, self.sourceFormat == nil {
                                self.logger.notice("No decoder format matched the playback event.")
                                self.recoverFromMusic(allowAuthorizationPrompt: false)
                            }
                        }
                    } catch {
                        let message = "Cannot read Music's audio logs: \(error.localizedDescription)"
                        DispatchQueue.main.async { [weak self] in
                            guard let self, self.detectionGeneration == generation else { return }
                            self.reportError(message)
                            if index == delays.count - 1, self.sourceFormat == nil {
                                self.recoverFromMusic(allowAuthorizationPrompt: false)
                            }
                        }
                    }
                }
            }
        }
    }

    func readCurrentTrackFromMusic() {
        guard playback.isPlaying, currentTrack?.isMusicApp == true else {
            reportError("Play a track in Music before reading its format.")
            return
        }
        guard !isReadingMusic else { return }
        stopDetection()
        sourceFormat = nil
        recoverFromMusic(allowAuthorizationPrompt: true)
    }

    private func recoverFromMusic(allowAuthorizationPrompt: Bool) {
        guard !isReadingMusic, playback.isPlaying, let track = currentTrack, track.isMusicApp else { return }
        let request = MetadataRecoveryRequest(generation: detectionGeneration, track: track.identity)
        metadataRequest = request
        isReadingMusic = true
        statusMessage = allowAuthorizationPrompt ? "Waiting for Music access..." : "Reading the current Music track..."
        metadataQueue.async { [weak self] in
            let result = Result { try MusicMetadataReader.readCurrentTrack(allowAuthorizationPrompt: allowAuthorizationPrompt) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.metadataRequest == request else { return }
                self.metadataRequest = nil
                self.isReadingMusic = false
                guard self.detectionGeneration == request.generation,
                      self.currentTrack?.identity == request.track, self.playback.isPlaying else {
                    self.logger.debug("Discarded an obsolete Music metadata request.")
                    if self.sourceFormat == nil, self.playback.isPlaying {
                        self.statusMessage = "Playback changed while reading Music. Read the current track again."
                    }
                    return
                }
                if self.sourceFormat?.origin == .decoder { return }
                switch result {
                case .success(let snapshot):
                    guard request.accepts(
                        snapshot, generation: self.detectionGeneration,
                        track: self.currentTrack?.identity, hasDecoderFormat: self.sourceFormat?.origin == .decoder
                    ) else {
                        self.reportError("Music's current track does not match the playback observation. Try again.")
                        return
                    }
                    let format = SourceAudioFormat(metadata: snapshot)
                    self.sourceFormat = format
                    self.apply(format)
                case .failure(let error):
                    self.reportError(error.localizedDescription)
                }
            }
        }
    }

    private func apply(_ format: SourceAudioFormat) {
        guard let device = selectedOutputDevice ?? defaultOutputDevice else {
            reportError("No audio output device is available.")
            return
        }
        guard let rate = RateSelection.sampleRate(
            for: format.sampleRate,
            supported: device.nominalSampleRates ?? [],
            preferMultiples: Defaults.shared.userPreferSampleRateMultiples
        ) else {
            reportError("Cannot read supported sample rates for \(device.name).")
            return
        }

        if enableBitDepthDetection, let sourceDepth = format.bitDepth {
            guard let stream = device.streams(scope: .output)?.first,
                  var format = RateSelection.physicalFormat(
                    at: rate, bitDepth: sourceDepth, supported: stream.availablePhysicalFormats ?? []
                  ) else {
                reportError("No matching physical format for \(device.name). Disable Bit Depth Switching.")
                return
            }
            if stream.physicalFormat != format {
                var address = AudioObjectPropertyAddress(
                    mSelector: kAudioStreamPropertyPhysicalFormat,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                let status = AudioObjectSetPropertyData(
                    stream.id, &address, 0, nil,
                    UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &format
                )
                guard status == noErr else {
                    reportError("Cannot set the audio format for \(device.name) (CoreAudio \(status)).")
                    return
                }
            }
        } else if device.nominalSampleRate != rate, !device.setNominalSampleRate(rate) {
            reportError("Cannot set \(device.name) to \(Int(rate)) Hz.")
            return
        }
        readBack(device: device, expectedRate: rate, generation: detectionGeneration)
    }

    private func readBack(device: AudioDevice, expectedRate: Double, generation: Int, attempt: Int = 0) {
        guard detectionGeneration == generation,
              (selectedOutputDevice ?? defaultOutputDevice)?.id == device.id else { return }
        getDeviceSampleRate()
        if device.nominalSampleRate == expectedRate {
            statusMessage = nil
        } else if attempt < 3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.readBack(device: device, expectedRate: expectedRate, generation: generation, attempt: attempt + 1)
            }
        } else {
            reportError("\(device.name) did not accept \(Int(expectedRate)) Hz. The displayed rate is the hardware readback.")
        }
    }

    func updateSampleRate(_ sampleRate: Float64, bitDepth: Int?) {
        let changed = previousSampleRate != sampleRate ||
            (enableBitDepthDetection && previousBitDepth != bitDepth)
        previousSampleRate = sampleRate
        previousBitDepth = bitDepth
        currentSampleRate = sampleRate / 1000
        currentBitDepth = bitDepth
        if enableBitDepthDetection, let bitDepth {
            AppDelegate.instance?.statusItemTitle = String(format: "%.1f kHz / %d bit", sampleRate / 1000, bitDepth)
        } else {
            AppDelegate.instance?.statusItemTitle = String(format: "%.1f kHz", sampleRate / 1000)
        }
        if changed {
            runUserScript(sampleRate, bitDepth: bitDepth)
        }
    }

    private func runUserScript(_ sampleRate: Float64, bitDepth: Int?) {
        guard let scriptPath = Defaults.shared.shellScriptPath else { return }
        var arguments = [String(Int(sampleRate))]
        if let bitDepth {
            arguments.append(String(bitDepth))
        }
        Task { @MainActor in
            do {
                let task = try NSUserUnixTask(url: URL(fileURLWithPath: scriptPath))
                try await task.execute(withArguments: arguments)
            } catch {
                self.reportError("Cannot run the selected script: \(error.localizedDescription)")
            }
        }
    }

    func trackDidChange(_ newTrack: TrackInfo, observedAt: Date) {
        let track = MediaTrack(trackInfo: newTrack)
        let payload = newTrack.payload
        let change = playback.update(
            trackID: track.id ?? "",
            isMusicApp: track.isMusicApp,
            isPlaying: payload.isPlaying,
            elapsedTime: payload.elapsedTimeMicros.map { $0 / 1_000_000 },
            timestamp: payload.timestampEpochMicros.map { Date(timeIntervalSince1970: $0 / 1_000_000) }
        )
        if currentTrack != track {
            sourceFormat = nil
            detectionEvent = nil
        }
        currentTrack = track.isMusicApp ? track : nil
        isMusicPlaying = playback.isPlaying

        switch change {
        case .none:
            break
        case .stopped:
            stopDetection()
            statusMessage = track.isMusicApp ? "Apple Music is paused." : "Waiting for Apple Music playback."
        case .resumed:
            beginDetection(at: observedAt)
            if let sourceFormat {
                apply(sourceFormat)
            }
        case .trackChanged, .seeked:
            beginDetection(at: observedAt)
        }
    }
}
