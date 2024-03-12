//
//  ParticleBLEInterfaceAbstract.swift
//  iOSBLEExample
//
//  Created by Nick Lambourne on 11/27/22.
//

import Foundation

//This file is just to keep the BLE interface abstracted
//It allows the protocol class to be unit tests without actually having the device attached

protocol ParticleBLEInterfaceDataDelegate {
    func onDataReceived(data: [UInt8])
}

protocol ParticleBLEStatusDelegate {
    func onStatusUpdated(state: ParticleBLE.State)
}

public class ParticleBLEInterfaceAbstract : NSObject {
    
    enum State: String, Codable {
        case idle
        case lookingForDevice
        case lookingForDeviceTimeout
        case connectingToDevice
        case connectingToDeviceTimeout
        case connectedButWaitingForVersion
        case connected
        case disconnected
    }
    
    var state: State = .idle
    
    //delegate list
    var statusDelegates:[ParticleBLEStatusDelegate] = []
    var dataDelegates:[ParticleBLEInterfaceDataDelegate] = []
    
    func registerDataDelegate( delegate: ParticleBLEInterfaceDataDelegate ) {
        dataDelegates.append( delegate )
    }
    
    func informDelegatesOfDataAvailable(data: [UInt8]) {
        for d in dataDelegates {
            d.onDataReceived(data: data)
        }
    }
    
    func registerStatusDelegate( delegate: ParticleBLEStatusDelegate ) {
        statusDelegates.append( delegate )
    }

    func informDelegatesOfStatusUpdate(state: State) {
        for d in statusDelegates {
            d.onStatusUpdated( state: state )
        }
    }
    
    func startup(bleName: String, completionHandler: @escaping () -> Void) {
        assert( false )
    }
    
    func disconnect() {
        assert( false )
    }
    
    func sendBuffer(buffer: [UInt8]) {
        assert( false )
    }
}
