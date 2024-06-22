module group;

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

@(Command("group").Description("Manage groups."))
struct GroupCommand
{
    int opCall()
    {
        return cmd.match!(
                (ListGroups cmd) => cmd(),
                (DeleteGroup cmd) => cmd()
        );
    }

    @SubCommands
    SumType!(ListGroups, DeleteGroup) cmd;
}

@(Command("list").Description("List groups."))
struct ListGroups
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

        writeln("Groups:");
        auto teams = appleAccount.listTeams().unwrap();
        foreach (team; teams) {
            auto groups = appleAccount.listApplicationGroups!iOS(team).unwrap();
            foreach (group; groups) {
                writefln!" - `%s`, with identifier `%s` and applicationGroup `%s` in team `%s`."(group.name, group.identifier, group.applicationGroup, team.name);
            }
        }

        return 0;
    }
}


@(Command("delete").Description("Delete an Group."))
struct DeleteGroup
{
    mixin LoginCommand;

    @(NamedArgument("team").Description("Team ID"))
    string teamId = null;

    @(PositionalArgument(0).Description("Application Group"))
    string applicationGroup;

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

        auto teams = appleAccount.listTeams().unwrap();

        if (teamId != null) {
            teams = teams.filter!((elem) => elem.teamId == teamId).array();
        }
        enforce(teams.length > 0, "No matching team found.");

        auto team = teams[0];

        auto groups = appleAccount.listApplicationGroups!iOS(team).unwrap();
        auto matchingGroup = groups.filter!((group) => group.applicationGroup == applicationGroup).array();

        if (matchingGroup.length == 0) {
            log.error("No matching Group found.");
            return 1;
        }

        enforce(matchingGroup.length == 1, "Multiple Group matched?? To prevent any issue, ignoring the request.");
        appleAccount.deleteApplicationGroup!iOS(team, matchingGroup[0].applicationGroup).unwrap();

        log.info("Done.");

        return 0;
    }
}