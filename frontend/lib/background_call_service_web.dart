class BackgroundCallService {
  static final BackgroundCallService _instance = BackgroundCallService._internal();
  factory BackgroundCallService() => _instance;
  BackgroundCallService._internal();

  static bool get isSupported => false;

  Future<void> initialize() async {}

  void connectToServer(String userId, {required String serverUrl}) {}

  Future<void> showCallConnectedNotification(String withUser) async {}

  Future<void> clearNotifications() async {}
}
