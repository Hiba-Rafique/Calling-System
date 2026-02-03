import 'dart:async';

class CallkitBridge {
  static Stream<dynamic> get onEvent => const Stream.empty();

  static Future<void> showIncoming(Map<String, dynamic> params) async {}

  static Future<void> endCall(String callId) async {}
}
