module sideload.sign;

import std.algorithm;
import std.exception;
import std.format;
import file = std.file;
import std.mmfile;
import std.parallelism;
import std.path;
import std.range;
import std.string;
import std.typecons;
import std.concurrency;
import std.datetime;

import slf4d;

import botan.hash.mdx_hash;
import botan.libstate.lookup;

import plist;

import imobiledevice;

import cms.cms_dec;

import server.developersession;

public import sideload.application;
public import sideload.bundle;
import sideload.certificateidentity;
import sideload.macho;

import utils;


void signFull(
    string configurationPath,
    iDevice device,
    DeveloperSession developer,
    Application app,
    string outputPath,
    void delegate(double progress, string action) progressCallback,
    bool isMultithreaded = true,
) {
    enum STEP_COUNT = 9.0;
    auto log = getLogger();

    bool isSideStore = app.bundleIdentifier() == "com.SideStore.SideStore";

    // select the first development team
    progressCallback(0 / STEP_COUNT, "Fetching development teams");
    auto team = developer.listTeams().unwrap()[0]; // TODO add a setting for that

    // list development devices from the account
    progressCallback(1 / STEP_COUNT, "List account's development devices");
    scope lockdownClient = new LockdowndClient(device, "sideloader");
    auto devices = developer.listDevices!iOS(team).unwrap();
    auto deviceUdid = device.udid();

    // if the current device is not registered as a development device for this account, do it!
    if (!devices.any!((device) => device.deviceNumber == deviceUdid)) {
        progressCallback(2 / STEP_COUNT, "Register the current device as a development device");
        auto deviceName = lockdownClient.deviceName();
        developer.addDevice!iOS(team, deviceName, deviceUdid).unwrap();
    }

    // create a certificate for the developer
    progressCallback(3 / STEP_COUNT, "Generating a certificate for Sideloader");
    auto certIdentity = new CertificateIdentity(configurationPath, developer);

    // check if we registered an app id for it (if not create it)
    progressCallback(4 / STEP_COUNT, "Creating App IDs for the application");
    string mainAppBundleId = app.bundleIdentifier();
    string mainAppIdStr = mainAppBundleId ~ "." ~ team.teamId;
    app.bundleIdentifier = mainAppIdStr;
    string mainAppName = app.bundleName();

    auto listAppIdResponse = developer.listAppIds!iOS(team).unwrap();

    auto appExtensions = app.appExtensions();

    foreach (ref plugin; appExtensions) {
        string pluginBundleIdentifier = plugin.bundleIdentifier();
        assertBundle(
            pluginBundleIdentifier.startsWith(mainAppBundleId) &&
            pluginBundleIdentifier.length > mainAppBundleId.length,
            "Plug-ins are not formed with the main app bundle identifier"
        );
        plugin.bundleIdentifier = mainAppIdStr ~ pluginBundleIdentifier[mainAppBundleId.length..$];
    }

    auto bundlesWithAppID = app ~ appExtensions;

    log.debugF!"App IDs needed: %-(%s, %)"(bundlesWithAppID.map!((b) => b.bundleIdentifier()).array());

    // Search which App IDs have to be registered (we don't want to start registering App IDs if we don't
    // have enough of them to register them all!! otherwise we will waste their precious App IDs)
    auto appIdsToRegister = bundlesWithAppID.filter!((bundle) => !listAppIdResponse.appIds.canFind!((a) => a.identifier == bundle.bundleIdentifier())).array();

    if (appIdsToRegister.length > listAppIdResponse.availableQuantity) {
        auto minDate = listAppIdResponse.appIds.map!((appId) => appId.expirationDate).minElement();
        throw new NoAppIdRemainingException(minDate);
    }

    foreach (bundle; appIdsToRegister) {
        log.infoF!"Creating App ID `%s`..."(bundle.bundleIdentifier);
        developer.addAppId!iOS(team, bundle.bundleIdentifier, bundle.bundleName).unwrap();
    }
    listAppIdResponse = developer.listAppIds!iOS(team).unwrap();
    auto appIds = listAppIdResponse.appIds.filter!((appId) => bundlesWithAppID.canFind!((bundle) => appId.identifier == bundle.bundleIdentifier())).array();
    auto mainAppId = appIds.find!((appId) => appId.identifier == mainAppIdStr)[0];

    foreach (ref appId; appIds) {
        if (!appId.features[AppIdFeatures.appGroup].boolean().native()) {
            // We need to enable app groups then !
            appId.features = developer.updateAppId!iOS(team, appId, dict(AppIdFeatures.appGroup, true)).unwrap();
        }
    }

    // create an app group for it if needed
    progressCallback(5 / STEP_COUNT, "Creating an application group");
    auto groupIdentifier = "group." ~ mainAppIdStr;

    if (isSideStore) {
        app.appInfo["ALTAppGroups"] = [groupIdentifier.pl].pl;
    }

    auto appGroups = developer.listApplicationGroups!iOS(team).unwrap();
    auto matchingAppGroups = appGroups.find!((appGroup) => appGroup.identifier == groupIdentifier).array();
    ApplicationGroup appGroup;
    if (matchingAppGroups.empty) {
        appGroup = developer.addApplicationGroup!iOS(team, groupIdentifier, mainAppName).unwrap();
    } else {
        appGroup = matchingAppGroups[0];
    }

    progressCallback(6 / STEP_COUNT, "Manage App IDs and groups");
    ProvisioningProfile[string] provisioningProfiles;
    foreach (appId; appIds) {
        developer.assignApplicationGroupToAppId!iOS(team, appId, appGroup).unwrap();
        auto deviceClass = lockdownClient.deviceClass();
        if (deviceClass.canFind("AppleTV")) {
            provisioningProfiles[appId.identifier] = developer.downloadTeamProvisioningProfile!tvOS(team, mainAppId).unwrap();
        } else {
            provisioningProfiles[appId.identifier] = developer.downloadTeamProvisioningProfile!iOS(team, mainAppId).unwrap();
        }
    }

    // sign the app with all the retrieved material!
    progressCallback(7 / STEP_COUNT, "Signing the application bundle");
    double accumulator = 0;
    sign(app, certIdentity, provisioningProfiles, (progress) => progressCallback((7 + (accumulator += progress)) / STEP_COUNT, "Signing the application bundle"));
    log.debugF!"app.bundleDir=%s"(app.bundleDir);

    auto destDir = buildPath(outputPath);
    if (!file.exists(destDir)) {
        file.mkdirRecurse(destDir);
    }
    auto destPath = buildPath(destDir, baseName(app.bundleDir));
    if (file.exists(destPath)) {
        file.rmdirRecurse(destPath);
    }
    copyDirRecursively(app.bundleDir, destPath);
    log.infoF!"Signed app path: %s"(destPath);
}

