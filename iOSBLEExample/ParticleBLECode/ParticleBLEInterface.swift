//
//  ParticleBLE.swift
//  iOSBLEExample
//
//  Created by Nick Lambourne on 10/20/22.
//

import Foundation
import CoreBluetooth
import NIOCore

class ParticleBLE: ParticleBLEInterfaceAbstract {
    
    ///
    /// Variables
    ///

    var timer = Timer()
    var timerRunning: Bool = false
    var timerRunTime: Int = 0
    var bleScanning: Bool = false

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
    
    //device details
    var bleName: String = ""
    
    var startupCompletionHandler: (() -> Void)? = nil

    ///
    /// Public funcs
    ///
    
    //an explicit startup command is needed (vs an init) because this can prompt the user for permissions
    override func startup(bleName: String, completionHandler: @escaping () -> Void) {
        self.bleName = bleName
        centralManager = CBCentralManager(delegate: self, queue: nil)
        
        //store the completionHandler for when the BLE interface turns on.
        startupCompletionHandler = completionHandler
    }
    
    func startConnectionProcess() {
        updateState(state: .lookingForDevice)
    }
    
    override func disconnect() {
        if self.state == .connected {
            self.centralManager!.cancelPeripheralConnection(self.peripheral!)
            
            updateState(state: .lookingForDevice)
        }
    }

    ///
    /// Private functions
    ///

    private func updateState( state: State ) {
        
        print("updateState(\(state))")
        
        //gotta be a new state, right?
        assert(self.state != state)
        
        var runTimer: Bool = false
        var resetTimeout: Bool = false
        var scanBLE: Bool = false

        switch state {
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
            
            case .connected:
                resetTimeout = true
                runTimer = false
                scanBLE = false
            
            case .connectedButWaitingForVersion:
                resetTimeout = true
                runTimer = false
                scanBLE = false

            case .idle:
                resetTimeout = true
                runTimer = false
                scanBLE = false
            
            case .disconnected:
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
        self.state = state
        
        //inform the delegates!
        informDelegatesOfStatusUpdate(state: state)
    }
    
    @objc func updateTimer() {
        timerRunTime += 1
        
        print("updateTimer\(timerRunTime)")

        switch self.state {
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
    
    override func sendBuffer(buffer: [UInt8]) {
        let maxPacketSize: Int? = peripheral?.maximumWriteValueLength(for: .withoutResponse)
       
        var bufferSize = buffer.count
        var currentOffset = 0
        var currentMaxLimit = min( maxPacketSize!, bufferSize )
        
        print("BLE sendBuffer: \(buffer.count)")
        
        while bufferSize != 0 {
            
            print("BLE sendBuffer Chunk: \(currentOffset) \(currentMaxLimit)")
            
            peripheral?.writeValue(Data(buffer[currentOffset...(currentMaxLimit-1)]), for: rxCharacteristic!, type: .withoutResponse)
            
            let dataJustSent = (currentMaxLimit - currentOffset)
            bufferSize -= dataJustSent
            currentOffset += dataJustSent
            
            if bufferSize != 0 {
                let nextRound = (bufferSize > maxPacketSize! ? maxPacketSize! : bufferSize)
                currentMaxLimit = currentOffset + nextRound
            }
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
                if startupCompletionHandler != nil {
                    startupCompletionHandler!()
                    startupCompletionHandler = nil
                }
            @unknown default:
                print("central.state is .unknown")
        }
    }

    func getManufacturingData( advertisementData: [String: Any] ) throws -> (companyID: UInt16, platformID: UInt16, setupCode: String) {
        //did we find our peripheral? our peripheral has manufacturing data!
        
        var companyID: UInt16 = 0
        var platformID: UInt16 = 0
        var setupCode: String = ""
        
        if let manufacturerData = advertisementData["kCBAdvDataManufacturerData"] as? Data {
            assert(manufacturerData.count == (2 + 2 + 6))
            
            let allocator = ByteBufferAllocator()
            var buf: ByteBuffer! = nil
            buf = allocator.buffer(capacity: manufacturerData.count)
            buf.writeBytes(Array(manufacturerData))
            
            companyID = buf.readInteger(endianness: .little)!
            //print("companyID", String(format: "%04X", companyID))
            
            platformID = buf.readInteger(endianness: .little)!
            //print("platformID", String(format: "%04X", platformID))
            
            setupCode = buf.readString(length: 6)!
            //print("setupCode: \(setupCode)")
        }

        return (companyID, platformID, setupCode )
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {

        do {
            guard let name = peripheral.name else { return }
            
            if name.contains(bleName) {
                do {
                    //
                    let (companyID, _, _) = try getManufacturingData( advertisementData: advertisementData )
                    
                    //check the companyID - you should change this on a per product implementation
                    //these defaults are for Particle's tinker implementation
                    assert(companyID == 0x1234)
                    //assert(platformID == 0x0020)
                    //print(setupCode)
                }
                catch {
                    
                }
                
                if( self.state == .lookingForDevice ) {
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
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("didDisconnectPeripheral(\(peripheral))")
        updateState(state: .disconnected)
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
            if state == .connectingToDevice {
                self.updateState(state: .connectedButWaitingForVersion)
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
            
            //we could check the version above, but for now assume its 2
            if state == .connectedButWaitingForVersion {
                self.updateState(state: .connected)
            }
        }
        else if characteristic.uuid == txUUID {
            //decode
            if let data = characteristic.value {
                
                if state == .connected {
                    
                    informDelegatesOfDataAvailable(data: Array(data))
                    
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        print("didWriteValueFor(\(characteristic)")
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
