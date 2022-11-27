//
//  ParticleBLEProtocol.swift
//  iOSBLEExample
//
//  Created by Nick Lambourne on 11/27/22.
//

import Foundation
import NIOCore

//The structure of a packet sent / received from the device is as follows:
// Header
//  Bytes 0-1               : payload length (does not include the header) (plaintext)
//  Bytes 2-3               : request ID  (encrypted)
//  Bytes 3-4               : request type (encrypted)
//  Bytes 4-5               : RESERVED (encrypted)
//  Bytes 6+                : Payload (encrypted)
//  Bytes <last 8 bytes>    : AES Tag (plaintext)

//global security enable - has to match the define BLE_CHANNEL_SECURITY_ENABLED in device OS
//in all builds, this is true by default unless you explicitly built the firmware differently
let SUPPORT_SECURITY = true

protocol ParticleBLEProtocolStatusDelegate {
    func onStatusUpdated(protocolState: ParticleBLEProtocol.ProtocolState, interfaceState: ParticleBLE.State)
}

public class ParticleBLEProtocol : ParticleBLEStatusDelegate, ParticleBLEInterfaceDataDelegate, ecJPAKETLSDelegate {

    ///
    /// Defines, enums and structs

    enum ProtocolState: String, Codable {
        case disconnected
        case authorizing
        case connected
    }
    
    enum ParticleBLEProtocolError: Error {
        case failedToJoinNetwork
        case requestAlreadyInProgess
        case badMessageFromDevice
    }
    
    //this is the header for the BLE protocol
    let MESSAGE_HEADER_SIZE: Int = 2
    let REQUEST_HEADER_SIZE: Int = 6
    let REPLY_HEADER_SIZE: Int = 6
    
    //this is the overhead for the security layer for normal packets
    let SECURITY_PACKET_OVERHEAD: Int = 8
    
    let ECHO_REQUEST_TYPE: UInt16 = 1
    let SCAN_NETWORKS_TYPE: UInt16 = 506
    let JOIN_KNOWN_NETWORK_TYPE: UInt16 = 500
    let GET_CURRENT_NETWORK_TYPE: UInt16 = 505
    
    struct Message {
        var reqID: UInt16
        var payload: [UInt8]
    }
    
    struct ReceivingData {
        var dataLength: UInt16
        var buf: ByteBuffer!
    }
    
    ///
    /// Variables
    
    var protocolState: ProtocolState = .disconnected
    
    //security engine
    var ecjpake: ecJPAKE = ecJPAKE()
    var mobileSecret: String = ""
    
    var receivingData: ReceivingData? = nil
    
    var reqIDToTypeDict: [UInt16: UInt16] = [:]
    var nextReqID: UInt16 = 32 //start at an offset for no reason - just to make debugging easier
    
    var bleInterface: ParticleBLEInterfaceAbstract
    
    var wifiAPCompletionHandler: ((_ wifiAPs: [Particle_Ctrl_Wifi_ScanNetworksReply.Network]?, _ error: Error?) -> Void)? = nil
    var currentConnectedAPCompletionHandler: ((_ currentConnectedAP: Particle_Ctrl_Wifi_GetCurrentNetworkReply?, _ error: Error?) -> Void)? = nil
    var requestJoinNetworkCompletionHandler: ((_ error: Error?) -> Void)? = nil
    var requestEchoCompletionHandler: ((_ echoResponse: String?, _ error: Error?) -> Void)? = nil
    
    var statusDelegates:[ParticleBLEProtocolStatusDelegate] = []
    
    //a general purpose buffer allocator
    let allocator: ByteBufferAllocator

    ///
    /// Public Interface
    
    init(bleInterface: ParticleBLEInterfaceAbstract) {
        self.bleInterface = bleInterface
        self.allocator = ByteBufferAllocator()
        
        bleInterface.registerStatusDelegate(delegate: self)
        bleInterface.registerDataDelegate(delegate: self)
        ecjpake.registerDelegate(delegate: self)
    }

