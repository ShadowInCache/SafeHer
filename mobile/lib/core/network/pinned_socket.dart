import 'package:web_socket_channel/web_socket_channel.dart';

import 'pinned_socket_stub.dart' if (dart.library.io) 'pinned_socket_io.dart' as impl;

/// Opens a WebSocket with the same certificate pinning the HTTP API uses.
///
/// The live-monitoring socket carries threat scores and emergency broadcasts
/// for a specific user, and it was the one channel left on plain CA trust
/// after `certificate_pinning.dart` landed. Pinning the API but not the
/// socket leaves the easier target unpinned.
Future<WebSocketChannel> connectPinnedWebSocket(Uri uri) => impl.connectPinnedWebSocket(uri);
