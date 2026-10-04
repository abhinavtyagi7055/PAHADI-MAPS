import 'dart:js_interop';

@JS('pahadiRequestNotificationPermission')
external JSPromise<JSString> _requestNotificationPermission();

@JS('pahadiShowNotification')
external void _showNotification(JSString title, JSString body);

Future<bool> requestBrowserNotificationPermission() async {
  final permission = await _requestNotificationPermission().toDart;
  return permission.toDart == 'granted';
}

void showBrowserNotification(String title, String body) {
  _showNotification(title.toJS, body.toJS);
}