    func startup(bleName: String, mobileSecret: String, completionHandler: @escaping () -> Void) {
        self.mobileSecret = mobileSecret
        
        do {
            try ecjpake.initialize(role: .client, sharedSecret: [UInt8](mobileSecret.utf8))
        }
        catch {
            assert( false )
        }
        
        //start the BLE interface!
        bleInterface.startup(bleName: bleName) {
            completionHandler()
        }
    }
    
    func registerStatusDelegate( delegate: ParticleBLEProtocolStatusDelegate ) {
        statusDelegates.append( delegate )
    }
        
    func requestWiFiAPs( completionHandler: @escaping (_ wifiAPs: [Particle_Ctrl_Wifi_ScanNetworksReply.Network]?, _ error: Error?) -> Void) {
        //only 1 allowed at once
        if( self.wifiAPCompletionHandler == nil ) {
            //store for async callback
            self.wifiAPCompletionHandler = completionHandler
            
            sendPacket(type: SCAN_NETWORKS_TYPE, data: [] )
        } else {
            completionHandler(nil, ParticleBLEProtocolError.requestAlreadyInProgess )
        }
    }

    func requestJoinWiFiNetwork(network: Particle_Ctrl_Wifi_ScanNetworksReply.Network, password: String, completionHandler: @escaping (_ error: Error?) -> Void) {
        
        var joinNetworkRequest = Particle_Ctrl_Wifi_JoinNewNetworkRequest()
        
        joinNetworkRequest.ssid = network.ssid
        joinNetworkRequest.security = network.security
        joinNetworkRequest.credentials.password = password
        joinNetworkRequest.credentials.type = .password
        joinNetworkRequest.bssid = network.bssid
        
        //only 1 allowed at once
        if( self.requestJoinNetworkCompletionHandler == nil ) {
            //store for async callback
            self.requestJoinNetworkCompletionHandler = completionHandler
            
            do {
                try sendPacket(type: JOIN_KNOWN_NETWORK_TYPE, data: Array(joinNetworkRequest.serializedData()) )
            }
            catch {
                assert( false )
            }
        }
        else {
            completionHandler(ParticleBLEProtocolError.requestAlreadyInProgess )
        }
    }
    
    func requestCurrentNetwork( completionHandler: @escaping (_ currentConnectedAP: Particle_Ctrl_Wifi_GetCurrentNetworkReply?, _ error: Error?) -> Void) {
        //only 1 allowed at once
        if( self.currentConnectedAPCompletionHandler == nil ) {
            //store for async callback
            self.currentConnectedAPCompletionHandler = completionHandler
            
            sendPacket(type: GET_CURRENT_NETWORK_TYPE, data: [] )
        } else {
            completionHandler(nil, ParticleBLEProtocolError.requestAlreadyInProgess )
        }
    }
    
    func requestEcho(echo: String, completionHandler: @escaping (_ echoResponse: String?, _ error: Error?) -> Void) {
        //send a test packet
        let dataToSend: [UInt8] = Array(echo.utf8)
        
        //only 1 allowed at once
        if( self.requestEchoCompletionHandler == nil ) {
            //store for async callback
            self.requestEchoCompletionHandler = completionHandler
            
            sendPacket(type: ECHO_REQUEST_TYPE, data: dataToSend )
        }
        else {
            completionHandler(nil, ParticleBLEProtocolError.requestAlreadyInProgess )
        }
    }
    
    ///
    /// Private Interface

    public func handshakeCompleted() {
        //aha! we are finished
        protocolState = .connected
        
        informDelegatesOfStatusUpdate()
    }
    
