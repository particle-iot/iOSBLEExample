//
//  ContentView.swift
//  iOSBLEExample
//
//  Created by Nick Lambourne on 10/20/22.
//

import SwiftUI

//Todo:
// create a state class and add in ParticleBLEDelegate to update the UI
// create an QR scanning flow

struct ContentView: View {
    var body: some View {
        Button {
            print("Scanning for devices!")
            ParticleBLEExampleGlobals.particleBLEInstance.updateState(state: .lookingForDevice)
        }
        label: {
            Text("Scan")
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
