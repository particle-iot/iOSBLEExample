//
//  ParticleBLE.swift
//  iOSBLEExample
//
//  Created by Nick Lambourne on 10/20/22.
//

import Foundation
import CoreBluetooth
import NIOCore

protocol ParticleBLEDelegate {
    func statusUpdated()
}

class ParticleBLE: NSObject {
    
    enum BLEState: String, Codable {
        case idle
        case waitingForUserInput
        case lookingForDevice
        case lookingForDeviceTimeout
        case connectingToDevice
        case connectingToDeviceTimeout
        case connectedAndWaitingForVersion
        case connectedAndRunning
    }
    var bleState: BLEState = .idle

    var timer = Timer()
    var timerRunning: Bool = false
    var timerRunTime: Int = 0
    var bleScanning: Bool = false
    
    var lastWifiAPsSeen: [Particle_Ctrl_Wifi_ScanNetworksReply.Network] = []
    
    var currentConnectedAP: Particle_Ctrl_Wifi_GetCurrentNetworkReply = Particle_Ctrl_Wifi_GetCurrentNetworkReply()
    
    //this is the header for the BLE protocol
    let REQUEST_PACKET_OVERHEAD: Int = 8
    
    let ECHO_REQUEST_TYPE: UInt16 = 1
    let SCAN_NETWORKS_TYPE: UInt16 = 506
    let JOIN_KNOWN_NETWORK_TYPE: UInt16 = 500
    let GET_CURRENT_NETWORK_TYPE: UInt16 = 505
    
    struct ReceivingData {
        var reqID: UInt16
        var dataLength: UInt16
        var buf: ByteBuffer!
    }
    
    var receivingData: ReceivingData? = nil
    
    enum ParticleBLEState {
        case Inactive
        case Active
        case Passed
        case Failed
    }
    
    struct Message {
        var reqID: UInt16
        var payload: [UInt8]
    }

    //The bluetooth bits
    var centralManager: CBCentralManager!
    let serviceUUID = CBUUID(string: "6E400021-B5A3-F393-E0A9-E50E24DCCA9E")

    //the target peripheral!
    var peripheral: CBPeripheral?
    
    let rxUUID = CBUUID(string: "6E400022-B5A3-F393-E0A9-E50E24DCCA9E")
    let txUUID = CBUUID(string: "6E400023-B5A3-F393-E0A9-E50E24DCCA9E")
    let versionUUID = CBUUID(string: "6E400024-B5A3-F393-E0A9-E50E24DCCA9E")
    
    var rxCharacteristic: CBCharacteristic?
    var txCharacteristic: CBCharacteristic?
    var versionCharacteristic: CBCharacteristic?
    
    var reqIDToTypeDict: [UInt16: UInt16] = [:]
    var nextReqID: UInt16 = 0
    
    //device details
    var bleName: String = ""
    var mobileSecret: String = ""
    
    //delegate list
    var delegates:[ParticleBLEDelegate] = []

    func startup() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func setDeviceDetails(bleName: String, mobileSecret: String) {
        self.bleName = bleName
        self.mobileSecret = mobileSecret
    }

    func registerDelegate( delegate: ParticleBLEDelegate ) {
        delegates.append( delegate )
        delegate.statusUpdated()
    }
    
    private func informDelegates() {
        for d in delegates {
            d.statusUpdated()
        }
    }
    
