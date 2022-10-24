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

//
//// Create a BookInfo object and populate it:
//var info = BookInfo()
//info.id = 1734
//info.title = "Really Interesting Book"
//info.author = "Jane Smith"
//
//// As above, but generating a read-only value:
//let info2 = BookInfo.with {
//    $0.id = 1735
//    $0.title = "Even More Interesting"
//    $0.author = "Jane Q. Smith"
//  }
//
//// Serialize to binary protobuf format:
//let binaryData: Data = try info.serializedData()
//
//// Deserialize a received Data object from `binaryData`
//let decodedInfo = try BookInfo(serializedData: binaryData)
//
//// Serialize to JSON format as a Data object
//let jsonData: Data = try info.jsonUTF8Data()
//
//// Deserialize from JSON format from `jsonData`
//let receivedFromJSON = try BookInfo(jsonUTF8Data: jsonData)
