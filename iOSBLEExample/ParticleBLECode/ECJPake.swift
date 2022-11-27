//
//  ECJPake.swift
//  iOSBLEExample
//
//  Created by Nick Lambourne on 10/20/22.
//

import Foundation
import libmbedtls

//The JPAKE sequence is as follows:
// Round 1:
// - The client (this iOS library) sends down an initial round to the server (the device)
// - The server ingests this and then sends a reply back to the client
// Round 2
// - After sending the initial round back to the client, the server immediatly seconds a second round to the server
// - The client ingests this and then sends the response back to the server
// Confirmation
// - The client calculates the shared secret and a confirmation code, then sends these down to the server
// - The server calculates the shared secret as well and checks if it matches the confirmation code that was sent by the client
// - The server then calculates its own confirmation packet, using its own ongoing hash and sends to the client
// - The client checks this received confirmation
//
// After this, both sides have a shared secret
// - The server and the client initialize their AES CCM encryption engine with the share secrets

public protocol ecJPAKETLSDelegate {
    func handshakeCompleted()
}

public class ecJPAKE {

    enum State: String, Codable {
        case idle
        case read_round_1
        case write_round_1
        case read_round_2
        case write_round_2
        case read_confirm
        case write_confirm
        case done
        case failed
    }
    var state: State = .idle
    
    enum Role: String, Codable {
        case client
        case server
    }
    
    public var delegate: ecJPAKETLSDelegate?
    
    private var jpakeContextAlloc: UnsafeMutablePointer<mbedtls_ecjpake_context>?
    private var counterRandomByteGeneratorAlloc: UnsafeMutablePointer<mbedtls_ctr_drbg_context>?
    private var entropyAlloc: UnsafeMutablePointer<mbedtls_entropy_context>?
    private var aesAlloc: UnsafeMutablePointer<mbedtls_ccm_context>?

    //default to client
    var role: Role = .client
    
    var hash = Sha256()
    
    let MAX_HANDSHAKE_PAYLOAD_SIZE: Int = 512;

    var sessionSecret: [UInt8] = []
    var confirmationKey: [UInt8] = []

    // Size of the cipher's key in bytes
    let AES_CCM_KEY_SIZE: Int = 16

    // Size of the authentication field in bytes
    let AES_CCM_TAG_SIZE: Int = 8

    // Total size of the nonce in bytes
    let AES_CCM_NONCE_SIZE: Int = 12

    // Size of the fixed part of the nonce in bytes
    let AES_CCM_FIXED_NONCE_SIZE: Int = 8
    
    //share secret size
    let JPAKE_SHARED_SECRET_SIZE: Int = 32

    //nonces
    var reqCount: UInt32 = 0
    var repCount: UInt32 = 0
    
    var reqNonce: [UInt8] = []
    var repNonce: [UInt8] = []
    
    init() {
        jpakeContextAlloc = UnsafeMutablePointer<mbedtls_ecjpake_context>.allocate(capacity: 1)
        counterRandomByteGeneratorAlloc = UnsafeMutablePointer<mbedtls_ctr_drbg_context>.allocate(capacity: 1)
        entropyAlloc = UnsafeMutablePointer<mbedtls_entropy_context>.allocate(capacity: 1)
        aesAlloc = UnsafeMutablePointer<mbedtls_ccm_context>.allocate(capacity: 1)
        
        mbedtls_ecjpake_init(jpakeContextAlloc!)
        mbedtls_ctr_drbg_init(counterRandomByteGeneratorAlloc!)
        mbedtls_entropy_init(entropyAlloc!)
        mbedtls_ccm_init(aesAlloc!)
    }
    
    func initialize(role: Role, sharedSecret: [UInt8]) throws {
        self.role = role
        
        let sharedSecretPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: sharedSecret.count)
        sharedSecretPointer.initialize(from: sharedSecret, count: sharedSecret.count)
        
        var ret = mbedtls_ecjpake_setup(jpakeContextAlloc!, role == .client ? MBEDTLS_ECJPAKE_CLIENT : MBEDTLS_ECJPAKE_SERVER, MBEDTLS_MD_SHA256, MBEDTLS_ECP_DP_SECP256R1, sharedSecretPointer, sharedSecret.count)
        assert( ret == 0 )
        
