import Foundation
import CoreBluetooth

protocol ParticleBLEDelegate {
    func statusUpdated()
}

class ParticleBLE: NSObject {
    
    enum SetupState {
        case idle
        case waitingForUserInput
        case lookingForDevice
        case lookingForDeviceTimeout
        case connectingToDevice
        case connectingToDeviceTimeout
        case connectedAndWaitingForVersion
        case connectedAndRunning
    }
    var setupState: SetupState = .idle
    
    var deviceAdvertisingName = "aabbcc"
    var setupCode = "sdfsdf" //should read from the manufacturing data?
    var mobileSecret = "sdfsdf" //from the QR code

    var timer = Timer()
    var timerRunning: Bool = false
    var timerRunTime: Int = 0
    var bleScanning: Bool = false
    
    enum ParticleBLEState {
        case Inactive
        case Active
        case Passed
        case Failed
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
    
    //delegate list
    var delegates:[ParticleBLEDelegate] = []

    func startup() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
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
    
    func updateState( state: SetupState ) {
        
        print("updateState(\(state))")
        
        //gotta be a new state, right?
        assert(self.setupState != state)
        
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
        self.setupState = state
        
        //inform the delegates!
        informDelegates()
    }
    
    @objc func updateTimer() {
        timerRunTime += 1
        
        print("updateTimer\(timerRunTime)")

        switch self.setupState {
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

    func getManufacturingData( advertisementData: [String: Any] ) throws -> (match: Bool, companyID: UInt16, platformID: UInt16, setupCode: String) {

        //did we find our peripheral? our peripheral has manufacturing data!
        if let manufacturerData = advertisementData["kCBAdvDataManufacturerData"] as? Data {
            assert(manufacturerData.count >= (2 + 2 + 6))
            
            let companyID = UInt16(manufacturerData[0]) + UInt16(manufacturerData[1]) << 8
            print("companyID", String(format: "%04X", companyID))
            
            let platformID = UInt16(manufacturerData[2]) + UInt16(manufacturerData[3]) << 8
            print("platformID", String(format: "%04X", platformID))
            
            var setupCode = ""
            
            if let manufacturerDataString = advertisementData["kCBAdvDataManufacturerData"] as? String {
                
                let start = manufacturerDataString.index(manufacturerDataString.startIndex, offsetBy: 4)
                let end = manufacturerDataString.index(manufacturerDataString.startIndex, offsetBy: 9)
                let range = start...end
                let newString = String(manufacturerDataString[range])
                
                setupCode = newString
                print("setupCode", setupCode)
            }
            
            //in theory, check the company id or something?
            var match: Bool = true
            
            return (match, companyID, platformID, setupCode )
        }
        
        assert( false )
        //throw "No manufacturing data"
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {

        do {
            guard let name = peripheral.name else { return }
            
            if name.contains(deviceAdvertisingName) {
                do {
                    let (match, companyID, platformID, setupCode) = try getManufacturingData( advertisementData: advertisementData )
                }
                catch {
                    
                }
                
                if( self.setupState == .lookingForDevice ) {
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
            if setupState == .connectingToDevice {
                self.updateState(state: .connectedAndWaitingForVersion)
            }
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
            if setupState == .connectedAndWaitingForVersion {
                self.updateState(state: .connectedAndRunning)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        print("didWriteValueFor(\(characteristic)")
        
        if characteristic.uuid == txUUID {
            //decode
        }
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
