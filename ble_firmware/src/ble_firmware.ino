#include "Particle.h"

// This app sets up custom BLE setup service UUIDs and puts the device
// in permanent provisioning mode

SYSTEM_MODE(SEMI_AUTOMATIC);
SerialLogHandler logHandler(115200, LOG_LEVEL_ALL);
STARTUP(System.enableFeature(FEATURE_DISABLE_LISTENING_MODE));

const char* serviceUuid = "6E400021-B5A3-F393-E0A9-E50E24DCCA9E";
const char* rxUuid = "6E400022-B5A3-F393-E0A9-E50E24DCCA9E";
const char* txUuid = "6E400023-B5A3-F393-E0A9-E50E24DCCA9E";
const char* versionUuid = "6E400024-B5A3-F393-E0A9-E50E24DCCA9E";

void ble_prov_mode_handler(system_event_t evt, int param) {
    if (param == ble_prov_mode_connected) {
        Log.info("BLE Event detected: ble_prov_mode_connected");
    }
    if (param == ble_prov_mode_disconnected) {
        Log.info("BLE Event detected: ble_prov_mode_disconnected");
    }
    if (param == ble_prov_mode_handshake_failed) {
        Log.info("BLE Event detected: ble_prov_mode_handshake_failed");
    }
    if (param == ble_prov_mode_handshake_done) {
        Log.info("BLE Event detected: ble_prov_mode_handshake_done");
    }
}

void nw_creds_handler(system_event_t evt, int param) {
    if (param == network_credentials_added) {
        Log.info("BLE Event detected: network_crendetials_added");
    }
}

void setup() {
    LOG(TRACE, "BLE Prov test app - startup");

    // ---------System Events---------
    System.on(ble_prov_mode, ble_prov_mode_handler);
    System.on(network_credentials, nw_creds_handler);
    
    System.setControlRequestFilter(SystemControlRequestAclAction::ACCEPT);

    // ---------Provisioning Service and Characteristic UUIDs---------
    // Provisioning UUIDs must be set before initialising BLE for the first time
    // Even better to call in STARTUP()
    BLE.setProvisioningSvcUuid(serviceUuid);
    BLE.setProvisioningTxUuid(txUuid);
    BLE.setProvisioningRxUuid(rxUuid);
    BLE.setProvisioningVerUuid(versionUuid);
    
    // ---------Setup device name---------
    BLE.setDeviceName("aabbccdd", 8);

    // ---------Set company ID---------
    BLE.setProvisioningCompanyId(0x1234);

    // ---------BLE provisioning mode---------
    BLE.provisioningMode(true);
    LOG(TRACE, "BLE prov mode status: %d", BLE.getProvisioningStatus());
    // To exit provisioning mode -> BLE.provisioningMode(false);
}

void loop() {
}