        sharedSecretPointer.deinitialize(count: sharedSecret.count)
        sharedSecretPointer.deallocate()
        
        //entropy only needed on the client side
        ret = mbedtls_ctr_drbg_seed(counterRandomByteGeneratorAlloc!, mbedtls_entropy_func, entropyAlloc!, nil, 0)
        assert( ret == 0 )
    
        //round one is initialized by the client, so the server starts of listening only
        if role == .server {
            state = .read_round_1
        }
        else {
            state = .write_round_1
        }

        //start my hash!
        hash.start()
    }
    
    func registerDelegate( delegate: ecJPAKETLSDelegate ) {
        self.delegate = delegate
    }

    func informDelegates() {
        if delegate != nil {
            delegate!.handshakeCompleted()
        }
    }
    
    func dumpCurrentHash(name: String) {
        let currentPacketHash = Sha256()
        currentPacketHash.start() //unclear if this is needed!
        currentPacketHash.copyFrom(src: hash )
        let interimPacketHash = currentPacketHash.finish()
        print("dumpCurrentHash: " + name)
        print(interimPacketHash)
    }

    deinit {
        jpakeContextAlloc!.deallocate()
        counterRandomByteGeneratorAlloc!.deallocate()
        entropyAlloc!.deallocate()
        aesAlloc!.deallocate()
    }
    
    func isWriteState( state: State ) -> Bool {
        return state == .write_confirm || state == .write_round_1 || state == .write_round_2
    }
    
    func getHandshake() -> [UInt8]? {
        
        if isWriteState( state: state ) {
            var out: [UInt8] = []
            
            print(self.role.rawValue + " getHandshake: \(state.rawValue)")
            
            if state == .write_confirm {
                
                if role == .client {
                    //if I am the client, calculate my version of the shared secret here and store
                    (self.sessionSecret, self.confirmationKey) = calculateSessionSecretAndConfirmationKeys()
                    
                    //clone the current hash and finialize it
                    let currentPacketHash = Sha256()
                    currentPacketHash.start() //unclear if this is needed!
                    currentPacketHash.copyFrom(src: hash )
                    let interimPacketHash = currentPacketHash.finish()

                    //create the hmac confirmation message
                    let hmac = HMACSha256()
                    hmac.start(key: confirmationKey)
                    hmac.update(data: Array<UInt8>("KC_1_U".utf8))
                    hmac.update(data: Array<UInt8>("client".utf8))
                    hmac.update(data: Array<UInt8>("server".utf8))
                    hmac.update(data: interimPacketHash)
                    let confirmationPacket = hmac.finish()

                    out = confirmationPacket
                    
                    //keep my hash up to date
                    hash.update(data: out)
                    dumpCurrentHash(name: "write confirm")

                    state = .read_confirm
                }
                else {
                    let packetHash = hash.finish()
                    
                    //create the hmac confirmation message
                    let hmac = HMACSha256()
                    hmac.start(key: confirmationKey)
                    hmac.update(data: Array<UInt8>("KC_1_U".utf8))
                    hmac.update(data: Array<UInt8>("client".utf8))
                    hmac.update(data: Array<UInt8>("server".utf8))
                    hmac.update(data: packetHash)
                    
                    out = hmac.finish()

                    state = .done
                    
                    initAESCCM()
                    
                    //inform of success!
                    informDelegates();
                }
                
            } else {
                var outTmp = [UInt8](repeating: 0xFF, count: MAX_HANDSHAKE_PAYLOAD_SIZE)
                
                let uint8Pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: MAX_HANDSHAKE_PAYLOAD_SIZE)
                uint8Pointer.initialize(from: &outTmp, count: MAX_HANDSHAKE_PAYLOAD_SIZE)
                let writtenBytes = UnsafeMutablePointer<Int>.allocate(capacity: 1)
                writtenBytes.initialize(to: 0)
                
                if state == .write_round_1 {
                    let ret = mbedtls_ecjpake_write_round_one(jpakeContextAlloc!, uint8Pointer, MAX_HANDSHAKE_PAYLOAD_SIZE, writtenBytes, mbedtls_ctr_drbg_random, counterRandomByteGeneratorAlloc!)
                    assert( ret == 0)
                    
                    if role == .server {
                        state = .write_round_2
                    }
                    else {
                        state = .read_round_1
                    }
                } else if state == .write_round_2 {
                    let ret = mbedtls_ecjpake_write_round_two(jpakeContextAlloc!, uint8Pointer, MAX_HANDSHAKE_PAYLOAD_SIZE, writtenBytes, mbedtls_ctr_drbg_random, counterRandomByteGeneratorAlloc!)
                    assert( ret == 0)
                    
                    if role == .server {
                        state = .read_round_2
                    }
                    else {
                        state = .write_confirm
                    }
                } else {
                    assert(false)
                }
                
                out = Array(UnsafeBufferPointer(start: uint8Pointer, count: writtenBytes.pointee))
                
                uint8Pointer.deinitialize(count: MAX_HANDSHAKE_PAYLOAD_SIZE)
                uint8Pointer.deallocate()
                
                writtenBytes.deinitialize(count: 1)
                writtenBytes.deallocate()
                
                hash.update(data: out)
                dumpCurrentHash(name: "write round")
            }
            
            return out
        }
        else {
            //read states don't have anything to send yet
            return nil
        }
    }

    func handleHandshake(packet: [UInt8]) {
        print(self.role.rawValue + " handleHandshake: \(state.rawValue)")
        
        if !isWriteState( state: state ) {
            
            if state == .read_confirm {
                
                if role == .server {
                    //if I am the server, calculate my version of the shared secret here and store as well
                    (self.sessionSecret, self.confirmationKey) = calculateSessionSecretAndConfirmationKeys()
                    
                    //clone the current hash and finialize it
                    
                    let currentPacketHash = Sha256()
                    currentPacketHash.copyFrom(src: hash )
                    let interimPacketHash = currentPacketHash.finish()
                    
                    dumpCurrentHash(name: "read confirm PRE")
                    
                    //create the hmac confirmation message
                    let hmac = HMACSha256()
                    hmac.start(key: confirmationKey)
                    hmac.update(data: Array<UInt8>("KC_1_U".utf8))
                    hmac.update(data: Array<UInt8>("client".utf8))
                    hmac.update(data: Array<UInt8>("server".utf8))
                    hmac.update(data: interimPacketHash)
                    let confirmationPacket = hmac.finish()
                    
                    assert( packet == confirmationPacket )
                    
                    hash.update(data: packet)
                    dumpCurrentHash(name: "read confirm")
                    
                    state = .write_confirm
                }
                else {
                    dumpCurrentHash(name: "read confirm")
                    
                    let currentPacketHash = Sha256()
                    currentPacketHash.copyFrom(src: hash )
                    let interimPacketHash = currentPacketHash.finish()
                    
                    //create the hmac confirmation message
                    let hmacConfirmation = HMACSha256()
                    hmacConfirmation.start(key: confirmationKey)
                    hmacConfirmation.update(data: Array<UInt8>("KC_1_U".utf8))
                    hmacConfirmation.update(data: Array<UInt8>("client".utf8))
                    hmacConfirmation.update(data: Array<UInt8>("server".utf8))
                    hmacConfirmation.update(data: interimPacketHash)
                    let confirmationPacket = hmacConfirmation.finish()
                    
                    //assert( packet == confirmationPacket )
                    
                    state = .done
                    
                    initAESCCM()
                    
                    //inform of success!
                    informDelegates();
                }
                
            } else {
                
                var packetCopy = packet
                
                let uint8Pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: packet.count)
                uint8Pointer.initialize(from: &packetCopy, count: packet.count)
                
                if state == .read_round_1 {
                    let ret = mbedtls_ecjpake_read_round_one(jpakeContextAlloc!, uint8Pointer, packet.count)
                    assert(ret == 0)
                    
                    if role == .server {
                        state = .write_round_1
                    }
                    else {
                        state = .read_round_2
                    }
                } else if state == .read_round_2 {
                    let ret = mbedtls_ecjpake_read_round_two(jpakeContextAlloc!, uint8Pointer, packet.count)
                    assert(ret == 0)
                    
                    if role == .server {
                        state = .read_confirm
                    }
                    else {
                        state = .write_round_2
                    }
                } else {
                    assert(false)
                }
                
                uint8Pointer.deinitialize(count: packet.count)
                uint8Pointer.deallocate()
                
                hash.update(data: packet)
            }
        }
    }
    
    func calculateSessionSecretAndConfirmationKeys() -> (sharedSecret: [UInt8], confirmationKey: [UInt8]) {
        let uint8Pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: JPAKE_SHARED_SECRET_SIZE)
        
        let writtenBytes = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        writtenBytes.initialize(to: 0)
        
        let ret = mbedtls_ecjpake_derive_secret(jpakeContextAlloc!, uint8Pointer, JPAKE_SHARED_SECRET_SIZE, writtenBytes, mbedtls_ctr_drbg_random, counterRandomByteGeneratorAlloc!)
        assert( ret == 0 )
        assert( writtenBytes.pointee == JPAKE_SHARED_SECRET_SIZE )
        
        let sharedSecret = Array(UnsafeBufferPointer(start: uint8Pointer, count: writtenBytes.pointee))
        
        uint8Pointer.deinitialize(count: JPAKE_SHARED_SECRET_SIZE)
        uint8Pointer.deallocate()
        
        writtenBytes.deinitialize(count: 1)
        writtenBytes.deallocate()
        
        //generate the confirmation key
        let confirmationKeyHash = Sha256()
        confirmationKeyHash.start()
        confirmationKeyHash.update(data: sharedSecret)
        confirmationKeyHash.update(data: Array<UInt8>("JPAKE_KC".utf8))
        let confirmationKey = confirmationKeyHash.finish()
        
        let sharedSecretHex = sharedSecret.map { String(format: "%02X", $0) }
        print(sharedSecretHex.joined(separator: ":"))
        
        let confirmationKeyHex = confirmationKey.map { String(format: "%02X", $0) }
        print(confirmationKeyHex.joined(separator: ":"))
        
        return (sharedSecret, confirmationKey)
    }
    
    func initAESCCM() {
        let uint8Pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: AES_CCM_KEY_SIZE)
        uint8Pointer.initialize(from: sessionSecret, count: AES_CCM_KEY_SIZE)
        
        // First AES_CCM_KEY_SIZE bytes of the shared secret are used as the session key for AES-CCM
        // encryption, next two blocks of AES_CCM_FIXED_NONCE_SIZE bytes each are used as fixed parts
        // of client and server nonces respectively
        let ret = mbedtls_ccm_setkey(aesAlloc!, MBEDTLS_CIPHER_ID_AES, uint8Pointer, (UInt32)(AES_CCM_KEY_SIZE * 8))
        assert( ret == 0 )
        
        uint8Pointer.deinitialize(count: AES_CCM_KEY_SIZE)
        uint8Pointer.deallocate()
        
        reqNonce = Array(sessionSecret[(AES_CCM_KEY_SIZE)...(AES_CCM_KEY_SIZE+AES_CCM_FIXED_NONCE_SIZE)-1])
        repNonce = Array<UInt8>(sessionSecret[(AES_CCM_KEY_SIZE+AES_CCM_FIXED_NONCE_SIZE)...(AES_CCM_KEY_SIZE+(AES_CCM_FIXED_NONCE_SIZE*2)-1)])
    }

    
    func genRequestNonce() -> [UInt8] {
        reqCount += 1
        
        let byteArray = withUnsafeBytes(of: reqCount) {
            Array($0)
        }
        
        let ret = byteArray + reqNonce
        assert( ret.count == AES_CCM_NONCE_SIZE )
        
        return ret
    }
    
    func genReplyNonce() -> [UInt8] {
        repCount += 1
        
        let byteArray = withUnsafeBytes(of: (repCount | 0x80000000)) {
            Array($0)
        }
        
        let ret = byteArray + repNonce
        assert( ret.count == AES_CCM_NONCE_SIZE )
        
        return ret
    }
    
    func encryptData(payload: [UInt8], additionalData: [UInt8]) -> (encryptedData: [UInt8], aesTag: [UInt8]) {
        let nonce = genRequestNonce()
        
        let payloadPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: payload.count)
        payloadPointer.initialize(from: payload, count: payload.count)
        
        let noncePointer = UnsafeMutablePointer<UInt8>.allocate(capacity: nonce.count)
        noncePointer.initialize(from: nonce, count: nonce.count)
        
        let additionalDataPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: additionalData.count)
        additionalDataPointer.initialize(from: additionalData, count: additionalData.count)
        
        let encryptedOutputPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: payload.count)
        
        let tagPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: AES_CCM_TAG_SIZE)

        let ret = mbedtls_ccm_encrypt_and_tag(aesAlloc!,payload.count,noncePointer,AES_CCM_NONCE_SIZE,additionalDataPointer,additionalData.count,payloadPointer,encryptedOutputPointer,tagPointer,AES_CCM_TAG_SIZE)
        assert( ret == 0 )
        
        let encryptedOuput = Array(UnsafeBufferPointer(start: encryptedOutputPointer, count: payload.count))
        let aesTag = Array(UnsafeBufferPointer(start: tagPointer, count: AES_CCM_TAG_SIZE))

        return (encryptedOuput, aesTag)
    }
    
    func decryptData(payload: [UInt8], additionalData: [UInt8], aesTag: [UInt8]) -> [UInt8] {
        let nonce = genReplyNonce()
        
        let payloadPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: payload.count)
        payloadPointer.initialize(from: payload, count: payload.count)
        
        let noncePointer = UnsafeMutablePointer<UInt8>.allocate(capacity: nonce.count)
        noncePointer.initialize(from: nonce, count: nonce.count)
        
        let additionalDataPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: additionalData.count)
        additionalDataPointer.initialize(from: additionalData, count: additionalData.count)
        
        let decryptedOutputPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: payload.count)
        
        let tagPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: AES_CCM_TAG_SIZE)
        tagPointer.initialize(from: aesTag, count: AES_CCM_TAG_SIZE)

        let ret = mbedtls_ccm_auth_decrypt(aesAlloc!,payload.count,noncePointer,AES_CCM_NONCE_SIZE,additionalDataPointer,additionalData.count,payloadPointer,decryptedOutputPointer,tagPointer,AES_CCM_TAG_SIZE)
        assert( ret == 0 )
        
        let decryptedOuput = Array(UnsafeBufferPointer(start: decryptedOutputPointer, count: payload.count))
    
        return decryptedOuput
    }
}



