//
//  SwiftRndSysExProbeApp.swift
//  SwiftRndSysExProbe
//
//  Created by Alexandre Enkerli on 2026-08-21.
//

import SwiftUI

@main
struct SwiftRndSysExProbeApp: App {
    private let hostModel = AudioUnitHostModel()

    var body: some Scene {
        WindowGroup {
            ContentView(hostModel: hostModel)
        }
    }
}
