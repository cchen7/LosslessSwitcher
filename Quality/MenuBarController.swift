//
//  MenuBarController.swift
//  LosslessSwitcher
//
//  Created by Vincent Neo on 18/6/25.
//

import Observation
import SwiftUI

@Observable
class MenuBarController {
    static let shared = MenuBarController()
    @ObservationIgnored
    let outputDevices: OutputDevices
    
    @ObservationIgnored
    private let mrController: MediaRemoteController
    
    init() {
        let outputDevices = OutputDevices()
        self.outputDevices = outputDevices
        self.mrController = MediaRemoteController(outputDevices: outputDevices)
    }

    func stop() {
        outputDevices.stopDetection()
        mrController.stopListening()
    }
}
