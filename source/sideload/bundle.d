module sideload.bundle;

import std.algorithm.iteration;
import std.array;
import file = std.file;
import std.path;
import std.algorithm;
import std.regex;

import plist;

class Bundle {
    PlistDict appInfo;
    string bundleDir;

    Bundle[] _appExtensions;
    Bundle[] _frameworks;
    string[] _libraries;

    this(string bundleDir) {
        if (bundleDir[$ - 1] == '/' || bundleDir[$ - 1] == '\\') bundleDir.length -= 1;
        this.bundleDir = bundleDir;
        string infoPlistPath = bundleDir.buildPath("Info.plist");
        assertBundle(file.exists(infoPlistPath), "No Info.plist here: " ~ infoPlistPath);

        fixBundleIdentifierAndName(infoPlistPath);

        appInfo = Plist.fromMemory(cast(ubyte[]) file.read(infoPlistPath)).dict();
        auto plugInsDir = bundleDir.buildPath("PlugIns");
        if (file.exists(plugInsDir)) {
            _appExtensions = file.dirEntries(plugInsDir, file.SpanMode.shallow).filter!((f) => f.isDir).map!((f) => new Bundle(f.name)).array;
        } else {
            _appExtensions = [];
        }

        auto frameworksDir = bundleDir.buildPath("Frameworks");
        if (file.exists(frameworksDir)) {
            _frameworks = file.dirEntries(frameworksDir, file.SpanMode.shallow).filter!((f) => f.isDir && f.name.endsWith(".framework")).map!((f) => new Bundle(f.name)).array;
            _libraries = file.dirEntries(frameworksDir, file.SpanMode.shallow).filter!((f) => f.isFile).map!((f) => f.name[bundleDir.length + 1..$]).array;
        } else {
            _frameworks = [];
        }
    }

    private static void fixBundleIdentifierAndName(string infoPlistPath) {
        auto info = Plist.fromMemory(cast(ubyte[]) file.read(infoPlistPath)).dict();
        auto rValidChar = regex(r"^[a-zA-Z0-9.-]$");
        auto rInvalidChar = regex(r"[^a-zA-Z0-9.-]");
    
        auto needWrite = false;
        if (!matchFirst(info["CFBundleIdentifier"].str().native(), rValidChar)) {
            info["CFBundleIdentifier"].str().opAssign(info["CFBundleIdentifier"].str().native().replaceAll(rInvalidChar, ""));
            needWrite = true;
        }
        if ("CFBundleName" in info && !matchFirst(info["CFBundleName"].str().native(), rValidChar)) {
            info["CFBundleName"].str().opAssign(info["CFBundleName"].str().native().replaceAll(rInvalidChar, ""));
            needWrite = true;
        }
        if (needWrite) {
            file.write(infoPlistPath, cast(ubyte[])info.toXml());
        }
    }
    

    void bundleIdentifier(string id) => appInfo["CFBundleIdentifier"] = id.pl;
    string bundleIdentifier() => appInfo["CFBundleIdentifier"].str().native();

    string bundleName() => appInfo["CFBundleName"].str().native();

    string[] libraries() => _libraries;
    Bundle[] frameworks() => _frameworks;
    Bundle[] appExtensions() => _appExtensions;
    Bundle[] subBundles() => frameworks ~ appExtensions;
}

void assertBundle(bool condition, string msg, string file = __FILE__, int line = __LINE__) {
    if (!condition) {
        throw new InvalidBundleException(msg, file, line);
    }
}

class InvalidBundleException: Exception {
    this(string msg, string file = __FILE__, int line = __LINE__) {
        super("Cannot parse the application bundle! " ~ msg, file, line);
    }
}
