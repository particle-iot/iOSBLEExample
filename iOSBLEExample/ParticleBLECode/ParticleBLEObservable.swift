//
//  ParticleBLEObservable.swift
//  iOSBLEExample
//
//  Created by Nick Lambourne on 10/20/22.
//

import Foundation

protocol ParticleBLEObservableDelegate {
    func stateUpdated()
}

class ParticleBLEObservable: ObservableObject, ParticleBLEDelegate {
    
    var delegate: ParticleBLEObservableDelegate? = nil
    var connected: Bool = false
    
    var allWiFiApsSeen: [Particle_Ctrl_Wifi_ScanNetworksReply.Network] = []
    
    init() {
        wifiAPs = []
        bleStateAsTextString = "Idle"
        currentConnectedNetwork = Particle_Ctrl_Wifi_GetCurrentNetworkReply()
    }
    
    func setDelegate(delegate: ParticleBLEObservableDelegate) {
        self.delegate = delegate
    }
    
    func statusUpdated() {
        print("New BLE status \(ParticleBLEExampleGlobals.particleBLEInstance.bleState)")
        
        //first, update any networks that have a name that is not available. This solves the problem where a wifi network
        //can be seen periodically, but its full details are not available from a single scan
        for network in ParticleBLEExampleGlobals.particleBLEInstance.lastWifiAPsSeen {
            
            //merge in the data
            if let i = allWiFiApsSeen.firstIndex(where: { $0.bssid == network.bssid }) {
                if allWiFiApsSeen[i].ssid.count == 0 {
                    allWiFiApsSeen[i].ssid = network.ssid
                }
                allWiFiApsSeen[i].rssi = network.rssi
            }
            else {
                allWiFiApsSeen.append(network)
            }
        }
        
        //update the visible network list to just those APs with text names
        var localWiFiAps: [Particle_Ctrl_Wifi_ScanNetworksReply.Network] = []
        for network in allWiFiApsSeen {
            if network.ssid.count > 0 {
                if !localWiFiAps.contains(where: {$0.ssid == network.ssid}) {
                    localWiFiAps.append(network)
                }
            }
        }
        
        //sort the list by name and store in the class
        wifiAPs = localWiFiAps.sorted(by: { $0.ssid < $1.ssid } )
        
        bleStateAsTextString = ParticleBLEExampleGlobals.particleBLEInstance.bleState.rawValue
        
        currentConnectedNetwork = ParticleBLEExampleGlobals.particleBLEInstance.currentConnectedAP
        
        connected = (ParticleBLEExampleGlobals.particleBLEInstance.bleState == .connectedAndRunning)
        
        if delegate != nil {
            delegate?.stateUpdated()
        }
    }
    
    func requestWiFiAPs() {
        ParticleBLEExampleGlobals.particleBLEInstance.requestWiFiAPs()
    }

    func connectWithPassword(network: Particle_Ctrl_Wifi_ScanNetworksReply.Network, password: String) {
        ParticleBLEExampleGlobals.particleBLEInstance.requestJoinWiFiNetwork(network: network, password: password)
    }
    
    func requestCurrentlyConnectedNetwork() {
        ParticleBLEExampleGlobals.particleBLEInstance.requestCurrentNetwork()
    }

    @Published var wifiAPs: [Particle_Ctrl_Wifi_ScanNetworksReply.Network] {
        didSet {
            //nothing
        }
    }
    
    @Published var currentConnectedNetwork: Particle_Ctrl_Wifi_GetCurrentNetworkReply {
        didSet {
            //nothing
        }
    }
    
    @Published var bleStateAsTextString: String {
        didSet {
            //nothing
        }
    }
    
    func startBLERunning(bleName: String, mobileSecret: String) {
        ParticleBLEExampleGlobals.particleBLEInstance.registerDelegate(delegate: self)
        ParticleBLEExampleGlobals.particleBLEInstance.setDeviceDetails( bleName: bleName, mobileSecret: mobileSecret)
        ParticleBLEExampleGlobals.particleBLEInstance.updateState(state: .lookingForDevice)
    }
}
