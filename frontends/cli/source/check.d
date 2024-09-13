module check;

import std.sumtype;

import slf4d;
import slf4d.default_provider;

import botan.pubkey.algo.rsa;

import argparse;

import imobiledevice;

import cli_frontend;

@(Command("check").Description("Check configuration."))
struct CheckCommand
{
    int opCall()
    {
        return cmd.match!(
                (CheckConfig cmd) => cmd(),
                (CheckAfc cmd) => cmd()
        );
    }

    @SubCommands
    SumType!(CheckConfig, CheckAfc) cmd;
}


@(Command("config").Description("Check current configuration environments."))
struct CheckConfig
{
    int opCall()
    {
        auto log = getLogger();

        string configurationPath = systemConfigurationPath();
        log.infoF!"configurationPath=%s"(configurationPath);
        scope provisioningData = initializeADI(configurationPath);
        scope adi = provisioningData.adi ;
        scope device = provisioningData.device;
        log.info("adi:");
        log.infoF!" provisioningPath=%s"(adi.provisioningPath );
        log.infoF!" identifier=%s"(adi.identifier);
        log.info("device:");
        log.infoF!" UUID=%s"(device.uniqueDeviceIdentifier);
        log.infoF!" clientInfo=%s"(device.serverFriendlyDescription);
        log.infoF!" identifier=%s"(device.adiIdentifier);
        log.infoF!" localUserUUID=%s"(device.localUserUUID);
  
        return 0;
    }
}

@(Command("afc").Description("Check afc service state."))
struct CheckAfc
{
    @(NamedArgument("udid").Description("UDID of the device (if multiple are available)."))
    string udid = null;

    int opCall()
    {
        auto log = getLogger();

        auto devices = iDevice.deviceList();
        string udid = this.udid;
        if (!udid) {
            if (devices.length == 1) {
                udid = devices[0].udid;
            } else {
                if (!devices.length) {
                    log.error("No device connected.");
                    return 1;
                }
                if (!this.udid) {
                    log.error("Multiple devices are connected. Please select one with --udid.");
                }
            }
        }

        auto device = new iDevice(udid);
        device.udid();

        scope lockdownClient = new LockdowndClient(device, "sideloader");
        scope afcService = lockdownClient.startService(AFC_SERVICE_NAME);
        scope afcClient = new AFCClient(device, afcService);
        string[] props;
        auto ret = afcClient.getFileInfo("PublicStaging", props);
        if (ret != AFCError.AFC_E_SUCCESS && ret != AFCError.AFC_E_OBJECT_NOT_FOUND) {
            log.infoF!"Check AFC error: %s"(ret);
            return 1;
        }
        log.info("SUCCESS!");

        return 0;
    }
}