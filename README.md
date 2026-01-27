# Calling System

A real-time voice calling application built with Flutter (frontend) and Node.js with Socket.IO (backend) using WebRTC for peer-to-peer audio communication.

## Features

- Real-time voice calls between any two users
- WebRTC technology for peer-to-peer audio
- Socket.IO signaling for call setup
- Professional calling interface with visual feedback
- Call states: Dialing, Ringing, Connecting, Connected
- Sound effects for call progress (with fallback)
- Vibration feedback on mobile devices
- Responsive UI for all screen sizes
- Cross-platform: Web, Android, iOS support

## Architecture

```
┌─────────────────┐    Socket.IO     ┌─────────────────┐
│   Flutter App   │ ◄──────────────► │  Node.js Server │
│   (WebRTC P2P)  │    Signaling     │   (Port 5000)   │
└─────────────────┘                 └─────────────────┘
         ▲                                    ▲
         │                                    │
         └──────────── Direct Audio ───────────┘
              (WebRTC Peer Connection)
```

## Prerequisites

### For Backend:
- Node.js (v14 or higher)
- npm or yarn

### For Frontend:
- Flutter SDK (v3.0 or higher)
- Android Studio / VS Code
- For mobile: Android SDK, Xcode (iOS)

## Quick Start

### 1. Clone the Repository
```bash
git clone <repository-url>
cd Calling-System
```

### 2. Start the Backend Server
```bash
cd backend
npm install
npm start
```
The server will start on `http://localhost:5000`

### 3. Start the Flutter Frontend
```bash
cd frontend
flutter pub get
flutter run
```

### 4. Test the Application
1. Open the app in two browser windows/devices
2. Register with different user IDs (e.g., "user1", "user2")
3. Make calls between users!

## Platform-Specific Setup

### Web Development
```bash
cd frontend
flutter pub get
flutter run -d chrome
```

### Android Development
```bash
cd frontend
flutter pub get
flutter run -d android
# Ensure Android device is connected or emulator is running
```

### iOS Development
```bash
cd frontend
flutter pub get
flutter run -d ios
# Requires macOS and Xcode
```

## Configuration

### Backend Configuration
The backend runs on port 5000 by default. To change:
```javascript
// backend/server.js
server.listen(5000, () => console.log('Server running on port 5000'));
```

### Frontend Configuration
The frontend connects to `localhost:5000` by default. To change:
```dart
// frontend/lib/call_service.dart
await _callService.initialize(userId, serverUrl: 'http://localhost:5000');
```

## Audio Files (Optional)

Add these files to `frontend/assets/sounds/` for custom audio effects:
- `dialing.mp3` - Outgoing call sound
- `ringing.mp3` - Incoming call sound  
- `connected.mp3` - Call connected sound
- `call_ended.mp3` - Call ended sound

Note: The app works without these files using fallback tones.

## Troubleshooting

### Common Issues:

#### 1. "Backend server is not running"
```bash
# Solution: Start the backend
cd backend
npm start
```

#### 2. "WebSocket connection failed"
- Check if backend is running on port 5000
- Verify firewall settings
- Try using `http://localhost:5000` instead of IP

#### 3. "Audio not working"
- Check browser microphone permissions
- Ensure microphone is not muted
- Try different browsers (Chrome recommended)
- Check device microphone settings

#### 4. "Build failed on Android"
```bash
# Solution: Update Android SDK and NDK
cd frontend/android/app
# Edit build.gradle.kts:
# compileSdk = 36
# ndkVersion = "27.0.12077973"
```

#### 5. "Vibration plugin errors"
- Vibration only works on mobile devices
- Errors are normal on web - app still works

### Debug Mode:
Enable debug logging in the app:
```dart
// In call_service.dart, debugPrint statements show detailed logs
```

## Network Requirements

### For Local Testing:
- Both devices on same WiFi network
- Backend server accessible to both devices

### For Production:
- Deploy backend to cloud service (Heroku, AWS, etc.)
- Update frontend server URL
- Configure HTTPS for WebRTC to work properly

## Project Structure

```
Calling-System/
├── backend/
│   ├── node_modules/
│   ├── package.json
│   ├── package-lock.json
│   └── server.js
├── frontend/
│   ├── android/
│   ├── ios/
│   ├── lib/
│   │   ├── main.dart
│   │   ├── call_service.dart
│   │   ├── call_screen.dart
│   │   ├── registration_screen.dart
│   │   ├── calling_interface.dart
│   │   └── sound_manager.dart
│   ├── assets/
│   │   └── sounds/
│   ├── pubspec.yaml
│   └── README.md
└── README.md
```