void copyDirRecursively(string sourceDir, string targetDir) {
    // 创建目标文件夹
    file.mkdirRecurse(targetDir);

    // 获取源文件夹中的所有文件和子文件夹
    foreach (entry; file.dirEntries(sourceDir, file.SpanMode.shallow)) {
        string entryName = entry.name;
        string targetPath = targetDir ~ "/" ~ baseName(entryName);

        if (entry.isDir) {
            // 递归复制子文件夹
            copyDirRecursively(entryName, targetPath);
        } else {
            // 复制文件
            file.copy(entryName, targetPath);
        }
    }
}

Tuple!(PlistDict, PlistDict) sign(
    Bundle bundle,
    CertificateIdentity identity,
    ProvisioningProfile[string] provisioningProfiles,
    void delegate(double progress) addProgress,
    bool isMultithreaded = true,
    string teamId = null,
    MDxHashFunction sha1Hasher = null,
    MDxHashFunction sha2Hasher = null,
) {
    auto log = getLogger();

    auto bundleFolder = bundle.bundleDir;
    auto fairPlayFolder = bundleFolder.buildPath("SC_Info");
    if (file.exists(fairPlayFolder)) {
        file.rmdirRecurse(fairPlayFolder);
    }

    auto bundleId =  bundle.bundleIdentifier();

    PlistDict files = new PlistDict();
    PlistDict files2 = new PlistDict();

    static import sse2;
    sse2.register();

    if (!sha1Hasher) {
        sha1Hasher = cast(MDxHashFunction) retrieveHash("SHA-1");
    }
    if (!sha2Hasher) {
        sha2Hasher = cast(MDxHashFunction) retrieveHash("SHA-256");
    }

    auto sha1HasherParallel = taskPool().workerLocalStorage!MDxHashFunction(cast(MDxHashFunction) sha1Hasher.clone());
    auto sha2HasherParallel = taskPool().workerLocalStorage!MDxHashFunction(cast(MDxHashFunction) sha2Hasher.clone());

    auto lprojFinder = boyerMooreFinder(".lproj");

    string infoPlist = bundle.appInfo.toBin();

    auto profile = bundle.bundleIdentifier() in provisioningProfiles;
    ubyte[] profileData;
    Plist profilePlist;

    if (profile) {
        profileData = profile.encodedProfile;
        file.write(bundleFolder.buildPath("embedded.mobileprovision"), profileData);
        profilePlist = Plist.fromMemory(dataFromCMS(profileData));
        teamId = profilePlist["TeamIdentifier"].array[0].str().native();
    }

    auto subBundles = bundle.subBundles();

    size_t stepCount = subBundles.length + 2;
    const double stepSize = 1.0 / stepCount;

    void signSubBundles() {
        foreach (subBundle; parallel(subBundles)) {
            auto bundleFiles = subBundle.sign(
                identity,
                provisioningProfiles,
                    (double progress) => addProgress(progress * stepSize),
                isMultithreaded,
                teamId,
                sha1HasherParallel.get(),
                sha2HasherParallel.get()
            );
            auto subBundlePath = subBundle.bundleDir;

            auto bundleFiles1 = bundleFiles[0];
            auto bundleFiles2 = bundleFiles[1];

            auto subFolder = subBundlePath.relativePath(/+ base +/ bundleFolder);

            void reroot(ref PlistDict dict, ref PlistDict subDict) {
                auto iter = subDict.iter();

                string key;
                Plist element;

                synchronized {
                    while (iter.next(element, key)) {
                        dict[subFolder.buildPath(key)] = element.copy();
                    }
                }
            }
            reroot(files, bundleFiles1);
            reroot(files2, bundleFiles2);

            void addFile(string subRelativePath) {
                ubyte[] sha1 = new ubyte[](20);
                ubyte[] sha2 = new ubyte[](32);

                auto localHasher1 = sha1HasherParallel.get();
                auto localHasher2 = sha2HasherParallel.get();

                auto hashPairs = [tuple(localHasher1, sha1), tuple(localHasher2, sha2)];

                scope MmFile memoryFile = new MmFile(subBundle.bundleDir.buildPath(subRelativePath));
                ubyte[] fileData = cast(ubyte[]) memoryFile[];

                foreach (hashCouple; parallel(hashPairs)) {
                    auto localHasher = hashCouple[0];
                    auto sha = hashCouple[1];
                    sha[] = localHasher.process(fileData)[];
                }

                synchronized {
                    files[subFolder.buildPath(subRelativePath)] = sha1.pl;
                    files2[subFolder.buildPath(subRelativePath)] = dict(
                        "hash", sha1,
                        "hash2", sha2
                    );
                }
            }
            addFile("_CodeSignature".buildPath("CodeResources"));
            addFile(subBundle.appInfo["CFBundleExecutable"].str().native());
        }
    }

    typeof(task(&signSubBundles)) subBundlesTask;
    if (isMultithreaded) {
        subBundlesTask = task(&signSubBundles);
        subBundlesTask.executeInNewThread();
    }

    log.debugF!"Signing bundle %s..."(baseName(bundleFolder));

    string executable = bundle.appInfo["CFBundleExecutable"].str().native();

    string codeSignatureFolder = bundleFolder.buildPath("_CodeSignature");
    string codeResourcesFile = codeSignatureFolder.buildPath("CodeResources");

    if (file.exists(codeSignatureFolder)) {
        if (file.exists(codeResourcesFile)) {
            file.remove(codeResourcesFile);
        }
    } else {
        file.mkdir(codeSignatureFolder);
    }

    file.write(bundleFolder.buildPath("Info.plist"), infoPlist);

    log.debug_("Hashing files...");

    auto bundleFiles = file.dirEntries(bundleFolder, file.SpanMode.breadth);
    // double fileStepSize = stepSize / bundleFiles.length; TODO

    // TODO re-use the original CodeResources if it already existed.
    if (bundleFolder[$ - 1] == '/' || bundleFolder[$ - 1] == '\\') bundleFolder.length -= 1;
    foreach(idx, absolutePath; parallel(bundleFiles)) {
        // scope(exit) addProgress(fileStepSize);

        string basename = baseName(absolutePath);
        string relativePath = absolutePath[bundleFolder.length + 1..$];

        enum frameworksDir = "Frameworks/";
        enum plugInsDir = "PlugIns/";

        if (
            // if it's a folder don't sign it
            !file.isFile(absolutePath)
            // if it's the executable skip it (it will be modified in the next step)
            || relativePath == executable
            // if it's a file from a framework folder, skip it as it is processed by some other thread.
            || (relativePath.startsWith(frameworksDir) && relativePath[frameworksDir.length..$].toForwardSlashes().canFind('/'))
            // if it's a file from a plugins folder, skip it as it is processed by some other thread.
            || (relativePath.startsWith(plugInsDir) && relativePath[plugInsDir.length..$].toForwardSlashes().canFind('/'))
        ) {
            continue;
        }

        ubyte[] sha1 = new ubyte[](20);
        ubyte[] sha2 = new ubyte[](32);

        auto localHasher1 = sha1HasherParallel.get();
        auto localHasher2 = sha2HasherParallel.get();

        auto hashPairs = [tuple(localHasher1, sha1), tuple(localHasher2, sha2)];

        if (file.getSize(absolutePath) > 0) {
            scope MmFile memoryFile = new MmFile(absolutePath);
            ubyte[] fileData = cast(ubyte[]) memoryFile[];

            foreach (hashCouple; parallel(hashPairs)) {
                auto localHasher = hashCouple[0];
                auto sha = hashCouple[1];
                sha[] = localHasher.process(fileData)[];
            }
        } else {
            foreach (hashCouple; parallel(hashPairs)) {
                auto localHasher = hashCouple[0];
                auto sha = hashCouple[1];
                sha[] = localHasher.process(cast(ubyte[]) [])[];
            }
        }

        Plist hashes1 = sha1.pl;

        PlistDict hashes2 = dict(
            "hash", sha1,
            "hash2", sha2
        );

        if (lprojFinder.beFound(relativePath) != null) {
            hashes1 = dict(
                "hash", hashes1,
                "optional", true
            );

            hashes2["optional"] = true.pl;
        }

        synchronized {
            files[relativePath] = hashes1;
            files2[relativePath] = hashes2;
        }
    }
    // too lazy yet to add better progress tracking
    addProgress(stepSize);

    if (isMultithreaded) {
        subBundlesTask.yieldForce();
    }

    log.debug_("Making CodeResources...");
    string codeResources = dict(
        "files", files.copy(),
        "files2", files2.copy(),
        // Rules have been copied from zsign
        "rules", rules(),
        "rules2", rules2()
    ).toXml();
    file.write(codeResourcesFile, codeResources);

    string executablePath = bundleFolder.buildPath(executable);
    PlistDict profileEntitlements = profilePlist ? profilePlist["Entitlements"].dict : new PlistDict();

    auto fatMachOs = (executable ~ bundle.libraries()).map!((f) {
        auto path = bundleFolder.buildPath(f);
        return tuple!("path", "machO")(path, MachO.parse(cast(ubyte[]) file.read(path)));
    });

    double machOStepSize = stepSize / fatMachOs.length;

    foreach (idx, fatMachOPair; parallel(fatMachOs)) {
        scope(exit) addProgress(machOStepSize);
        auto path = fatMachOPair.path;
        auto fatMachO = fatMachOPair.machO;
        log.debugF!"Signing executable %s..."(path[bundleFolder.dirName.length + 1..$]);

        auto requirementsBlob = new RequirementsBlob();

        foreach (machO; fatMachO) {
            CodeDirectoryBlob codeDir1;
            CodeDirectoryBlob codeDir2;

            PlistDict entitlements;

            if (idx == 0) {
                entitlements = profileEntitlements;
                codeDir1 = new CodeDirectoryBlob(sha1HasherParallel.get(), bundleId, teamId, machO, entitlements, infoPlist, codeResources);
                codeDir2 = new CodeDirectoryBlob(sha2HasherParallel.get(), bundleId, teamId, machO, entitlements, infoPlist, codeResources, true);
            } else {
                entitlements = new PlistDict();
                codeDir1 = new CodeDirectoryBlob(sha1HasherParallel.get(), baseName(path), teamId, machO, entitlements, null, null);
                codeDir2 = new CodeDirectoryBlob(sha2HasherParallel.get(), baseName(path), teamId, machO, entitlements, null, null, true);
            }

            auto embeddedSignature = new EmbeddedSignature();
            embeddedSignature.blobs = cast(Blob[]) [
                requirementsBlob,
                new EntitlementsBlob(entitlements.toXml())
            ];

            if (machO.filetype == MH_EXECUTE) {
                embeddedSignature.blobs ~= new DerEntitlementsBlob(entitlements);
            }

            embeddedSignature.blobs ~= cast(Blob[]) [
                codeDir1,
                codeDir2,
                new SignatureBlob(identity, [null, sha1HasherParallel.get(), sha2HasherParallel.get()])
            ];

            machO.replaceCodeSignature(new ubyte[](embeddedSignature.length()));

            auto encodedBlob = embeddedSignature.encode();
            enforce(!machO.replaceCodeSignature(encodedBlob));
        }

        file.write(path, makeMachO(fatMachO));
    }

    return tuple(files, files2);
}

