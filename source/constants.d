module constants;

public import version_string;

enum applicationName = "Sideloader";
enum altstoreApplicationNmae = "AltStore";
enum appWebsite = "https://github.com/Dadoum/Sideloader";
enum rawAboutText = `%s

Sideloader has been made by Dadoum, with the source code available on https://github.com/Dadoum/Sideloader.

Sideloader would not have been possible without the work of countless others on different projects.

Thanks to people behind: libimobiledevice, libplist, Botan, Botan D port, SideStore, AltStore, D Programming language, `
~ `%s, dlang-requests, slf4d, Cydia Impactor, Apple team behind Apple Music for Android, and many others.`;

enum ubyte[] appleAuthCA = cast(ubyte[]) "-----BEGIN CERTIFICATE-----
MIID+DCCAuCgAwIBAgIII2l0BK3LgxQwDQYJKoZIhvcNAQELBQAwYjELMAkGA1UE
BhMCVVMxEzARBgNVBAoTCkFwcGxlIEluYy4xJjAkBgNVBAsTHUFwcGxlIENlcnRp
ZmljYXRpb24gQXV0aG9yaXR5MRYwFAYDVQQDEw1BcHBsZSBSb290IENBMB4XDTE0
MDMwODAxNTMwNFoXDTI5MDMwODAxNTMwNFowbTEnMCUGA1UEAwweQXBwbGUgU2Vy
dmVyIEF1dGhlbnRpY2F0aW9uIENBMSAwHgYDVQQLDBdDZXJ0aWZpY2F0aW9uIEF1
dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwggEiMA0G
CSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC5Jhawy4ercRWSjt+qPuGA11O6pGDM
fIVy9zB8CU9XDUr/4V7JS1ATAmSxvTk10dcEUcEY+iL6rt+YGNa/Tk1DEPoliJ/T
QIV25SKBtlRFc5qL45xIGoZ6w1Hi2pX4pH3bMN5sDsTF9WyY56b6VyAdGXN6Ds1j
D7cniC7hmmiCuEBsYxYkZivnsuJUfeeIOaIbgT4C0znYl3dKMgzWCgqzBJvxcm9j
qBUebDfoD9tTkNYpXLxqV5tGeAo+JOqaP6HYP/XbbqhsgrXdmTjsklaUpsVzJtGu
CLLGUueOdkuJuFQPbuDZQtsqZYdGFLuWuFe7UeaEE/cNobaJrHzRIXSrAgMBAAGj
gaYwgaMwHQYDVR0OBBYEFCzFbVLdMe+M7AiB7d/cykMARQHQMA8GA1UdEwEB/wQF
MAMBAf8wHwYDVR0jBBgwFoAUK9BpR5R2Cf70a40uQKb3R01/CF4wLgYDVR0fBCcw
JTAjoCGgH4YdaHR0cDovL2NybC5hcHBsZS5jb20vcm9vdC5jcmwwDgYDVR0PAQH/
BAQDAgEGMBAGCiqGSIb3Y2QGAgwEAgUAMA0GCSqGSIb3DQEBCwUAA4IBAQAj8QZ+
UEGBol7TcKRJka/YzGeMoSV9xJqTOS/YafsbQVtE19lryzslCRry9OPHnOiwW/Df
3SIlERWTuUle2gxmel7Xb/Bj1GWMxHpUfVZPZZr92sSyyLC4oct94EeoQBW4Fhnt
W2GO36rQzdI6wH46nyJO39/0ThrNk//Q8EVVZDM+1OXaaKATinYwJ9S/+B529vnD
AO+xg+pTbVw1xw0HAbr4Ybn+xZprQ2GBA+u6X3Cd6G+UJEvczpKoLqI1PONJ4BZ3
otxruY0YQrk2lkMyxst2mTU22FbGmF3Db6V+lcLVegoCIGZ4kvJnpCMN6Am9zCEx
EKC9vrXdTN1GA5mZ
-----END CERTIFICATE-----";
enum nativesUrl = "https://apps.mzstatic.com/content/android-apple-music-apk/applemusic.apk";
