//
//  ParticleBLEObservable.swift
//  iOSBLEExample
//
//  Created by Nick Lambourne on 10/20/22.
//
// This class is used by SwiftUI components to observe changes going on in the underlying BLE protocol
// It also acts as a proxy for commands being sent to the device so when the result of the API call is ready,
// the class can observe the updated data and merge it into the UI layer

import Foundation

protocol ParticleBLEObservableDelegate {
    func stateUpdated()
}

class ParticleBLEObservable: ObservableObject, ParticleBLEProtocolStatusDelegate {

    var delegate: ParticleBLEObservableDelegate? = nil
    var connected: Bool = false
    var deviceFound: Bool = false
    
    var allWiFiApsSeen: [Particle_Ctrl_Wifi_ScanNetworksReply.Network] = []
    
    init() {
        wifiAPs = []
        bleInterfaceStateAsTextString = "Idle"
        bleProtocolStateAsTextString = "Disconnected"
        currentConnectedNetwork = Particle_Ctrl_Wifi_GetCurrentNetworkReply()
        
        ParticleBLEExampleGlobals.particleBLEProtocolInstance.registerStatusDelegate(delegate: self)
    }
    
    func setDelegate(delegate: ParticleBLEObservableDelegate) {
        self.delegate = delegate
    }
    
    func onStatusUpdated(protocolState: ParticleBLEProtocol.ProtocolState, interfaceState: ParticleBLE.State) {
        print("New BLE Protocol status \(protocolState)")
        print("New BLE Interface status \(interfaceState)")

        bleInterfaceStateAsTextString = interfaceState.rawValue
        bleProtocolStateAsTextString = protocolState.rawValue
        
        //we use the protocol layer as an indication its ok to start the setup process
        connected = (protocolState == .connected)
        
        //log if we saw the device atleast once for error handling purposes
        if (interfaceState == .connectingToDevice) || (interfaceState == .connectingToDeviceTimeout) || (interfaceState == .connectedButWaitingForVersion) {
            deviceFound = true
        }

        if delegate != nil {
            delegate?.stateUpdated()
        }
    }
    
    //protocol wrappers
    //these are used so it can update this observable that is used by SwiftUI to redraw the screen when it updates
    func deleteExistingWiFiAPs(completionHandler: @escaping (_ error: Error?) -> Void) {
        ParticleBLEExampleGlobals.particleBLEProtocolInstance.clearKnownNetworks() { error in
            if error != nil {
                print("clearKnownNetworks error: " + error!.localizedDescription)
            } else {
                //nothing!
            }
            
            completionHandler(error)
        }
    }
    
    func requestWiFiAPs() {
        ParticleBLEExampleGlobals.particleBLEProtocolInstance.requestWiFiAPs() { newWifiAPs, error in
            if error == nil {
                //first, update any networks that have a name that is not available. This solves the problem where a wifi network
                //can be seen periodically, but its full details are not available from a single scan
                for network in newWifiAPs! {

                    //merge in the data
                    if let i = self.allWiFiApsSeen.firstIndex(where: { $0.bssid == network.bssid }) {
                        if self.allWiFiApsSeen[i].ssid.count == 0 {
                            self.allWiFiApsSeen[i].ssid = network.ssid
                        }
                        self.allWiFiApsSeen[i].rssi = network.rssi
                    }
                    else {
                        self.allWiFiApsSeen.append(network)
                    }
                }

                //update the visible network list to just those APs with text names
                var localWiFiAps: [Particle_Ctrl_Wifi_ScanNetworksReply.Network] = []
                for network in self.allWiFiApsSeen {
                    if network.ssid.count > 0 {
                        if !localWiFiAps.contains(where: {$0.ssid == network.ssid}) {
                            localWiFiAps.append(network)
                        }
                    }
                }

                //sort the list by name and store in the class
                self.wifiAPs = localWiFiAps.sorted(by: { $0.ssid < $1.ssid } )
            } else {
                print("requestWiFiAPs error: " + error!.localizedDescription)
            }
        }
    }

    func connectWithPassword(network: Particle_Ctrl_Wifi_ScanNetworksReply.Network, password: String, completionHandler: @escaping (_ error: Error?) -> Void) {
        ParticleBLEExampleGlobals.particleBLEProtocolInstance.requestJoinWiFiNetwork(network: network, password: password) { error in
            if error != nil {
                print("connectWithPassword error: " + error!.localizedDescription)
            }
            
            //success!
            completionHandler(error)
        }
    }
    
    func connectWithNoPassword(network: Particle_Ctrl_Wifi_ScanNetworksReply.Network, completionHandler: @escaping (_ error: Error?) -> Void) {
        ParticleBLEExampleGlobals.particleBLEProtocolInstance.requestJoinWiFiNetwork(network: network, password: nil) { error in
            if error != nil {
                print("connectWithNoPassword error: " + error!.localizedDescription)
            }
            
            //success!
            completionHandler(error)
        }
    }

    func requestCurrentlyConnectedNetwork(completionHandler: @escaping (_ error: Error?) -> Void) {
        ParticleBLEExampleGlobals.particleBLEProtocolInstance.requestCurrentNetwork() { currentConnectedAP, error in
            
            print("requestCurrentlyConnectedNetwork \(String(describing: currentConnectedAP?.ssid))");
            
            if error != nil {
                print("requestCurrentlyConnectedNetwork error: " + error!.localizedDescription)
            } else {
                self.currentConnectedNetwork = currentConnectedAP!
            }
            
            completionHandler(error)
        }
    }

    //These published variables automatically redraw any swift UI observers that are listening
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
    
    @Published var bleInterfaceStateAsTextString: String {
        didSet {
            //nothing
        }
    }
    
    @Published var bleProtocolStateAsTextString: String {
        didSet {
            //nothing
        }
    }
    
    //these functions can call the BLE iOS system wide prompt to pop up
    //NOT HANDLED:
    // - user permission denied
    // - user permission revoked
    func startBLERunning(bleName: String, mobileSecret: String) {

        //reset interface state
        deviceFound = false
        connected = false
        
        //TODO - stop the below lines from running on a retry...
        
        //this will cause BLE to be turned on. Its a good place to prime the user for the permissions dialog
        ParticleBLEExampleGlobals.particleBLEProtocolInstance.startup(bleName: bleName, mobileSecret: mobileSecret) {
            
            //this can be deferred in an application as it kicks off the actual connection process. We just
            //happen to call it here immediatly
            ParticleBLEExampleGlobals.particleBLEInstance.startConnectionProcess()
        }
    }
    
    func stopBLE() {
        ParticleBLEExampleGlobals.particleBLEInstance.disconnect();
    }
}
