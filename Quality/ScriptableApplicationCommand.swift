//
//  ScriptableApplicationCommand.swift
//  LosslessSwitcher
//
//  Created by Vincent Neo on 6/12/23.
//

import Cocoa

class ScriptableApplicationCommand: NSScriptCommand {
    
    override func performDefaultImplementation() -> Any? {
        guard let delegate = AppDelegate.instance else {
            return -1000
        }

        let od = delegate.outputDevices
        guard let sampleRate = od?.currentSampleRate else {
            return -1
        }
        return Int(sampleRate * 1000)
    }
}

class SourceSampleRateCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        AppDelegate.instance?.outputDevices.sourceFormat.flatMap { Int(exactly: $0.sampleRate) } ?? -1
    }
}

class SourceBitDepthCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        AppDelegate.instance?.outputDevices.sourceFormat?.bitDepth ?? -1
    }
}

class OutputBitDepthCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        AppDelegate.instance?.outputDevices.currentBitDepth ?? -1
    }
}

class ReadCurrentTrackCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let devices = AppDelegate.instance?.outputDevices else {
            scriptErrorNumber = -1000
            scriptErrorString = "LosslessSwitcher is not ready."
            return nil
        }
        devices.readCurrentTrackFromMusic()
        return nil
    }
}
