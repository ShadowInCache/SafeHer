#include <ArduinoIoTCloud.h>
#include <Arduino_ConnectionHandler.h>

// ===== WiFi Credentials =====
const char SSID[] = "Test_Wifi";
const char PASS[] = "Test12345";

// ===== Device Credentials =====
const char DEVICE_LOGIN_NAME[]  = "1d5b2785-9e0e-4b6d-be24-d549fcde1b12"; 
const char DEVICE_KEY[]         = "nN6Fa@Cm!WqBqY20sh1oQj?2P";

// ===== Callbacks =====
void onStr1Change();
void onV0Change();
void onLoc1Change();

// ===== Cloud Variables =====
String Str1;
bool V0;
CloudLocation Loc1;

// ===== WiFi Connection =====
WiFiConnectionHandler ArduinoIoTPreferredConnection(SSID, PASS);

// ===== Init =====
void initProperties() {
  ArduinoCloud.setBoardId(DEVICE_LOGIN_NAME);
  ArduinoCloud.setSecretDeviceKey(DEVICE_KEY);
  ArduinoCloud.addProperty(Str1, READWRITE, ON_CHANGE, onStr1Change);
  ArduinoCloud.addProperty(V0, READWRITE, ON_CHANGE, onV0Change);
  ArduinoCloud.addProperty(Loc1, READWRITE, ON_CHANGE, onLoc1Change);
}