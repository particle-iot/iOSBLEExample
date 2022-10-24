//
//  QRScanner.swift
//  iOSBLEExample
//
//  Created by Nick Lambourne on 10/21/22.
//

import Foundation
import SwiftUI

struct SetupWiFi: View, ParticleBLEObservableDelegate {
    
    //this is the state of the local UI panel that is selecting the wifi AP from the users perspective
    enum WiFiConnectivityState: Codable {
        case Connecting
        case ScanningForAPs
        case EnteringCredentials
        case JoiningNetwork
        case Finished
        case Error
        case ErrorNoConnection
    }
    
    @State var wifiOnboardingState: WiFiConnectivityState = .Connecting
    
    @State var bleName: String
    @State var mobileSecret: String
    
    @State var password: String = ""
    
    @State var selectedNetwork: Particle_Ctrl_Wifi_ScanNetworksReply.Network? = nil
    
    //this object is to observe the underlying BLE state so swiftUI can automatically update as the state changes
    @StateObject var particleBLEObservable = ParticleBLEObservable()
    
    //this is used to refresh the wifi networks list. This timer always runs and we use the counter to measure it
    @State var wifiAPRefreshTimer = Timer.publish(every: 1,  on: .main, in: .common).autoconnect()
    @State var wifiAPRefreshCount = 0
    
    //the particleBLEObservable delegate
    func stateUpdated() {
        if particleBLEObservable.connected {
            if( wifiOnboardingState == .Connecting ) {
                wifiOnboardingState = .ScanningForAPs
            }
            
            if( wifiOnboardingState == .JoiningNetwork ) {
                if selectedNetwork?.ssid == particleBLEObservable.currentConnectedNetwork.ssid {
                    wifiOnboardingState = .Finished
                }
            }
        }
        else {
            //go to an error state if we disconnect before we've finished
            if( wifiOnboardingState != .Connecting ) {
                wifiOnboardingState = .Error
            }
        }
    }
    
    var body: some View {
      VStack() {
          if wifiOnboardingState == .Connecting {
              VStack() {
                  //just show the state as it connects
                  Text(particleBLEObservable.bleStateAsTextString)
                  ProgressView()
                      .padding()
                      .shadow(color: Color(red: 0, green: 0, blue: 0.6),
                              radius: 4.0, x: 1.0, y: 2.0)
              }
              .onAppear() {
                  particleBLEObservable.setDelegate(delegate: self)
                  particleBLEObservable.startBLERunning( bleName: bleName, mobileSecret: mobileSecret)
                  
                  //reset the timer
                  wifiAPRefreshCount = 0
              }
              .onReceive(self.wifiAPRefreshTimer) { currentTime in
                  wifiAPRefreshCount += 1
                  
                  if wifiAPRefreshCount > 30 {
                      //time out
                      wifiOnboardingState = .ErrorNoConnection
                  }
              }
          }
          else if wifiOnboardingState == .ScanningForAPs {
              VStack() {
                  Text("Select Wi-Fi Network")
                  List(particleBLEObservable.wifiAPs, id: \.ssid) { ap in
                      HStack() {
                          Text(ap.ssid).padding()
                          Text(String(ap.rssi) + " dB").frame(maxWidth: .infinity, alignment: .trailing).padding()
                      }
                      .onTapGesture {
                          selectedNetwork = ap
                          
                          //join the selected network
                          wifiOnboardingState = .EnteringCredentials
                      }
                  }
                  .onAppear() {
                      //request the wifi list
                      particleBLEObservable.requestWiFiAPs()
                      
                      //reset the timer
                      wifiAPRefreshCount = 0
                  }
                  .onReceive(self.wifiAPRefreshTimer) { currentTime in
                      wifiAPRefreshCount += 1
                      
                      if wifiAPRefreshCount > 10 {
                          //re-request the wifi list
                          particleBLEObservable.requestWiFiAPs()
                          
                          //reset the timer again
                          wifiAPRefreshCount = 0
                      }
                  }
                  ProgressView()
                      .padding()
                      .shadow(color: Color(red: 0, green: 0, blue: 0.6),
                                          radius: 4.0, x: 1.0, y: 2.0)
              }
          }
          else if wifiOnboardingState == .EnteringCredentials {
              VStack() {
                  HStack() {
                      Text("Password")
                      TextField(
                        "Password",
                        text: $password
                      )
                      .padding()
                      .font(Font.custom("HelveticaNeue", size: 20, relativeTo: .body))
                      .foregroundColor(Color.red)
                  }
                  Button {
                      particleBLEObservable.connectWithPassword(network: selectedNetwork!, password: password)
                      wifiOnboardingState = .JoiningNetwork
                  }
                  label: {
                      Text("Submit")
                  }
              }
          }
          else if wifiOnboardingState == .JoiningNetwork {
              VStack() {
                  Text("Joining network")
                  Text(particleBLEObservable.currentConnectedNetwork.ssid)
                  ProgressView()
                      .padding()
                      .shadow(color: Color(red: 0, green: 0, blue: 0.6),
                                          radius: 4.0, x: 1.0, y: 2.0)
              }
              .onAppear() {
                  //request the wifi list
                  particleBLEObservable.requestCurrentlyConnectedNetwork()
                  
                  //reset the timer
                  wifiAPRefreshCount = 0
              }
              .onReceive(self.wifiAPRefreshTimer) { currentTime in
                  wifiAPRefreshCount += 1

                  if wifiAPRefreshCount > 5 {
                      //re-request the wifi current connection
                      particleBLEObservable.requestCurrentlyConnectedNetwork()
                      
                      //reset the timer again
                      wifiAPRefreshCount = 0
                  }
              }
          }
          else if wifiOnboardingState == .Finished {
              Text("Finished! Time for a cup of tea and a nice biscuit")
          }
          else if wifiOnboardingState == .Error {
              Text("Something went horribly wrong")
          }
          else if wifiOnboardingState == .ErrorNoConnection {
              Text("Device was not found!")
          }
      }
    }
}