    func receiveBuffer(buffer: [UInt8]) -> ( bytesConsumed: Int, completedBuffer: [UInt8]? ) {
        print("receiveBuffer \(buffer.count)")
        var bytesConsumed: Int = 0
        
        let startPacket: Bool = (receivingData == nil)
        
        if startPacket {
            //what is the packet size?
            let messageHeader = Array(buffer[...(MESSAGE_HEADER_SIZE-1)])
            let messageSize: UInt16 = UnsafePointer(messageHeader).withMemoryRebound(to: UInt16.self, capacity: 1) {
                $0.pointee
            }
            
            print("New receiveBuffer len (\(messageSize))" )

            var totalPacketSize = messageSize
            if protocolState == .authorizing {
                //just has a message header
                totalPacketSize += UInt16(MESSAGE_HEADER_SIZE)
            }
            else {
                assert( protocolState == .connected )

                totalPacketSize += UInt16(MESSAGE_HEADER_SIZE)
                totalPacketSize += UInt16(REPLY_HEADER_SIZE)

                if SUPPORT_SECURITY {
                    totalPacketSize += UInt16(SECURITY_PACKET_OVERHEAD)
                }
            }
            print("Total packet len (\(totalPacketSize))" )

            //create the receiving buffer
            //it contains the message header and the raw data
            var recBuf: ByteBuffer! = nil
            recBuf = allocator.buffer(capacity: Int(totalPacketSize))
            
            receivingData = ReceivingData(dataLength: totalPacketSize, buf: recBuf)
        }
        
        //anything left to receive?
        var bytesLeftToReceive: UInt16 = receivingData!.dataLength - UInt16(receivingData!.buf.readableBytes)
        print("Bytes left to receive: \(bytesLeftToReceive)")
        
        //how many bytes did we take?
        bytesConsumed += min( Int(bytesLeftToReceive), buffer.count )

        //write the received data in to the buffer, but only up to the amount we are expecting
        receivingData!.buf.writeBytes(Array(buffer[...(Int(bytesConsumed)-1)]))
        
        bytesLeftToReceive -= UInt16(bytesConsumed)

        //reset the buffer if nothing left to received
        if bytesLeftToReceive == 0 {
            let receivedData = receivingData!
            
            //reset the receiving buffer
            receivingData = nil

            return (bytesConsumed, receivedData.buf.getBytes(at: 0, length: receivedData.buf.readableBytes) ?? [])
        }

        return ( bytesConsumed, nil )
    }
    
    //call back from the
    func onDataReceived(data: [UInt8]) {
        var receivedBuffer = data
        
        while receivedBuffer.count > 0 {
            let (bytesConsumed, completedBuffer) = receiveBuffer(buffer: receivedBuffer)

            //advance the received buffer along
            receivedBuffer = Array(receivedBuffer[bytesConsumed...])
            
            if completedBuffer != nil {
                //if we are authorizing, run the process...
                if protocolState == .authorizing {
                    //strip off the message header 2 bytes
                    let bufferMinusMessageHeader = Array(completedBuffer![2...])
                    
                    //handle the packet from the device
                    ecjpake.handleHandshake(packet: Array(bufferMinusMessageHeader))
                    
                    //if the handshake is finished, lets start sending some protocol packets!
                    if ecjpake.state == .done {
                        protocolState = .connected
                    } else {
                        //send the next packet
                        var trySend: Bool = true

                        while trySend {
                            let handshake = ecjpake.getHandshake()
                            if handshake != nil {
                                sendSecurityPacket(data: handshake!)
                            }
                            else {
                                trySend = false
                            }
                        }
                    }
                }
                else {
                    let decodedMessage = decodePacket(buffer: completedBuffer!)
                    
                    //get request type that matches the message we sent
                    let type = reqIDToTypeDict[decodedMessage.reqID]
                    
                    if type == ECHO_REQUEST_TYPE {
                        //echo
                        let str = String(decoding: decodedMessage.payload, as: UTF8.self)
                        print("Received echo: \(str)")
                        
                        assert( requestEchoCompletionHandler != nil )
                        requestEchoCompletionHandler!(str, nil)
                        requestEchoCompletionHandler = nil
                        
                    } else if type == SCAN_NETWORKS_TYPE {
                        
                        var thisError: Error?
                        var scannedNetworks: Particle_Ctrl_Wifi_ScanNetworksReply?
                        
                        do {
                            scannedNetworks = try Particle_Ctrl_Wifi_ScanNetworksReply(serializedData: Data(decodedMessage.payload))
                            
                            //print out what we found
                            for network in scannedNetworks!.networks {
                                print("\(network.ssid) \(network.rssi)")
                            }
                        }
                        catch {
                            thisError = ParticleBLEProtocolError.badMessageFromDevice
                        }
                        
                        assert( wifiAPCompletionHandler != nil )
                        wifiAPCompletionHandler!(scannedNetworks!.networks, thisError)
                        wifiAPCompletionHandler = nil
                        
                    } else if type == JOIN_KNOWN_NETWORK_TYPE {
                        
                        var joinNetworkError: Error? = nil
                        
                        do {
                            let _: Particle_Ctrl_Wifi_JoinNewNetworkReply = try Particle_Ctrl_Wifi_JoinNewNetworkReply(serializedData: Data(decodedMessage.payload))
                            
                            //the return packet doesn't save it if connects, so we just have to check later on
                        }
                        catch {
                            joinNetworkError = ParticleBLEProtocolError.failedToJoinNetwork
                        }
                        
                        assert( requestJoinNetworkCompletionHandler != nil )
                        requestJoinNetworkCompletionHandler!(joinNetworkError)
                        requestJoinNetworkCompletionHandler = nil
                        
                    } else if type == GET_CURRENT_NETWORK_TYPE {
                        do {
                            let currentNetworkReply: Particle_Ctrl_Wifi_GetCurrentNetworkReply = try Particle_Ctrl_Wifi_GetCurrentNetworkReply(serializedData: Data(decodedMessage.payload))
                            
                            assert( currentConnectedAPCompletionHandler != nil )
                            currentConnectedAPCompletionHandler!(currentNetworkReply, nil)
                            currentConnectedAPCompletionHandler = nil
                        }
                        catch {
                            
                        }
                    }
                    
                    //remove the request type!
                    reqIDToTypeDict.removeValue(forKey: decodedMessage.reqID)
                }
            }
        }
    }
    
