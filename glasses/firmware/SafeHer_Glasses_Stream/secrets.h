// Copy this file to `secrets.h` and fill in your network.
//
// `secrets.h` is gitignored. This example is the one that gets committed, and
// it must never contain a real credential.
//
// This matters here specifically: an earlier sketch in this directory had a
// Gmail app password and an Arduino IoT device key written into the source and
// pushed to a public repository. Anything in a `#define` in a `.ino` is
// published the moment the commit is.

#pragma once

#define WIFI_SSID     "Test_Wifi"
#define WIFI_PASSWORD "Test12345"
