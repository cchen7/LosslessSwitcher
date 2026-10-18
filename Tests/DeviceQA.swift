import AppKit
import CoreAudio
import Foundation

struct QAFailure: Error, CustomStringConvertible {
    let description: String
}

func property(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
}

func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, initial: T) throws -> T {
    var address = property(selector)
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
    }
    guard status == noErr else { throw QAFailure(description: "CoreAudio read failed: \(status)") }
    return value
}

func write<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, value: T) throws {
    var address = property(selector)
    var value = value
    let status = withUnsafePointer(to: &value) {
        AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), $0)
    }
    guard status == noErr else { throw QAFailure(description: "CoreAudio write failed: \(status)") }
}

func waitUntil(_ timeout: TimeInterval, condition: () throws -> Bool) rethrows -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if try condition() { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    } while Date() < deadline
    return try condition()
}

func check(_ success: Bool, _ message: String) throws {
    guard success else { throw QAFailure(description: message) }
    print("PASS: \(message)")
}

func run() throws {
    guard CommandLine.arguments.count == 3 else {
        throw QAFailure(description: "Usage: swift Tests/DeviceQA.swift /path/to/LosslessSwitcher.app DEVICE_NAME")
    }
    let app = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
    let requestedName = CommandLine.arguments[2]
    guard let bundleID = Bundle(url: app)?.bundleIdentifier else {
        throw QAFailure(description: "Application bundle not found: \(app.path)")
    }
    try check(
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty,
        "No existing LosslessSwitcher instance"
    )
    guard UserDefaults(suiteName: bundleID)?
        .string(forKey: "com.vincent-neo.LosslessSwitcher-Key-SelectedDeviceUID") == nil else {
        throw QAFailure(description: "Select Default Device in LosslessSwitcher before running this test.")
    }
    guard UserDefaults(suiteName: bundleID)?.string(forKey: "KeyShellScriptPath") == nil else {
        throw QAFailure(description: "Clear the custom script before testing to avoid script side effects.")
    }

    let system = AudioObjectID(kAudioObjectSystemObject)
    var address = property(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    let sizeStatus = AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size)
    guard sizeStatus == noErr else { throw QAFailure(description: "Cannot enumerate audio devices: \(sizeStatus)") }
    var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.stride)
    let listStatus = devices.withUnsafeMutableBytes {
        AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!)
    }
    guard listStatus == noErr else { throw QAFailure(description: "Cannot read audio devices: \(listStatus)") }
    let matches = try devices.filter {
        let name = try read($0, kAudioObjectPropertyName, initial: "" as CFString) as String
        return name.localizedCaseInsensitiveContains(requestedName)
    }
    guard matches.count == 1, let device = matches.first else {
        throw QAFailure(description: "Expected exactly one audio device matching \(requestedName).")
    }
    let originalDefault = try read(system, kAudioHardwarePropertyDefaultOutputDevice, initial: AudioDeviceID(0))
    let originalRate = try read(device, kAudioDevicePropertyNominalSampleRate, initial: Double(0))
    let process = Process()
    process.executableURL = app.appendingPathComponent("Contents/MacOS/LosslessSwitcher")

    func setRate(_ rate: Double) throws {
        try write(device, kAudioDevicePropertyNominalSampleRate, value: rate)
        try check(try waitUntil(3) {
            try read(device, kAudioDevicePropertyNominalSampleRate, initial: Double(0)) == rate
        }, "Hardware accepts \(Int(rate)) Hz")
    }

    func displayedRate() throws -> Double {
        let query = Process()
        query.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        query.arguments = ["-e", """
            using terms from application "\(app.path)"
                tell application "\(app.path)" to get latest sample rate
            end using terms from
            """]
        let pipe = Pipe()
        query.standardOutput = pipe
        try query.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        query.waitUntilExit()
        guard query.terminationStatus == 0,
              let rate = Double(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw QAFailure(description: "Cannot query the application's displayed sample rate.")
        }
        return rate
    }

    var testError: Error?
    do {
        try write(system, kAudioHardwarePropertyDefaultOutputDevice, value: device)
        try check(try waitUntil(3) {
            try read(system, kAudioHardwarePropertyDefaultOutputDevice, initial: AudioDeviceID(0)) == device
        }, "Requested device is the default output")
        try setRate(44100)
        try process.run()
        try check(waitUntil(10) {
            NSRunningApplication(processIdentifier: process.processIdentifier)?.isFinishedLaunching == true
        }, "Application completes launch")
        for rate in [44100.0, 96000.0, 192000.0, 44100.0] {
            try setRate(rate)
            try check(try waitUntil(3) { try displayedRate() == rate }, "Displayed rate follows hardware at \(Int(rate)) Hz")
        }
    } catch {
        testError = error
    }

    var stopped = true
    if process.isRunning {
        stopped = NSRunningApplication(processIdentifier: process.processIdentifier)?.terminate() == true &&
            waitUntil(8, condition: { !process.isRunning })
    }
    try write(system, kAudioHardwarePropertyDefaultOutputDevice, value: originalDefault)
    try setRate(originalRate)
    try check(try waitUntil(3) {
        try read(system, kAudioHardwarePropertyDefaultOutputDevice, initial: AudioDeviceID(0)) == originalDefault
    }, "Original audio output restored")
    try check(stopped, "QA application exits gracefully")
    if let testError { throw testError }
}

do {
    try run()
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
