module cli_frontend;

import core.stdc.stdlib;

import std.array;
import std.datetime;
import std.exception;
import std.format;
import std.parallelism;
import std.path;
import std.process;
import std.stdio;
import std.sumtype;
import std.string;
import std.traits;
import std.typecons;
import std.regex;
import file = std.file;

import slf4d;
import slf4d.default_provider;
import slf4d.provider;

import botan.cert.x509.x509cert;
import botan.pubkey.algo.rsa;

import plist;

import provision;

import imobiledevice;

import server.appleaccount;
import server.developersession;
import version_string;

import sideload;
import sideload.bundle;
import sideload.application;
import sideload.certificateidentity;
import sideload.sign;

import argparse;

import app;
import utils;

version = X509;

noreturn wrongArgument(string msg) {
    getLogger().error(msg);
    exit(1);
}

auto openApp(string path) {
    if (!file.exists(path))
        return wrongArgument("The specified app file does not exist.");

    if (!path.endsWith(".ipa") && !path.endsWith(".tipa"))
        return wrongArgument("The app is not an ipa file.");

    if (!file.isFile(path))
        return wrongArgument("The app should be an ipa file.");

    return new Application(path);
}

auto openAppFolder(string path) {
    if (!file.exists(path))
        return wrongArgument("The specified app file does not exist.");

    if (file.isFile(path))
        return wrongArgument("The app should be a folder.");

    return new Application(path);
}


auto readFile(string path) {
    return cast(ubyte[]) file.read(path);
}

auto readPrivateKey(string path) {
    RandomNumberGenerator rng = RandomNumberGenerator.makeRng();
    return RSAPrivateKey(loadKey(path, rng));
}

auto readCertificate(string path) {
    return X509Certificate(path, false);
}

extern(C) char* getpass(const(char)* prompt);

string readPasswordLine(string prompt) {
    version (Windows) {
        write(prompt.toStringz(), " [/!\\ The password will appear in clear text in the terminal]: ");
        return readln().chomp();
    } else {
        return fromStringz(cast(immutable) getpass(prompt.toStringz()));
    }
}

DeveloperSession login(Device device, ADI adi, bool interactive, string appleId, string password, bool quietMode) {
    auto log = getLogger();

    log.info("Logging in...");

    DeveloperSession account;

    // TODO Keyring stuff
    // ...

    if (account) return null;
    if (interactive) {
        log.info("Please enter your account informations. They will only be sent to Apple servers.");
        log.info("See it for yourself at https://github.com/Dadoum/Sideloader/");

        write("Apple ID: ");
        appleId = readln().chomp();
        password = readPasswordLine("Password: ");
    }
    if (appleId.empty || password.empty) {
        log.error("You are not logged in. (please add `-a` and `-p` to specific Apple ID, or add `-i` to make us ask you the account)");
        return null;
    }

    TFAHandlerDelegate tfaHandler = (sendCode, submitCode) {
        if (quietMode) {
            string error = format!`2FA authentication can not performed in QUIET MODE.`;
            throw new Exception(error);
        }
    
        sendCode();
        log.info("A code has been sent to your devices, please type it here (type `ENTER` to cancel):");
        auto code = readln().chomp();
        if (code.empty) {
            throw new Exception("Cancel 2FA authentication.");
        }
        auto regDigit = regex(r"^\d+$"); 
        if (match(code, regDigit).empty) {
            throw new Exception("Invalid 2FA code.");
        }
        submitCode(code).match!((Success _) => false, (ReloginNeeded _) => false, (AppleLoginError _) => false);
    };

    return DeveloperSession.login(
        device,
        adi,
        appleId,
        password,
        tfaHandler)
    .match!(
        (DeveloperSession session) => session,
        (AppleLoginError error) {
            log.errorF!"Can't log-in! %s (%d)"(error.description, error);
            return null;
        }
    );
}

