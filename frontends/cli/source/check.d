module check;

import slf4d;
import slf4d.default_provider;

import botan.pubkey.algo.rsa;

import argparse;
import progress;

import server.developersession;

import imobiledevice;

import sideload.application;
import sideload.certificateidentity;
import sideload.sign: sideloadSign = signFull;

import cli_frontend;

@(Command("check").Description("Check current environments."))
struct CheckCommand
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
