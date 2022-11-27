//
//  iOSBLEExampleApp.swift
//  iOSBLEExample
//
//  Created by Nick Lambourne on 10/20/22.
//

import SwiftUI

struct ParticleBLEExampleGlobals {
    static let particleBLEInstance = ParticleBLE()
    static let particleBLEProtocolInstance = ParticleBLEProtocol(bleInterface: particleBLEInstance)
}

@main
struct iOSBLEExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

