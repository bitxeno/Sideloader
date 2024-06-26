module certificate;

import std.algorithm;
import std.array;
import std.exception;
import std.stdio;
import std.sumtype;
import std.typecons;

import slf4d;
import slf4d.default_provider;

import botan.cert.x509.pkcs10;
import botan.filters.data_src;

import argparse;

import server.developersession;

import cli_frontend;

@(Command("cert").Description("Manage certificates."))
struct CertificateCommand
{
    int opCall()
    {
        return cmd.match!(
                (ListCerts cmd) => cmd(),
                (SubmitCert cmd) => cmd(),
                (RevokeCert cmd) => cmd()
        );
    }

    @SubCommands
    SumType!(ListCerts, SubmitCert, RevokeCert) cmd;
}

@(Command("list").Description("List certificates."))
struct ListCerts
{
    mixin LoginCommand;

    @(NamedArgument("team").Description("Team ID"))
    string teamId = null;

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

        string teamId = this.teamId;
        if (teamId != null) {
            teams = teams.filter!((elem) => elem.teamId == teamId).array();
        }
        enforce(teams.length > 0, "No matching team found.");

        auto team = teams[0];

        auto certificates = appleAccount.listAllDevelopmentCerts!iOS(team).unwrap();

        writefln!"You have %d certificates registered."(certificates.length);
        writeln("Currently registered certificates:");
        foreach (certificate; certificates) {
            writefln!" - `%s` with the serial number `%s`, from the machine named `%s`."(certificate.name, certificate.serialNumber, certificate.machineName);
        }

        return 0;
    }
}

// @(Command("register").Description("Register a certificate for Sideloader if we don't already have one."))

@(Command("submit").Description("Submit a certificate signing request to Apple servers."))
struct SubmitCert
{
    mixin LoginCommand;

    @(NamedArgument("team").Description("Team ID"))
    string teamId = null;

    @(PositionalArgument(0).Description("CSR file"))
    string certificatePath;

    int opCall()
    {
        ubyte[] certificateData = readFile(certificatePath);
        auto cert = PKCS10Request(DataSourceMemory(certificateData.ptr, certificateData.length));

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

        string teamId = this.teamId;
        if (teamId != null) {
            teams = teams.filter!((elem) => elem.teamId == teamId).array();
        }
        enforce(teams.length > 0, "No matching team found.");

        auto team = teams[0];

        appleAccount.submitDevelopmentCSR!iOS(team, cast(string) cert.PEM_encode()).unwrap();

        return 0;
    }
}

@(Command("revoke").Description("Revoke a certificate."))
struct RevokeCert
{
    mixin LoginCommand;

    @(NamedArgument("team").Description("Team ID"))
    string teamId = null;

    @(PositionalArgument(0).Description("certificate serial number"))
    string serialNumber;

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

        string teamId = this.teamId;
        if (teamId != null) {
            teams = teams.filter!((elem) => elem.teamId == teamId).array();
        }
        enforce(teams.length > 0, "No matching team found.");

        auto team = teams[0];

        auto certificates = appleAccount.listAllDevelopmentCerts!iOS(team).unwrap();
        auto matchingCerts = certificates.filter!((cert) => cert.serialNumber == serialNumber).array();

        if (matchingCerts.length == 0) {
            log.error("No matching certificate found.");
            return 1;
        }

        enforce(matchingCerts.length == 1, "Multiple certificate matched?? To prevent any issue, ignoring the request.");

        appleAccount.revokeDevelopmentCert!iOS(team, matchingCerts[0]).unwrap();

        return 0;
    }
}
