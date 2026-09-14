// Minimal isolation test: does ANY sketch produce Serial output on this board
// right now? Prints a counter once per second forever. No I2C, no BLE, no
// model. Purely to distinguish "USB/Serial toolchain problem" from "something
// specific to the diagnostic/production sketches."
void setup() {
  Serial.begin(115200);
}

unsigned long counter = 0;

void loop() {
  Serial.printf("MINIMAL_TEST_ALIVE %lu\n", counter);
  counter++;
  delay(1000);
}
