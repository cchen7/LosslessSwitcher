//
//  MediaRemoteController.swift
//  LosslessSwitcher
//
//  Created by Vincent Neo on 1/5/22.
//

import Cocoa
import MediaRemoteAdapter
import OSLog

class MediaRemoteController {
    private var controller: MediaController?
    private weak var outputDevices: OutputDevices?
    private var restartWorkItem: DispatchWorkItem?
    private var restartAttempts = 0
    private var stopped = false
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LosslessSwitcher", category: "MediaRemote")

    init(outputDevices: OutputDevices) {
        self.outputDevices = outputDevices
        startListening()
    }

    private func startListening() {
        let controller = MediaController()
        self.controller = controller
        controller.onTrackInfoReceived = { [weak self] trackInfo in
            let observedAt = Date()
            self?.restartAttempts = 0
            self?.outputDevices?.trackDidChange(trackInfo, observedAt: observedAt)
        }
        controller.onDecodingError = { [weak self] error, _ in
            self?.outputDevices?.reportError("Cannot decode playback information: \(error.localizedDescription)")
        }
        controller.onListenerTerminated = { [weak self] in
            guard let self, !self.stopped else { return }
            self.controller?.onListenerTerminated = nil
            self.controller?.stopListening()
            self.controller = nil
            self.outputDevices?.stopDetection()
            self.restartAttempts += 1
            guard self.restartAttempts <= 3 else {
                self.outputDevices?.reportError("The Music listener stopped repeatedly. Quit and reopen LosslessSwitcher.")
                return
            }
            self.logger.error("The Music listener stopped; restarting (attempt \(self.restartAttempts)).")
            let workItem = DispatchWorkItem { [weak self] in self?.startListening() }
            self.restartWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(self.restartAttempts), execute: workItem)
        }
        controller.startListening()
    }

    func stopListening() {
        stopped = true
        restartWorkItem?.cancel()
        controller?.onListenerTerminated = nil
        controller?.onTrackInfoReceived = nil
        controller?.onDecodingError = nil
        controller?.stopListening()
        controller = nil
    }

    deinit {
        stopListening()
    }
}
