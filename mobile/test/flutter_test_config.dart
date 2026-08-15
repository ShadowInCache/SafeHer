import 'dart:async';
import 'dart:io' show Platform;

import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:google_fonts/google_fonts.dart';

/// Golden files in this repo are rendered on Windows.
///
/// Text rasterisation is not identical across operating systems -- font
/// hinting, subpixel positioning and the fallback font chosen when a family is
/// unavailable all differ -- so a golden captured on one platform reliably
/// mismatches on another by a small percentage of pixels. That makes golden
/// assertions useless as a cross-platform gate: on Linux CI they fail on every
/// run regardless of whether anything actually regressed.
///
/// So the assertion is skipped off the reference platform. The tests still
/// build and pump their widget trees everywhere, which is what catches real
/// breakage (exceptions, layout overflows, missing providers); only the
/// pixel comparison is limited to where the files were generated.
///
/// Set `GOLDEN_PLATFORM_OVERRIDE=1` to force comparison anywhere -- useful if
/// the goldens are ever regenerated on Linux.
bool _shouldSkipGoldens() {
  if (Platform.environment['GOLDEN_PLATFORM_OVERRIDE'] == '1') return false;
  return !Platform.isWindows;
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  return GoldenToolkit.runWithConfiguration(
    () async {
      await loadAppFonts();
      await testMain();
    },
    config: GoldenToolkitConfiguration(
      defaultDevices: [Device.phone],
      skipGoldenAssertion: _shouldSkipGoldens,
    ),
  );
}
