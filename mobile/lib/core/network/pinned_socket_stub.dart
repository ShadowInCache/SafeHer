import 'package:web_socket_channel/web_socket_channel.dart';

/// Web build: the browser owns the TLS stack and never exposes the
/// certificate chain to page JavaScript, so pinning is not implementable
/// here — the same reason `certificate_pinning_stub.dart` is a no-op.
Future<WebSocketChannel> connectPinnedWebSocket(Uri uri) async =>
    WebSocketChannel.connect(uri);
