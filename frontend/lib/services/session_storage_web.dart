// Flutter Web only. Keep the session in this browser tab (not localStorage).
import 'dart:js_interop';

@JS('window.sessionStorage')
external _BrowserStorage get _browserStorage;

extension type _BrowserStorage(JSObject _) implements JSObject {
  external JSString? getItem(JSString key);
  external void setItem(JSString key, JSString value);
  external void removeItem(JSString key);
}

String? read(String key) {
  try {
    return _browserStorage.getItem(key.toJS)?.toDart;
  } catch (_) {
    // Private browsing or browser policy may block storage.
    return null;
  }
}

void write(String key, String value) {
  try {
    _browserStorage.setItem(key.toJS, value.toJS);
  } catch (_) {}
}

void remove(String key) {
  try {
    _browserStorage.removeItem(key.toJS);
  } catch (_) {}
}