    func updateState( state: BLEState ) {
        
        print("updateState(\(state))")
        
        //gotta be a new state, right?
        assert(self.bleState != state)
        
        var runTimer: Bool = false
        var resetTimeout: Bool = false
        var scanBLE: Bool = false

        switch state {
            case .waitingForUserInput:
                runTimer = false
                scanBLE = false

            case .lookingForDevice:
                resetTimeout = true
                runTimer = true
                scanBLE = true
        
            case .lookingForDeviceTimeout:
                resetTimeout = true
                runTimer = false
                scanBLE = false
            
            case .connectingToDevice:
                resetTimeout = true
                runTimer = true
                scanBLE = true
            
            case .connectedAndRunning:
                resetTimeout = true
                runTimer = false
                scanBLE = false
            
            case .connectedAndWaitingForVersion:
                resetTimeout = true
                runTimer = false
                scanBLE = false

            case .idle:
                resetTimeout = true
                runTimer = false
                scanBLE = false
            
            default:
                assert( false )
        }
        
        //timer changes?
        if runTimer && !timerRunning {
            print("Starting timer")
            timerRunTime = 0
            timer = Timer.scheduledTimer(timeInterval: 1, target: self,
                                         selector: (#selector(ParticleBLE.updateTimer)), userInfo: nil, repeats: true)
        }
        if !runTimer && timerRunning {
            print("Stopping timer")
            timer.invalidate()
        }
        if resetTimeout {
            timerRunTime = 0
        }
        timerRunning = runTimer
        
        //BLE scanning changes
        if scanBLE && !bleScanning {
            print("Starting BLE scanning")
            centralManager.scanForPeripherals(withServices: [], options: [CBCentralManagerScanOptionAllowDuplicatesKey : true] )
        }
        if !scanBLE && bleScanning {
            print("Stopping BLE scanning")
            centralManager.stopScan()
        }
        bleScanning = scanBLE
        
        //store the new state
        self.bleState = state
        
        //inform the delegates!
        informDelegates()
    }
    
    @objc func updateTimer() {
        timerRunTime += 1
        
        print("updateTimer\(timerRunTime)")

        switch self.bleState {
            case .lookingForDevice:
                if timerRunTime > 60 {
                    self.updateState(state: .lookingForDeviceTimeout)
                }
            break
            
            case .connectingToDevice:
                if timerRunTime > 60 {
                    self.updateState(state: .connectingToDeviceTimeout)
                }
                break

            default:
                //nothing
            break
        }
    }

}

extension ParticleBLE: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
            case .unknown:
                print("central.state is .unknown")
            case .resetting:
                print("central.state is .resetting")
            case .unsupported:
                print("central.state is .unsupported")
            case .unauthorized:
                print("central.state is .unauthorized")
            case .poweredOff:
                print("central.state is .poweredOff")
            case .poweredOn:
                print("central.state is .poweredOn")
            @unknown default:
                print("central.state is .unknown")
        }
    }

    func getManufacturingData( advertisementData: [String: Any] ) throws -> (companyID: UInt16, platformID: UInt16, setupCode: String) {
        //did we find our peripheral? our peripheral has manufacturing data!
        if let manufacturerData = advertisementData["kCBAdvDataManufacturerData"] as? Data {
            assert(manufacturerData.count == (2 + 2 + 6))
            
            let allocator = ByteBufferAllocator()
            var buf: ByteBuffer! = nil
            buf = allocator.buffer(capacity: manufacturerData.count)
            buf.writeBytes(Array(manufacturerData))
            
            let companyID: UInt16 = buf.readInteger(endianness: .little)!
            print("companyID", String(format: "%04X", companyID))
            
            let platformID: UInt16 = buf.readInteger(endianness: .little)!
            print("platformID", String(format: "%04X", platformID))
            
            let setupCode: String = buf.readString(length: 6)!
            print("setupCode: \(setupCode)")
            
            return (companyID, platformID, setupCode )
        }
        
        assert( false )
        //throw "No manufacturing data"
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {

        do {
            guard let name = peripheral.name else { return }
            
            if name.contains(bleName) {
                do {
                    let (companyID, platformID, setupCode) = try getManufacturingData( advertisementData: advertisementData )
                    
                    //check the companyID ?
                    assert(companyID == 0x1234)
                    assert(platformID == 0x0020)
                }
                catch {
                    
                }
                
                if( self.bleState == .lookingForDevice ) {
                    self.peripheral = peripheral
        
                    self.centralManager.connect(self.peripheral!)
                    self.updateState(state: .connectingToDevice)
                }
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("didConnect(\(peripheral))")
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }
}



extension ParticleBLE: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: Error?) {
        print("didDiscoverIncludedServicesFor(\(service)")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        print("didDiscoverCharacteristicsFor(\(service)")
        
        for c in service.characteristics! {
            print(c)
            
            switch c.uuid {
                case rxUUID:
                    print("got rx")
                    rxCharacteristic = c

                case txUUID:
                    print("got tx")
                    txCharacteristic = c
                
                case versionUUID:
                    print("got version")
                    versionCharacteristic = c
                
                default:
                    break
            }
        }
        
        if versionCharacteristic != nil {
            //read the version
            peripheral.readValue(for: versionCharacteristic!)
            if bleState == .connectingToDevice {
                self.updateState(state: .connectedAndWaitingForVersion)
            }
        }
        
        if txCharacteristic != nil {
            peripheral.setNotifyValue(true, for: txCharacteristic!)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        print("didDiscoverServices(\(String(describing: error))")
        for s in peripheral.services! {
            peripheral.discoverCharacteristics(nil, for: s)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        print("didUpdateValueFor(\(characteristic)")
        
        if characteristic.uuid == versionUUID {
            print("Version Data: \(characteristic.value![0])")
            
            //we should check the version above, but for now assume its 2
            if bleState == .connectedAndWaitingForVersion {
                self.updateState(state: .connectedAndRunning)
            }
        }
        else if characteristic.uuid == txUUID {
            //decode
            if let data = characteristic.value {
                let (messageValid, receivedMsg) = decodePacket(buffer: Array(data))

                if messageValid {
                    //get request type
                    let type = reqIDToTypeDict[receivedMsg!.reqID]
                    
                    if type == ECHO_REQUEST_TYPE {
                        //echo
                        let str = String(decoding: receivedMsg!.payload, as: UTF8.self)
                        print("Received echo: \(str)")
                        
                    } else if type == SCAN_NETWORKS_TYPE {
                        do {
                            let scannedNetworks: Particle_Ctrl_Wifi_ScanNetworksReply = try Particle_Ctrl_Wifi_ScanNetworksReply(serializedData: Data(receivedMsg!.payload))
                            
                            //print out what we found
                            for network in scannedNetworks.networks {
                                print("\(network.ssid) \(network.rssi)")
                            }
                            
                            self.lastWifiAPsSeen = scannedNetworks.networks
                        }
                        catch {
                            
                        }
                        
                        informDelegates()
                    } else if type == JOIN_KNOWN_NETWORK_TYPE {
                        do {
                            let joinNetworkReply: Particle_Ctrl_Wifi_JoinNewNetworkReply = try Particle_Ctrl_Wifi_JoinNewNetworkReply(serializedData: Data(receivedMsg!.payload))
                        }
                        catch {
                            
                        }

                        informDelegates()
                    } else if type == GET_CURRENT_NETWORK_TYPE {
                        do {
                            let currentNetworkReply: Particle_Ctrl_Wifi_GetCurrentNetworkReply = try Particle_Ctrl_Wifi_GetCurrentNetworkReply(serializedData: Data(receivedMsg!.payload))
                            
                            currentConnectedAP = currentNetworkReply
                        }
                        catch {
                            
                        }

                        informDelegates()
                    }
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        print("didWriteValueFor(\(characteristic)")
    }
    
    func requestWiFiAPs() {
        sendPacket(type: SCAN_NETWORKS_TYPE, data: [] )
    }
    
    func requestJoinWiFiNetwork(network: Particle_Ctrl_Wifi_ScanNetworksReply.Network, password: String) {
        var joinNetworkRequest = Particle_Ctrl_Wifi_JoinNewNetworkRequest()
        
        joinNetworkRequest.ssid = network.ssid
        joinNetworkRequest.security = network.security
        joinNetworkRequest.credentials.password = password
        joinNetworkRequest.credentials.type = .password
        joinNetworkRequest.bssid = network.bssid

        do {
            try sendPacket(type: JOIN_KNOWN_NETWORK_TYPE, data: Array(joinNetworkRequest.serializedData()) )
        }
        catch {
            
        }
    }
    
    func requestCurrentNetwork() {
        sendPacket(type: GET_CURRENT_NETWORK_TYPE, data: [] )
    }
    
    func requestEcho() {
        //send a test packet
        let string = "hello"
        let dataToSend: [UInt8] = Array(string.utf8)
        
        sendPacket(type: ECHO_REQUEST_TYPE, data: dataToSend )
    }
    
    func sendPacket(type: UInt16, data: [UInt8]) {
        
        let reqID: UInt16 = nextReqID
        nextReqID += 1
        reqIDToTypeDict[reqID] = type

        print("Send packet: \(reqID), \(type), \(data.count)")
        
        let reserved: UInt16 = 0
        
        let allocator = ByteBufferAllocator()
        var buf: ByteBuffer! = nil
        
        buf = allocator.buffer(capacity: data.count + REQUEST_PACKET_OVERHEAD)
        buf.writeInteger(UInt16(data.count), endianness: .little)
        buf.writeInteger(reqID, endianness: .little)
        buf.writeInteger(type, endianness: .little)
        buf.writeInteger(reserved, endianness: .little)
        buf.writeBytes(data)
        
        peripheral?.writeValue(Data(buf.getBytes(at: 0, length: buf.readableBytes) ?? []), for: rxCharacteristic!, type: .withoutResponse)
    }
    
    func decodePacket(buffer: [UInt8]) -> ( messageOK: Bool, receivedMsg: Message? ) {
        print("decodePacket \(buffer.count)")

        let startPacket: Bool = (receivingData == nil)
        
        var workingBuffer: [UInt8] = buffer
        
        if startPacket {
            //get the header etc...
            let allocator = ByteBufferAllocator()
            var buf: ByteBuffer! = nil
            buf = allocator.buffer(capacity: buffer.count)
            buf.writeBytes(buffer)
            
            let dataLength: UInt16 = buf.readInteger(endianness: .little)!
            let reqID: UInt16 = buf.readInteger(endianness: .little)!
            let _: UInt16 = buf.readInteger(endianness: .little)!
            let _: UInt16 = buf.readInteger(endianness: .little)!
            
            //free the buf above?
            
            //remove the first 8 bytes from the buffer
            workingBuffer = Array(workingBuffer[REQUEST_PACKET_OVERHEAD...])
            
            //create the receiving buffer
            var recBuf: ByteBuffer! = nil
            recBuf = allocator.buffer(capacity: Int(dataLength))

            receivingData = ReceivingData(reqID: reqID, dataLength: dataLength, buf: recBuf)
        }

        //write the received data in to the buffer
        receivingData!.buf.writeBytes(workingBuffer)
        
        //message?
        var returnMessage: Message? = nil
        
        //anything left to receive?
        let bytesLeftToReceive = receivingData!.dataLength - UInt16(receivingData!.buf.readableBytes)
        
        print("Receive packet: \(bytesLeftToReceive)")
        
        //reset the buffer if nothing left to received
        if bytesLeftToReceive == 0 {
            returnMessage = Message(reqID: receivingData!.reqID, payload: receivingData!.buf.getBytes(at: 0, length: receivingData!.buf.readableBytes) ?? [])
            receivingData = nil
        }

        return ( bytesLeftToReceive == 0, returnMessage )
    }
}


extension Data {
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
    }
    
    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let hexDigits = Array((options.contains(.upperCase) ? "0123456789ABCDEF" : "0123456789abcdef").utf16)
        var chars: [unichar] = []
        chars.reserveCapacity(2 * count)
        for byte in self {
            chars.append(hexDigits[Int(byte / 16)])
            chars.append(hexDigits[Int(byte % 16)])
        }
        return String(utf16CodeUnits: chars, count: chars.count)
    }
}
