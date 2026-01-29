# Calling System

A real-time voice calling application built with Flutter (frontend) and Node.js with Socket.IO (backend) using WebRTC for peer-to-peer audio communication.

## Features

- Email/password registration + login (JWT)
- Persistent login (Hive)
- Set a unique public **Call ID** (`call_user_id`) used for calling
- Real-time voice calls and video calls between any two users
- WebRTC technology for peer-to-peer audio
- WebRTC peer-to-peer video (optional per call)
- Socket.IO signaling for call setup
- Professional calling interface with visual feedback
- Call states: Dialing, Ringing, Connecting, Connected
- Sound effects for call progress (with fallback)
- Vibration feedback on mobile devices
- Responsive UI for all screen sizes
- Cross-platform: Web, Android, iOS support
- Server URL strategy: **zrok first**, automatic **localhost fallback** when no response

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
1. Open the app in two devices/simulators
2. Create accounts (email/password)
3. Set a unique **Call ID** when prompted
4. Use **Voice Call** or **Video Call** to call another user by Call ID

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

### Auth Endpoints
- `POST /api/auth/register`
- `POST /api/auth/login`
- `GET /api/me` (JWT required)
- `POST /api/me/call-user-id` (JWT required)

### Database
The `users` table includes:
- `email` (unique)
- `password_hash`
- `call_user_id` (nullable, unique)

### Frontend Configuration
The app prefers the hosted **zrok** URL first, and automatically falls back to:
- `http://localhost:5000`

The same zrok-first strategy is used for:
- REST API requests (register/login/me/call-user-id)
- Socket.IO signaling

Login sessions are persisted using Hive (`frontend/lib/auth_service.dart`).

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

#### 4. "Camera permission denied" (Video Calls)
- Android: ensure these permissions exist in manifests:
  - `android.permission.CAMERA`
  - `android.permission.RECORD_AUDIO`
- iOS: ensure `Info.plist` contains:
  - `NSCameraUsageDescription`
  - `NSMicrophoneUsageDescription`
- After changing permissions, do a **full rebuild** (hot reload is not enough)
- If you previously tapped **Don't ask again** on Android, enable permissions manually in App Settings

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
