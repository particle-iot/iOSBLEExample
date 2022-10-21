//
//  iOSBLEExampleApp.swift
//  iOSBLEExample
//
//  Created by Nick Lambourne on 10/20/22.
//

import SwiftUI


struct ParticleBLEExampleGlobals {
    static let particleBLEInstance = ParticleBLE()
}

@main
struct iOSBLEExampleApp: App {
    
    init() {
        ParticleBLEExampleGlobals.particleBLEInstance.startup()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
