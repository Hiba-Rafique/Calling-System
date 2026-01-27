# Audio Files for Calling System

This folder contains audio files for the calling app. The following files are expected:

## Required Audio Files:

1. **dialing.mp3** - Sound played when making an outgoing call
   - Duration: ~2 seconds
   - Content: Dialing tone (like traditional phone dialing)

2. **ringing.mp3** - Sound played for incoming calls
   - Duration: ~2 seconds (will loop)
   - Content: Phone ringing sound

3. **connected.mp3** - Sound played when call is successfully connected
   - Duration: ~1 second
   - Content: Positive connection sound

4. **call_ended.mp3** - Sound played when call ends
   - Duration: ~1 second
   - Content: Call termination sound

## Temporary Solution:

If you don't have these audio files, the app will fall back to web audio synthesis tones that play through the console. The app will still work, but without actual audio feedback.

## How to Add Audio Files:

1. Find or create short audio files with the above specifications
2. Place them in this folder
3. Make sure they are named exactly as listed above
4. Run `flutter pub get` to update assets

## Alternative:

You can also use online sound effects or record your own sounds for a more personalized experience.
