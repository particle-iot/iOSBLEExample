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
        case SearchingForDevice
        case Connecting
        case ScanningForAPs
        case EnteringCredentials
        case JoiningNetwork
        case CheckingJoinedNetwork
        case Finished
        case Error
        case ErrorNoConnection
        case ErrorUnableToConnect
        case ErrorFailedToJoinNetwork
    }
    
    @State var wifiOnboardingState: WiFiConnectivityState = .SearchingForDevice
    
    @State var bleName: String
    @State var mobileSecret: String
    
    @State var password: String = ""
    
    //this field below is quite terrible, but its used so the UI can show the network name in the same
    //manner as the password box, purely for asthetics.. there is probably a better way, but the bindings
    @State var dummyField: String = ""
    
    @State var selectedNetwork: Particle_Ctrl_Wifi_ScanNetworksReply.Network? = nil
    
    //this object is to observe the underlying BLE state so swiftUI can automatically update as the state changes
    @StateObject var particleBLEObservable = ParticleBLEObservable()
    
    //this is used to refresh the wifi networks list. This timer always runs and we use the counter to measure it
    //the design pattern of "running a timer all the time and observing it / resetting it" isn't great, but swiftUI has
    //not matured enough to give a better version of this (as of writing)
    @State var wifiAPRefreshTimer = Timer.publish(every: 1,  on: .main, in: .common).autoconnect()
    @State var wifiAPRefreshCount = 0

    //the particleBLEObservable delegate
    func stateUpdated() {
        if particleBLEObservable.connected {
            if( wifiOnboardingState == .Connecting ) {
                wifiOnboardingState = .ScanningForAPs
            }
        }
        else if particleBLEObservable.deviceFound {
            if( wifiOnboardingState == .SearchingForDevice ) {
                wifiOnboardingState = .Connecting
            }
        }
        else {
            //go to an error state if we disconnect before we've finished
            if( (wifiOnboardingState != .Connecting) && (wifiOnboardingState != .SearchingForDevice) ) {
                wifiOnboardingState = .Error
            }
        }
    }
    
    var body: some View {
      VStack() {
          //the connecting and searching UI is the same in this application
          //the different is just that we show different error messages
          if wifiOnboardingState == .SearchingForDevice || wifiOnboardingState == .Connecting {
              VStack() {
                  //just show the state as it connects
                  Text("Interface: " + particleBLEObservable.bleInterfaceStateAsTextString)
                  Text("Protocol: " + particleBLEObservable.bleProtocolStateAsTextString)
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
                      //time out caused by what?
                      if wifiOnboardingState == .SearchingForDevice {
                          wifiOnboardingState = .ErrorNoConnection
                      }
                      else {
                          wifiOnboardingState = .ErrorUnableToConnect
                      }
                  }
              }
          }
          //the scanning for wifi access points UI page is updated as new access points become available
          //each successful scan MAY add in more networks to the list. the BLE Observer keeps the list up to date
          //by merging in new networks as they are found
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
                          //re-request the wifi list infinitum (but only every 10 seconds,
                          //this being an arbitary number I invented as 'reasonable' but without any evidence for / against
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
          //This screen always asked for the password. Some networks don't need a password, but
          //that UI flow hasn't been implemented right now (its pretty trivial to do so, as the wifi AP list
          //has info on what security each network needs)
          else if wifiOnboardingState == .EnteringCredentials {
              VStack() {
                  HStack() {
                      Text("Wi-Fi AP")
                      TextField(selectedNetwork!.ssid, text: $dummyField)
                      .disabled(true)
                      .padding()
                      .font(Font.custom("HelveticaNeue", size: 20, relativeTo: .body))
                      .foregroundColor(Color.red)
                  }
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
                      //switch to the checking state immediatly - the closure below will kick it out of this state when it completes
                      wifiOnboardingState = .JoiningNetwork
                      
                      particleBLEObservable.connectWithPassword(network: selectedNetwork!, password: password) { error in
                          if error != nil {
                              wifiOnboardingState = .ErrorFailedToJoinNetwork
                          }
                          else {
                              wifiOnboardingState = .CheckingJoinedNetwork
                          }
                      }
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
          }
          else if wifiOnboardingState == .CheckingJoinedNetwork {
              VStack() {
                  Text("Checking Joined Network")
                  Text(particleBLEObservable.currentConnectedNetwork.ssid)
                  ProgressView()
                      .padding()
                      .shadow(color: Color(red: 0, green: 0, blue: 0.6),
                                          radius: 4.0, x: 1.0, y: 2.0)
              }
              .onAppear() {
                  //request the wifi list
                  particleBLEObservable.requestCurrentlyConnectedNetwork() { error in
                      if error == nil {
                          if (selectedNetwork?.ssid == particleBLEObservable.currentConnectedNetwork.ssid) {
                              wifiOnboardingState = .Finished
                          }
                          else {
                              wifiOnboardingState = .ErrorFailedToJoinNetwork
                          }
                      }
                  }

                  //reset the timer
                  wifiAPRefreshCount = 0
              }
              .onReceive(self.wifiAPRefreshTimer) { currentTime in
                  wifiAPRefreshCount += 1

                  if wifiAPRefreshCount > 5 {
                      //re-request the wifi current connection
                      particleBLEObservable.requestCurrentlyConnectedNetwork() { error in
                          //its possible this can error IF an existing call was still in progress
                          if error == nil {
                              if (selectedNetwork?.ssid == particleBLEObservable.currentConnectedNetwork.ssid) {
                                  wifiOnboardingState = .Finished
                              }
                              else {
                                  wifiOnboardingState = .ErrorFailedToJoinNetwork
                              }
                          }
                      }
                      
                      //reset the timer again
                      wifiAPRefreshCount = 0
                  }
                  
                  //did we connect?!
                  //Note, here you can do additional network rechability tests etc... to validate that a connection is made
                  //You can also check if the device is now talking to the Particle Cloud
                  if (particleBLEObservable.currentConnectedNetwork != nil) && (selectedNetwork?.ssid == particleBLEObservable.currentConnectedNetwork.ssid) {
                      wifiOnboardingState = .Finished
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
          else if wifiOnboardingState == .ErrorUnableToConnect {
              Text("Unable to connect to the device!")
          }
          else if wifiOnboardingState == .ErrorFailedToJoinNetwork {
              Text("Error joining network!")
          }
      }
    }
}
