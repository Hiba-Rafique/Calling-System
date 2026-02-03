import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';

class CallkitBridge {
  static Stream<dynamic> get onEvent => FlutterCallkitIncoming.onEvent;

  static Future<void> showIncoming(Map<String, dynamic> params) {
    final p = CallKitParams.fromJson(params);
    return FlutterCallkitIncoming.showCallkitIncoming(p);
  }

  static Future<void> endCall(String callId) {
    return FlutterCallkitIncoming.endCall(callId);
  }
}
