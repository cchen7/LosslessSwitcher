//
//  CMPlayerStats.swift
//  Quality
//
//  Created by Vincent Neo on 19/4/22.
//

import Foundation
import CoreAudio
import OSLog
import Sweep

struct CMPlayerStats {
    let sampleRate: Double // Hz
    let bitDepth: Int
    let date: Date
    let priority: Int
}

// Decoder logs do not carry a reliable public track identifier. Use a bounded
// transition window instead of blindly taking the newest (possibly preloaded) track.
struct RateSelection {
    static func candidate(_ stats: [CMPlayerStats], near event: Date) -> CMPlayerStats? {
        stats.filter {
            let offset = $0.date.timeIntervalSince(event)
            return offset >= -1.5 && offset <= 2.0 &&
                $0.sampleRate.isFinite && $0.sampleRate > 0 &&
                (1...64).contains($0.bitDepth)
        }.min {
            let left = abs($0.date.timeIntervalSince(event))
            let right = abs($1.date.timeIntervalSince(event))
            return left == right ? $0.date < $1.date : left < right
        }
    }

    static func sampleRate(for source: Double, supported: [Double], preferMultiples: Bool) -> Double? {
        guard source.isFinite, source > 0 else { return nil }
        let rates = supported.filter { $0.isFinite && $0 > 0 }
        guard let nearest = rates.min(by: { abs($0 - source) < abs($1 - source) }) else { return nil }
        guard preferMultiples, nearest != source else { return nearest }
        let base = source.truncatingRemainder(dividingBy: 44100) == 0 ? 44100.0 : 48000.0
        return rates.filter {
            $0 < source && $0.truncatingRemainder(dividingBy: base) == 0
        }.max() ?? nearest
    }

    static func physicalFormat(
        at sampleRate: Double,
        bitDepth: Int,
        supported: [AudioStreamRangedDescription]
    ) -> AudioStreamBasicDescription? {
        let match = supported.filter {
            $0.mFormat.mFormatID == kAudioFormatLinearPCM &&
                $0.mSampleRateRange.mMinimum <= sampleRate &&
                sampleRate <= $0.mSampleRateRange.mMaximum &&
                $0.mFormat.mBitsPerChannel > 0
        }.min {
            abs(Int($0.mFormat.mBitsPerChannel) - bitDepth) <
                abs(Int($1.mFormat.mBitsPerChannel) - bitDepth)
        }
        guard var format = match?.mFormat else { return nil }
        format.mSampleRate = sampleRate
        return format
    }
}

class CMPlayerParser {
    static func parseMusicConsoleLogs(_ entries: [SimpleConsole]) -> [CMPlayerStats] {
        let kTimeDifferenceAcceptance = 5.0 // seconds
        var lastDate: Date?
        var sampleRate: Double?
        var bitDepth: Int?
        
        var stats = [CMPlayerStats]()
        
        for entry in entries {
            // ignore useless log messages for faster switching
            if !entry.message.contains("audioCapabilities:") {
                continue
            }
            
            let date = entry.date
            let rawMessage = entry.message
            
            if let lastDate = lastDate, date.timeIntervalSince(lastDate) > kTimeDifferenceAcceptance {
                sampleRate = nil
                bitDepth = nil
            }
            
            if let subSampleRate = rawMessage.firstSubstring(between: "asbdSampleRate = ", and: " kHz") {
                let strSampleRate = String(subSampleRate)
                sampleRate = Double(strSampleRate)
            }
            
            if let subBitDepth = rawMessage.firstSubstring(between: "sdBitDepth = ", and: " bit") {
                let strBitDepth = String(subBitDepth)
                bitDepth = Int(strBitDepth)
            }
            else if rawMessage.contains("sdBitRate") { // lossy
                bitDepth = 16
            }
            
            if let sr = sampleRate,
               let bd = bitDepth {
                let stat = CMPlayerStats(sampleRate: sr * 1000, bitDepth: bd, date: date, priority: 1)
                stats.append(stat)
                sampleRate = nil
                bitDepth = nil
                print("detected stat \(stat)")
                break
            }
            
            lastDate = date
            
        }
        return stats
    }
    
    static func parseCoreAudioConsoleLogs(_ entries: [SimpleConsole]) -> [CMPlayerStats] {
        entries.compactMap { entry in
            let message = entry.message
            guard message.contains("ACAppleLosslessDecoder.cpp"),
                  message.contains("Input format:"),
                  let rateText = message.firstSubstring(between: "ch, ", and: " Hz"),
                  let depthText = message.firstSubstring(between: "from ", and: "-bit source"),
                  let rate = Double(String(rateText).trimmingCharacters(in: .whitespacesAndNewlines)),
                  let depth = Int(String(depthText).trimmingCharacters(in: .whitespacesAndNewlines)),
                  rate.isFinite, rate > 0, (1...64).contains(depth)
            else { return nil }
            return CMPlayerStats(sampleRate: rate, bitDepth: depth, date: entry.date, priority: 5)
        }
    }

    static func parseCoreMediaConsoleLogs(_ entries: [SimpleConsole]) -> [CMPlayerStats] {
        let kTimeDifferenceAcceptance = 5.0 // seconds
        var lastDate: Date?
        var sampleRate: Double?
        let bitDepth = 24 // Core Media don't provide bit depth, but I am keeping this for now, since it seems to be the first to deliver accurate bitrate data, fairly consistently.
        
        var stats = [CMPlayerStats]()
        
        for entry in entries {
            let date = entry.date
            let rawMessage = entry.message
            
            if let lastDate = lastDate, date.timeIntervalSince(lastDate) > kTimeDifferenceAcceptance {
                sampleRate = nil
            }
            
            if rawMessage.contains("Creating AudioQueue") {
                if let subSampleRate = rawMessage.firstSubstring(between: "sampleRate:", and: .end) {
                    let strSampleRate = String(subSampleRate)
                    sampleRate = Double(strSampleRate)
                }
            }
            
            if let sr = sampleRate {
                let stat = CMPlayerStats(sampleRate: sr, bitDepth: bitDepth, date: date, priority: 2)
                stats.append(stat)
                sampleRate = nil
                print("detected stat \(stat)")
                break
            }
            
            lastDate = date
            
        }
        return stats
    }
}
