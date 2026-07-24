import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Minimal WebViewPlatform test double. model_viewer_plus (and any other
/// webview_flutter-based widget) asserts `WebViewPlatform.instance != null`
/// before constructing its controller — there's no real WebView in the
/// `flutter test` VM environment, so this satisfies construction without
/// attempting to render actual web content. Call [install] once per test
/// that mounts such a widget.
class FakeWebViewPlatform extends WebViewPlatform {
  static void install() {
    WebViewPlatform.instance = FakeWebViewPlatform();
  }

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return _FakePlatformWebViewController(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(PlatformWebViewWidgetCreationParams params) {
    return _FakePlatformWebViewWidget(params);
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return _FakePlatformNavigationDelegate(params);
  }
}

class _FakePlatformWebViewController extends PlatformWebViewController {
  _FakePlatformWebViewController(super.params) : super.implementation();

  // These have concrete (throwing) bodies on the base class rather than
  // being abstract, so noSuchMethod alone doesn't intercept them — each
  // one actually called during ModelViewer's init needs an explicit
  // override. Anything else falls through to noSuchMethod below.
  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setPlatformNavigationDelegate(PlatformNavigationDelegate handler) async {}

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams javaScriptChannelParams) async {}

  @override
  Future<void> loadRequest(LoadRequestParams params) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _FakePlatformWebViewWidget extends PlatformWebViewWidget {
  _FakePlatformWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _FakePlatformNavigationDelegate extends PlatformNavigationDelegate {
  _FakePlatformNavigationDelegate(super.params) : super.implementation();

  @override
  Future<void> setOnNavigationRequest(NavigationRequestCallback onNavigationRequest) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
