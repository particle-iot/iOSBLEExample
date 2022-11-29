//
//  ContentView.swift
//  iOSBLEExample
//
//  Created by Nick Lambourne on 10/20/22.
//

import SwiftUI

//This is an entry point for the setup flow screen.
//The bleName is taken from the firmware BLE application and should be customized per product
//The mobile secret is taken from the QR on the front of the module. This secret can be overridden to something
//else in the firmware if needed.
struct ContentView: View {
    @State private var isShowingScanner = false
    
    @AppStorage("bleName") private var bleName: String = "aabbcc"
    @AppStorage("mobileSecret") private var mobileSecret: String = ""
    
    var body: some View {
        NavigationView {
            VStack() {
                Image("particle-logo-stacked").padding()
                HStack() {
                    Text("BLE Name")
                    TextField(
                        "BLE Name",
                        text: $bleName
                    )
                    .padding()
                    .font(Font.custom("HelveticaNeue", size: 20, relativeTo: .body))
                    .foregroundColor(Color.blue)
                }
                
                HStack() {
                    Text("Mobile Secret")
                    TextField(
                        "Mobile Secret",
                        text: $mobileSecret
                    )
                    .padding()
                    .font(Font.custom("HelveticaNeue", size: 20, relativeTo: .body))
                    .foregroundColor(Color.blue)
                    NavigationLink(destination: QRScanner()) {
                        Text("Scan")
                    }
                    .padding()
                }
                
                NavigationLink(destination: SetupWiFi(bleName: bleName, mobileSecret: mobileSecret)) {
                    Text("Setup Wi-Fi")
                }
                .padding()
            }
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
