typedef VoidCallbackFn = void Function();

void registerWebUnloadHandler(VoidCallbackFn onUnload) {
  // no-op on non-web platforms
}
