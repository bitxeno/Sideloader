module install;

import slf4d;
import slf4d.default_provider;

import std.range;
import std.string;
import std.array;
import std.conv;

import argparse;
import progress;

import imobiledevice;

import sideload;
import sideload.application;

import cli_frontend;

@(Command("install").Description("Install an application on the device (renames the app, register the identifier, sign and install automatically)."))
struct InstallCommand
{
    mixin LoginCommand;

    @(PositionalArgument(0, "app path").Description("The path of the IPA file to sideload."))
    string appPath;

    @(NamedArgument("udid").Description("UDID of the device (if multiple are available)."))
    string udid = null;
    
    @(NamedArgument("singlethread").Description("Run the signature process on a single thread. Sacrifices speed for more consistency."))
    bool singlethreaded;

    @(NamedArgument("q", "quiet").Description("Enable quiet mode"))
    bool quietMode;
    

    int opCall()
    {
        Application app = openApp(appPath);

        auto log = getLogger();

        string configurationPath = systemConfigurationPath();
        log.infoF!"Configuration path: %s"(configurationPath);
        scope provisioningData = initializeADI(configurationPath);
        scope adi = provisioningData.adi;
        scope akDevice = provisioningData.device;

        auto appleAccount = login(akDevice, adi, quietMode);

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
        sideloadFull(configurationPath, device, appleAccount, app, (percent, action) {
            printProgress(percent, action);
        }, !singlethreaded);
        progressBar.finish();

        return 0;
    }

    void printProgress(double percent, string message)
    {
        auto log = getLogger();
        const width = 32;
        const process_width = 3;
        const bar_suffix = "| ";
        const fill = "#";
        const empty_fill = " ";
        size_t filled_length = cast(size_t)(percent * width);
        size_t empty_length = width - filled_length;
        string bar = join(repeat(fill, filled_length), "");
        string empty = join(repeat(empty_fill, empty_length), "");
        size_t process = cast(int)(percent * 100);
        size_t process_filled_length = process_width - to!string(process).length;
        string process_filled = join(repeat(empty_fill, process_filled_length), "");
        log.infoF!"%s%s%s%d/%d%s %s"(bar, empty, bar_suffix, process, 100, process_filled, message);
    }
}