auto initializeADI(string configurationPath)
{
    scope log = getLogger();
    if (!(file.exists(configurationPath.buildPath("lib/libstoreservicescore.so")) && file.exists(configurationPath.buildPath("lib/libCoreADI.so")))) {
        auto succeeded = downloadAndInstallDeps(configurationPath, (progress) {
            write(format!"%.2f %% completed\r"(progress * 100));
            stdout.flush();

            return false;
        });

        if (!succeeded) {
            log.error("Download failed.");
            exit(1);
        }
        log.info("Download completed.");
    }

    scope provisioningData = app.initializeADI(configurationPath);
    return provisioningData;
}

string systemConfigurationPath()
{
    return environment.get("SIDELOADER_CONFIG_DIR").orDefault(defaultConfigurationPath());
}

string defaultConfigurationPath()
{
    version (Windows) {
        string configurationPath = environment["AppData"];
    } else version (OSX) {
        string configurationPath = "~/Library/Preferences/".expandTilde();
    } else {
        string configurationPath = environment.get("XDG_CONFIG_DIR")
            .orDefault("~/.config")
            .expandTilde();
    }
    return configurationPath.buildPath("Sideloader");
}

// planned commands

import app_id;
import certificate;
import install;
// @(Command("login").Description("Log-in to your Apple account."))
// @(Command("logout").Description("Log-out."))
import sign;
// @(Command("swift-setup").Description("Set-up certificates to build a Swift Package Manager iOS application (requires SPM in the path)."))
import team;
import device;
import group;
import check;
import tool;
// @(Command("tweak").Description("Install a tweak in an ipa file."))

mixin template LoginCommand()
{
    import provision;
    @(NamedArgument("i", "interactive").Description("Prompt to type passwords if needed."))
    bool interactive = false;
    @(NamedArgument("a", "appleId").Description("Apple ID to sign the ipa, only needed when installing IPA."))
    string appleId = "";
    @(NamedArgument("p", "password").Description("Password of Apple ID, only needed when installing IPA."))
    string password = "";

    final auto login(Device device, ADI adi, bool quietMode = false) => cli_frontend.login(device, adi, interactive, appleId, password, quietMode);
}

@(Command("version").Description("Print the version."))
struct VersionCommand {
    int opCall() {
        writeln(versionStr);
        return 0;
    }
}

int entryPoint(Commands commands)
{
    version (linux) {
        import core.stdc.locale;
        setlocale(LC_ALL, "");
    }

    defaultPoolThreads = commands.threadCount;
    auto logLevel = Levels.INFO;
    if (commands.debug_) {
        logLevel = Levels.DEBUG;
    }
    if (commands.trace_) {
        logLevel = Levels.TRACE;
    }
    configureLoggingProvider(new shared DefaultProvider(!commands.nocolor_, logLevel));

    try
    {
        return commands.cmd.match!(
                (AppIdCommand cmd) => cmd(),
                (CertificateCommand cmd) => cmd(),
                (InstallCommand cmd) => cmd(),
                (SignCommand cmd) => cmd(),
                (TeamCommand cmd) => cmd(),
                (DeviceCommand cmd) => cmd(),
                (GroupCommand cmd) => cmd(),
                (CheckCommand cmd) => cmd(),
                (ToolCommand cmd) => cmd(),
                (VersionCommand cmd) => cmd(),
        );
    }
    catch (Exception ex)
    {
        getLogger().errorF!"%s at %s:%d: %s"(typeid(ex).name, ex.file, ex.line, ex.msg);
        getLogger().debugF!"Full exception: %s"(ex);
        return 1;
    }
}

struct Commands
{
    @(NamedArgument("d", "debug").Description("Enable debug logging"))
    bool debug_;

    @(NamedArgument("verbose").Description("Enable trace logging"))
    bool trace_;

    @(NamedArgument("nocolor").Description("Disable ANSI color output"))
    bool nocolor_;

    @(NamedArgument("thread-count").Description("Numbers of threads to be used for signing the application bundle"))
    uint threadCount = uint.max;

    @SubCommands
    SumType!(AppIdCommand, CertificateCommand, InstallCommand, SignCommand, TeamCommand, DeviceCommand, GroupCommand, CheckCommand, ToolCommand, VersionCommand) cmd;
}

mixin CLI!Commands.main!entryPoint;