    func onStatusUpdated(state: ParticleBLE.State) {
        if state == .connected {
            if SUPPORT_SECURITY {
                protocolState = .authorizing

                //kick off the authorization flow!
                let handshake = ecjpake.getHandshake()
                if handshake != nil {
                    sendSecurityPacket(data: handshake!)
                }
            } else {
                protocolState = .connected
            }
        }
        else if state == .disconnected {
            protocolState = .disconnected
        }

        //inform all listeners
        informDelegatesOfStatusUpdate()
    }
    
    func informDelegatesOfStatusUpdate() {
        for d in statusDelegates {
            d.onStatusUpdated(protocolState: protocolState, interfaceState: bleInterface.state)
        }
    }
    
    func decodePacket(buffer: [UInt8]) -> Message {

        print("decodePacket \(buffer.count)")
        
        var workingBuffer = buffer
        
        if SUPPORT_SECURITY {
            //decrypt the packet
            let messageHeader: [UInt8] = Array(buffer[0...Int(MESSAGE_HEADER_SIZE-1)])
            let dataToDec: [UInt8] = Array(buffer[Int(MESSAGE_HEADER_SIZE)...Int(buffer.count - SECURITY_PACKET_OVERHEAD - 1)])
            let aesTag: [UInt8] = Array(buffer[Int(buffer.count - SECURITY_PACKET_OVERHEAD)...Int(buffer.count-1)])
            
            var decryptedData = ecjpake.decryptData(payload: dataToDec, additionalData: messageHeader, aesTag: aesTag)
            
            //re-assemble the decrypted message
            workingBuffer = messageHeader + decryptedData + aesTag
        }

        //get the packet as a bytebuffer
        var buf: ByteBuffer! = nil
        buf = allocator.buffer(capacity: workingBuffer.count)
        buf.writeBytes(workingBuffer)
        
        //read the message header!
        let messageLength: UInt16 = buf.readInteger(endianness: .little)!

        //read the reply/request header!
        let reqID: UInt16 = buf.readInteger(endianness: .little)!
        let result: UInt32 = buf.readInteger(endianness: .little)!

        print(result)

        return Message(reqID: reqID, payload: buf.getBytes(at: (MESSAGE_HEADER_SIZE+REPLY_HEADER_SIZE), length: Int(messageLength)) ?? [])
    }
    
