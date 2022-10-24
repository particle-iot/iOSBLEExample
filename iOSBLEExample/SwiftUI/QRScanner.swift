//
//  QRScanner.swift
//  iOSBLEExample
//
//  Created by Nick Lambourne on 10/21/22.
//

import Foundation
import SwiftUI
import CodeScanner

struct QRScanner: View {
    
    @Environment(\.presentationMode) var presentationMode

    func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let result):
            let details = result.string.components(separatedBy: " ")
            guard details.count == 2 else { return }

            UserDefaults.standard.set(details[1], forKey: "mobileSecret")
            
            presentationMode.wrappedValue.dismiss()

        case .failure(let error):
            print("Scanning failed: \(error.localizedDescription)")
        }
    }
    
  var body: some View {
      CodeScannerView(codeTypes: [.dataMatrix], simulatedData: "", completion: handleScan)
  }
}
