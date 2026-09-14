import 'package:dio/dio.dart';

import 'glasses_resolver.dart';

/// Web build: no raw sockets, so no connection factory. A plain Dio lets the
/// browser do what it can with the hostname. The mDNS steering is native-only.
Dio glassesDio({
  required GlassesAddressResolver resolver,
  Duration timeout = const Duration(seconds: 3),
}) =>
    Dio(BaseOptions(connectTimeout: timeout, receiveTimeout: timeout));
