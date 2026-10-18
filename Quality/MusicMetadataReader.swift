import AppKit
import Carbon
import Foundation

enum MusicMetadataError: LocalizedError {
    case notRunning
    case notPlaying
    case consentRequired
    case accessDenied
    case trackChanged
    case invalidReply
    case sampleRateUnavailable
    case timedOut
    case appleEvent(OSStatus)

    var errorDescription: String? {
        switch self {
        case .notRunning:
            return "Music is not running."
        case .notPlaying:
            return "Music is not playing."
        case .consentRequired:
            return "No fresh decoder format. Choose Read Current Track from Music to allow startup detection."
        case .accessDenied:
            return "Allow LosslessSwitcher to access Music in System Settings > Privacy & Security > Automation."
        case .trackChanged:
            return "Music changed tracks while reading its format. Try again."
        case .invalidReply:
            return "Music returned incomplete track information."
        case .sampleRateUnavailable:
            return "Music did not report a sample rate for the current track."
        case .timedOut:
            return "Reading the current Music track timed out."
        case .appleEvent(let status):
            return "Music metadata could not be read (Apple event \(status))."
        }
    }
}

enum MusicMetadataReader {
    static func readCurrentTrack(allowAuthorizationPrompt: Bool) throws -> MusicTrackSnapshot {
        guard let music = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first else {
            throw MusicMetadataError.notRunning
        }
        let target = NSAppleEventDescriptor(processIdentifier: music.processIdentifier)
        let permission = AEDeterminePermissionToAutomateTarget(
            target.aeDesc, kAECoreSuite, kAEGetData, allowAuthorizationPrompt
        )
        switch permission {
        case noErr: break
        case OSStatus(errAEEventWouldRequireUserConsent): throw MusicMetadataError.consentRequired
        case OSStatus(errAEEventNotPermitted): throw MusicMetadataError.accessDenied
        case OSStatus(procNotFound): throw MusicMetadataError.notRunning
        default: throw MusicMetadataError.appleEvent(permission)
        }

        let deadline = ProcessInfo.processInfo.systemUptime + 3
        let track = try property("pTrk")
        guard try isPlaying(target: target, deadline: deadline) else { throw MusicMetadataError.notPlaying }
        // Music doesn't resolve a list-valued get, so bracket the rate with identity checks.
        let before = try identity(track: track, target: target, deadline: deadline)
        let rateValue = try get("pSRt", of: track, target: target, deadline: deadline)
        guard let rate = rateValue.coerce(toDescriptorType: typeIEEE64BitFloatingPoint)?.doubleValue,
              rate.isFinite, rate > 0 else { throw MusicMetadataError.sampleRateUnavailable }
        let after = try identity(track: track, target: target, deadline: deadline)
        guard before == after, !music.isTerminated else { throw MusicMetadataError.trackChanged }
        guard try isPlaying(target: target, deadline: deadline) else { throw MusicMetadataError.notPlaying }
        return MusicTrackSnapshot(track: after, sampleRate: rate, isPlaying: true)
    }

    private static func code(_ value: String) -> AEKeyword {
        value.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func property(
        _ name: String, of container: NSAppleEventDescriptor = .null()
    ) throws -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: typeProperty), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: OSType(formPropertyID)), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code(name)), forKeyword: AEKeyword(keyAEKeyData))
        record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        guard let result = record.coerce(toDescriptorType: typeObjectSpecifier) else {
            throw MusicMetadataError.invalidReply
        }
        return result
    }

    private static func get(
        _ name: String, of container: NSAppleEventDescriptor = .null(),
        target: NSAppleEventDescriptor, deadline: TimeInterval
    ) throws -> NSAppleEventDescriptor {
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining >= 0.1 else { throw MusicMetadataError.timedOut }
        let event = NSAppleEventDescriptor(
            eventClass: kAECoreSuite, eventID: kAEGetData, targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(try property(name, of: container), forKeyword: keyDirectObject)
        let options: NSAppleEventDescriptor.SendOptions = [
            .waitForReply, .neverInteract, .dontRecord,
            NSAppleEventDescriptor.SendOptions(rawValue: UInt(kAEDoNotPromptForUserConsent))
        ]
        let reply = try event.sendEvent(options: options, timeout: remaining)
        if let error = reply.paramDescriptor(forKeyword: keyErrorNumber), error.int32Value != 0 {
            throw MusicMetadataError.appleEvent(error.int32Value)
        }
        guard let value = reply.paramDescriptor(forKeyword: keyDirectObject) else {
            throw MusicMetadataError.invalidReply
        }
        return value
    }

    private static func text(
        _ name: String, track: NSAppleEventDescriptor, target: NSAppleEventDescriptor, deadline: TimeInterval
    ) throws -> String {
        let value = try get(name, of: track, target: target, deadline: deadline)
        if let text = value.stringValue { return text }
        if value.descriptorType == typeType, value.typeCodeValue == code("msng") { return "" }
        throw MusicMetadataError.invalidReply
    }

    private static func identity(
        track: NSAppleEventDescriptor, target: NSAppleEventDescriptor, deadline: TimeInterval
    ) throws -> TrackIdentity {
        let title = try text("pnam", track: track, target: target, deadline: deadline)
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MusicMetadataError.invalidReply
        }
        return TrackIdentity(
            title: title,
            artist: try text("pArt", track: track, target: target, deadline: deadline),
            album: try text("pAlb", track: track, target: target, deadline: deadline)
        )
    }

    private static func isPlaying(target: NSAppleEventDescriptor, deadline: TimeInterval) throws -> Bool {
        let state = try get("pPlS", target: target, deadline: deadline)
        guard state.descriptorType == typeEnumerated else { throw MusicMetadataError.invalidReply }
        return state.enumCodeValue == code("kPSP")
    }
}
