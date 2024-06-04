module device;

import std.algorithm;
import std.array;
import std.exception;
import std.stdio;
import std.sumtype;
import std.typecons;

import slf4d;
import slf4d.default_provider;

import argparse;

import server.developersession;

import cli_frontend;

@(Command("device").Description("Manage devcies."))
struct DeviceCommand
{
    int opCall()
    {
        return cmd.match!(
                (ListDevices cmd) => cmd()
        );
    }

    @SubCommands
    SumType!(ListDevices) cmd;
}

@(Command("list").Description("List devcies."))
struct ListDevices
{
    mixin LoginCommand;

    int opCall()
    {
        auto log = getLogger();

        string configurationPath = systemConfigurationPath();

        scope provisioningData = initializeADI(configurationPath);
        scope adi = provisioningData.adi;
        scope akDevice = provisioningData.device;

        auto appleAccount = login(akDevice, adi);

        if (!appleAccount) {
            return 1;
        }

        writeln("Devices:");
        auto teams = appleAccount.listTeams().unwrap();
        foreach (team; teams) {
            auto devices = appleAccount.listDevices!iOS(team).unwrap();
            foreach (device; devices) {
                writefln!" - `%s`, with udid `%s` in team `%s`."(device.name, device.deviceNumber, team.name);
            }
        }

        return 0;
    }
}
