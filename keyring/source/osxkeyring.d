module osxkeyring;

import keyring;

version (OSX):

class OSXKeyring : KeyringImplementation
{
    static OSXKeyring create()
    {
        return null; // new OSXKeyring;
    }

    void store(string account)
    {
    }

    string lookup()
    {
        return null;
    }

    void clear()
    {

    }
}
