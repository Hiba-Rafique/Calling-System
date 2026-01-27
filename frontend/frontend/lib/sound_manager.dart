import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter/foundation.dart';

/// Manages sound effects and vibration for calling experience
class SoundManager {
  static final SoundManager _instance = SoundManager._internal();
  factory SoundManager() => _instance;
  SoundManager._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlayingRingtone = false;

  /// Play outgoing call sound (dialing tone)
  Future<void> playDialingSound() async {
    try {
      // Use built-in system sound for dialing
      await _audioPlayer.play(AssetSource('sounds/dialing.mp3'));
    } catch (e) {
      debugPrint('Could not play dialing sound: $e');
      // Fallback: Use system sound if asset not available
      await _playSystemDialingSound();
    }
  }

  /// Play ringing sound for incoming calls
  Future<void> playRingingSound() async {
    if (_isPlayingRingtone) return;
    
    _isPlayingRingtone = true;
    try {
      // Use built-in system sound for ringing
      await _audioPlayer.play(AssetSource('sounds/ringing.mp3'));
      
      // Loop the ringing sound
      _audioPlayer.onPlayerComplete.listen((_) {
        if (_isPlayingRingtone) {
          _audioPlayer.play(AssetSource('sounds/ringing.mp3'));
        }
      });
    } catch (e) {
      debugPrint('Could not play ringing sound: $e');
      // Fallback: Use system sound if asset not available
      await _playSystemRingingSound();
    }
  }

  /// Stop ringing sound
  void stopRingingSound() {
    _isPlayingRingtone = false;
    _audioPlayer.stop();
  }

  /// Play call connected sound
  Future<void> playCallConnectedSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/connected.mp3'));
    } catch (e) {
      debugPrint('Could not play connected sound: $e');
      // Fallback: Use system sound if asset not available
      await _playSystemConnectedSound();
    }
  }

  /// Play call ended sound
  Future<void> playCallEndedSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/call_ended.mp3'));
    } catch (e) {
      debugPrint('Could not play call ended sound: $e');
      // Fallback: Use system sound if asset not available
      await _playSystemEndedSound();
    }
  }

  /// Vibrate for incoming calls
  Future<void> vibrateForIncomingCall() async {
    try {
      bool? hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        // Vibrate in a pattern: vibrate, pause, vibrate, pause...
        await Vibration.vibrate(pattern: [0, 500, 200, 500]);
      }
    } catch (e) {
      debugPrint('Could not vibrate: $e');
    }
  }

  /// Vibrate once for call actions
  Future<void> vibrateOnce() async {
    try {
      bool? hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        await Vibration.vibrate(duration: 100);
      }
    } catch (e) {
      debugPrint('Could not vibrate: $e');
    }
  }

  /// Stop all sounds and vibration
  void stopAll() {
    _isPlayingRingtone = false;
    _audioPlayer.stop();
    Vibration.cancel();
  }

  /// Dispose resources
  void dispose() {
    stopAll();
    _audioPlayer.dispose();
  }

  // Fallback system sounds (using web audio APIs or simple beeps)
  Future<void> _playSystemDialingSound() async {
    // For web and mobile, we can use simple beeps or system sounds
    if (kIsWeb) {
      // Web fallback - use Web Audio API for simple tones
      _playWebTone(440, 200); // A4 note
    }
  }

  Future<void> _playSystemRingingSound() async {
    if (kIsWeb) {
      // Web fallback - play ringing pattern
      for (int i = 0; i < 3; i++) {
        await Future.delayed(Duration(milliseconds: 400));
        _playWebTone(800, 300); // Higher pitch for ringing
      }
    }
  }

  Future<void> _playSystemConnectedSound() async {
    if (kIsWeb) {
      _playWebTone(600, 200); // Pleasant connection tone
    }
  }

  Future<void> _playSystemEndedSound() async {
    if (kIsWeb) {
      _playWebTone(300, 300); // Lower tone for call end
    }
  }

  void _playWebTone(double frequency, int duration) {
    if (kIsWeb) {
      // Simple web audio implementation
      // This would require additional web-specific audio setup
      debugPrint('Playing web tone: ${frequency}Hz for ${duration}ms');
    }
  }
}

/// Call state enum for better state management
enum CallState {
  idle,      // Not in any call
  dialing,   // Outgoing call being initiated
  ringing,   // Incoming call ringing
  connecting, // Call is connecting
  connected, // Call is active
  ending,    // Call is ending
}
