module sign;

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

@(Command("sign").Description("Sign an application bundle."))
struct SignCommand
{
    mixin LoginCommand;

    @(PositionalArgument(0, "app path").Description("The path of the IPA file to sign."))
    string appPath;

    @(PositionalArgument(1, "output app path").Description("The output path of the signed IPA bundle."))
    string outputPath;

    @(NamedArgument("udid").Description("UDID of the device (if multiple are available)."))
    string udid = null;

    @(NamedArgument("singlethread").Description("Run the signature process on a single thread. Sacrifices speed for more consistency."))
    bool singlethreaded;

    int opCall()
    {
        Application app = openApp(appPath);

        auto log = getLogger();

        string configurationPath = systemConfigurationPath();

        scope provisioningData = initializeADI(configurationPath);
        scope adi = provisioningData.adi;
        scope akDevice = provisioningData.device;

        auto appleAccount = login(akDevice, adi);

        if (!appleAccount) {
            return 1;
        }

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

        log.infoF!"Initiating connection the device (UUID: %s)"(udid);
        auto device = new iDevice(udid);
        Bar progressBar = new Bar();
        string message;
        progressBar.message = () => message;
        sideloadSign(configurationPath, device, appleAccount, app, outputPath, (progress, action) {
            message = action;
            progressBar.index = cast(int) (progress * 100);
            progressBar.update();
        }, !singlethreaded);
        progressBar.finish();

        return 0;
    }
}
