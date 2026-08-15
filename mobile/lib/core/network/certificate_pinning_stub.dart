import 'package:dio/dio.dart';

/// Web build: no-op.
///
/// A browser owns its own TLS stack and never hands the certificate chain to
/// page JavaScript, so pinning is not implementable here — there is no hook
/// to inspect the leaf certificate from Dart compiled to JS. The web target
/// exists for development (`flutter run -d chrome`); the shipping Android
/// and iOS builds get the real implementation in
/// `certificate_pinning_io.dart`.
void applyCertificatePinning(Dio dio) {}
