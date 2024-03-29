// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: internal.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/apple/swift-protobuf/

import Foundation
import SwiftProtobuf

// If the compiler emits an error on this type, it is because this file
// was generated by a version of the `protoc` Swift plug-in that is
// incompatible with the version of SwiftProtobuf to which you are linking.
// Please ensure that you are building against the same version of the API
// that was used to generate this file.
fileprivate struct _GeneratedWithProtocGenSwiftVersion: SwiftProtobuf.ProtobufAPIVersionCheck {
  struct _2: SwiftProtobuf.ProtobufAPIVersion_2 {}
  typealias Version = _2
}

struct Particle_Firmware_WifiConfig {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var networks: [Particle_Firmware_WifiConfig.Network] = []

  var unknownFields = SwiftProtobuf.UnknownStorage()

  struct Network {
    // SwiftProtobuf.Message conformance is added in an extension below. See the
    // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
    // methods supported on all messages.

    var ssid: String = String()

    var bssid: Data = Data()

    var security: Particle_Ctrl_Wifi_Security = .noSecurity

    var credentials: Particle_Ctrl_Wifi_Credentials {
      get {return _credentials ?? Particle_Ctrl_Wifi_Credentials()}
      set {_credentials = newValue}
    }
    /// Returns true if `credentials` has been explicitly set.
    var hasCredentials: Bool {return self._credentials != nil}
    /// Clears the value of `credentials`. Subsequent reads from it will return its default value.
    mutating func clearCredentials() {self._credentials = nil}

    var unknownFields = SwiftProtobuf.UnknownStorage()

    init() {}

    fileprivate var _credentials: Particle_Ctrl_Wifi_Credentials? = nil
  }

  init() {}
}

struct Particle_Firmware_CellularConfig {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var internalSim: Particle_Ctrl_Cellular_AccessPoint {
    get {return _internalSim ?? Particle_Ctrl_Cellular_AccessPoint()}
    set {_internalSim = newValue}
  }
  /// Returns true if `internalSim` has been explicitly set.
  var hasInternalSim: Bool {return self._internalSim != nil}
  /// Clears the value of `internalSim`. Subsequent reads from it will return its default value.
  mutating func clearInternalSim() {self._internalSim = nil}

  var externalSim: Particle_Ctrl_Cellular_AccessPoint {
    get {return _externalSim ?? Particle_Ctrl_Cellular_AccessPoint()}
    set {_externalSim = newValue}
  }
  /// Returns true if `externalSim` has been explicitly set.
  var hasExternalSim: Bool {return self._externalSim != nil}
  /// Clears the value of `externalSim`. Subsequent reads from it will return its default value.
  mutating func clearExternalSim() {self._externalSim = nil}

  var activeSim: Particle_Ctrl_Cellular_SimType = .invalidSimType

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _internalSim: Particle_Ctrl_Cellular_AccessPoint? = nil
  fileprivate var _externalSim: Particle_Ctrl_Cellular_AccessPoint? = nil
}

#if swift(>=5.5) && canImport(_Concurrency)
extension Particle_Firmware_WifiConfig: @unchecked Sendable {}
extension Particle_Firmware_WifiConfig.Network: @unchecked Sendable {}
extension Particle_Firmware_CellularConfig: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "particle.firmware"

extension Particle_Firmware_WifiConfig: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".WifiConfig"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "networks"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeRepeatedMessageField(value: &self.networks) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.networks.isEmpty {
      try visitor.visitRepeatedMessageField(value: self.networks, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Particle_Firmware_WifiConfig, rhs: Particle_Firmware_WifiConfig) -> Bool {
    if lhs.networks != rhs.networks {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Particle_Firmware_WifiConfig.Network: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = Particle_Firmware_WifiConfig.protoMessageName + ".Network"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "ssid"),
    2: .same(proto: "bssid"),
    3: .same(proto: "security"),
    4: .same(proto: "credentials"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self.ssid) }()
      case 2: try { try decoder.decodeSingularBytesField(value: &self.bssid) }()
      case 3: try { try decoder.decodeSingularEnumField(value: &self.security) }()
      case 4: try { try decoder.decodeSingularMessageField(value: &self._credentials) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    if !self.ssid.isEmpty {
      try visitor.visitSingularStringField(value: self.ssid, fieldNumber: 1)
    }
    if !self.bssid.isEmpty {
      try visitor.visitSingularBytesField(value: self.bssid, fieldNumber: 2)
    }
    if self.security != .noSecurity {
      try visitor.visitSingularEnumField(value: self.security, fieldNumber: 3)
    }
    try { if let v = self._credentials {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 4)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Particle_Firmware_WifiConfig.Network, rhs: Particle_Firmware_WifiConfig.Network) -> Bool {
    if lhs.ssid != rhs.ssid {return false}
    if lhs.bssid != rhs.bssid {return false}
    if lhs.security != rhs.security {return false}
    if lhs._credentials != rhs._credentials {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Particle_Firmware_CellularConfig: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".CellularConfig"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "internal_sim"),
    2: .standard(proto: "external_sim"),
    3: .standard(proto: "active_sim"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularMessageField(value: &self._internalSim) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._externalSim) }()
      case 3: try { try decoder.decodeSingularEnumField(value: &self.activeSim) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._internalSim {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._externalSim {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    if self.activeSim != .invalidSimType {
      try visitor.visitSingularEnumField(value: self.activeSim, fieldNumber: 3)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Particle_Firmware_CellularConfig, rhs: Particle_Firmware_CellularConfig) -> Bool {
    if lhs._internalSim != rhs._internalSim {return false}
    if lhs._externalSim != rhs._externalSim {return false}
    if lhs.activeSim != rhs.activeSim {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
