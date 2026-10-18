//
//  ContentView.swift
//  Quality
//
//  Created by Vincent Neo on 18/4/22.
//

import SwiftUI
import OSLog
import SimplyCoreAudio

struct ContentView: View {
    @EnvironmentObject var outputDevices: OutputDevices
    
    var body: some View {
        VStack {
            Text("Source: \(outputDevices.sourceFormat?.description ?? "Not detected")")
                .font(.system(size: 14.5, weight: .medium))
            Text("Output: \(outputDevices.outputFormatDescription)")
                .font(.system(size: 20, weight: .semibold))
            if outputDevices.sourceFormat?.origin == .musicMetadata {
                Text("Rate from Music metadata; source codec and bit depth are unknown. Output bit depth is unchanged.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let device = outputDevices.selectedOutputDevice ?? outputDevices.defaultOutputDevice {
                Text(device.name)
                    .font(.system(size: 14.5, weight: .regular, design: .default))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let message = outputDevices.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let warning = outputDevices.sourceOutputWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 340)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