    func sendSecurityPacket(data: [UInt8]) {
        var txBuf: ByteBuffer! = allocator.buffer(capacity: data.count + 2)
        
        var messageLength: UInt16 = UInt16(data.count)
        var messageHeader = withUnsafeBytes(of: &messageLength) { Array($0) }
        
        txBuf.writeBytes(messageHeader)
        txBuf.writeBytes(data)

        bleInterface.sendBuffer(buffer: txBuf.getBytes(at: 0, length: txBuf.readableBytes) ?? [])
    }
    
    func sendPacket(type: UInt16, data: [UInt8]) {

        //message header
        var bufMessagerHeader: ByteBuffer! = nil
        bufMessagerHeader = allocator.buffer(capacity: MESSAGE_HEADER_SIZE)
        bufMessagerHeader.writeInteger(UInt16(data.count), endianness: .little)
        
        //generated the request header and append the payload
        let reqID: UInt16 = nextReqID
        nextReqID += 1
        reqIDToTypeDict[reqID] = type
        let reserved: UInt16 = 0
        
        var bufRequestHeader: ByteBuffer! = nil
        bufRequestHeader = allocator.buffer(capacity: data.count + REQUEST_HEADER_SIZE)
        bufRequestHeader.writeInteger(reqID, endianness: .little)
        bufRequestHeader.writeInteger(type, endianness: .little)
        bufRequestHeader.writeInteger(reserved, endianness: .little)
        bufRequestHeader.writeBytes(data) //payload
        
        print("Send packet: \(reqID), \(type), \(data.count)")
        
        var txBufferLen = bufRequestHeader.readableBytes + MESSAGE_HEADER_SIZE
        
        if SUPPORT_SECURITY {
            txBufferLen += SECURITY_PACKET_OVERHEAD
        }
        
        var txBuf: ByteBuffer! = nil
        txBuf = allocator.buffer(capacity: txBufferLen)
        
        //message header
        let messageHeader = bufMessagerHeader.getBytes(at: 0, length: bufMessagerHeader.readableBytes) ?? []
        
        //write the new message
        txBuf.writeBytes(messageHeader)
        
        //encrypt the packet
        if SUPPORT_SECURITY {
            var (encryptedData, aesTag) = ecjpake.encryptData(payload: bufRequestHeader.getBytes(at: 0, length: bufRequestHeader.readableBytes) ?? [], additionalData: messageHeader)
            
            txBuf.writeBytes(encryptedData)
            txBuf.writeBytes(aesTag)
        } else {
            txBuf.writeBytes( bufRequestHeader.getBytes(at: 0, length: bufRequestHeader.readableBytes) ?? [])
        }
        
        bleInterface.sendBuffer(buffer: txBuf.getBytes(at: 0, length: txBuf.readableBytes) ?? [])
    }
}


//
//if SUPPORT_SECURITY {
//    var secureBuf: ByteBuffer! = nil
//    secureBuf = allocator.buffer(capacity: bufRequestHeader.readableBytes + MESSAGE_HEADER_PACKET_SIZE + SECURITY_PACKET_OVERHEAD)
//
//    //encrypt the packet
//    let messageHeader = bufMessagerHeader.getBytes(at: 0, length: bufMessagerHeader.readableBytes) ?? []
//    var (dataToEnc, aesTag) = ecjpake.encryptData(payload: bufRequestHeader.getBytes(at: 0, length: bufRequestHeader.readableBytes) ?? [], additionalData: messageHeader)
//
//    //write the new message
//    secureBuf.writeBytes(messageHeader)
//    secureBuf.writeBytes(dataToEnc)
//    secureBuf.writeBytes(aesTag)
//
//    sendBuffer(buffer: secureBuf.getBytes(at: 0, length: secureBuf.readableBytes) ?? [])
//}
//else {
//    var insecureBuffer: ByteBuffer! = nil
//    insecureBuffer = allocator.buffer(capacity: bufRequestHeader.readableBytes + MESSAGE_HEADER_PACKET_SIZE)
//
//    insecureBuffer.writeInteger(UInt16(data.count))
//    insecureBuffer.writeBytes( bufRequestHeader.getBytes(at: 0, length: bufRequestHeader.readableBytes) ?? [] )
//
//    sendBuffer(buffer: insecureBuffer.getBytes(at: 0, length: insecureBuffer.readableBytes) ?? [])
//}

