import 'dart:html' as html;

typedef VoidCallbackFn = void Function();

bool _registered = false;

void registerWebUnloadHandler(VoidCallbackFn onUnload) {
  if (_registered) return;
  _registered = true;

  html.window.addEventListener('beforeunload', (_) {
    try {
      onUnload();
    } catch (_) {}
  });

  html.window.addEventListener('pagehide', (_) {
    try {
      onUnload();
    } catch (_) {}
  });
}