func ecjpake_test() {
    do {
        print("ecjpake_test")

        let key: [UInt8] = [UInt8]("0123456789ABCDE".utf8)
        
        let client = ecJPAKE()
        try client.initialize(role: .client, sharedSecret: key)
        
        let server = ecJPAKE()
        try server.initialize(role: .server, sharedSecret: key)
        
        print("initialized")
        
        //client to server round 1
        let clientRoundOne = client.getHandshake()
        server.handleHandshake(packet: clientRoundOne!)
        
        //server to client round 1
        let serverRoundOne = server.getHandshake()
        client.handleHandshake(packet: serverRoundOne!)
        
        
        //server to client round 2
        let serverRoundTwo = server.getHandshake()
        client.handleHandshake(packet: serverRoundTwo!)
        
        //client to server round 2
        let clientRoundTwo = client.getHandshake()
        server.handleHandshake(packet: clientRoundTwo!)
        
        
        //read confirm from client to server
        let clientWriteConfirm = client.getHandshake()
        server.handleHandshake(packet: clientWriteConfirm!)
        
        //write confirm from server to client
        let serverWriteConfirm = server.getHandshake()
        client.handleHandshake(packet: serverWriteConfirm!)
        
        print("jpake handshake complete")
        
        //server.initAESCCM()
        //client.initAESCCM()
        
        //sanity checks
        assert(server.sessionSecret == client.sessionSecret)
        assert(server.reqNonce == client.reqNonce)
        assert(server.reqNonce == client.reqNonce)

        let testData: [UInt8] = [UInt8]("You may say I'm a dreamer,But I'm not the only one".utf8)
        
        let additionalData: [UInt8] = [0,1]
        let( encData, aesTag ) = client.encryptData(payload: testData, additionalData: additionalData)
        let decyptedData = server.decryptData(payload: encData, additionalData: additionalData, aesTag: aesTag )
        
        assert( decyptedData == testData )
    }
    catch {
        
    }
}