Plist rules() {
    return dict(
        "^.*", true,
        "^.*\\.lproj/", dict(
            "optional", true,
            "weight", 1000.
        ),
        "^.*\\.lproj/locversion.plist$", dict(
            "omit", true,
            "weight", 1100.
        ),
        "^Base\\.lproj/", dict(
            "weight", 1010.
        ),
        "^version.plist$", true
    );
}

Plist rules2() {
    return dict(
        ".*\\.dSYM($|/)", dict(
            "weight", 11.
        ),
        "^(.*/)?\\.DS_Store$", dict(
            "omit", true,
            "weight", 2000.
        ),
        "^.*", true,
        "^.*\\.lproj/", dict(
            "optional", true,
            "weight", 1000.
        ),
        "^.*\\.lproj/locversion.plist$", dict(
            "omit", true,
            "weight", 1100.
        ),
        "^Base\\.lproj/", dict(
            "weight", 1010.
        ),
        "^Info\\.plist$", dict(
            "omit", true,
            "weight", 20.
        ),
        "^PkgInfo$", dict(
            "omit", true,
            "weight", 20.
        ),
        "^embedded\\.provisionprofile$", dict(
            "weight", 20.
        ),
        "^version\\.plist$", dict(
            "weight", 20.
        )
    );
}

class InvalidApplicationException: Exception {
    this(string message, string file = __FILE__, size_t line = __LINE__) {
        super(format!"Cannot sign the application : %s"(message));
    }
}

class NoAppIdRemainingException: Exception {
    this(DateTime minExpirationDate, string file = __FILE__, int line = __LINE__) {
        super(format!"Cannot make any more app ID, you have to wait until %s to get a new app ID"(minExpirationDate.toSimpleString()), file, line);
    }
}