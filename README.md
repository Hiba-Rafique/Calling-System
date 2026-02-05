# Calling System - Flutter Voice & Video Calling App

A complete Flutter-based calling application with WebRTC, real-time notifications, and cross-platform support for Android and iOS.

## Features

- **Voice & Video Calling** - WebRTC-powered real-time communication
- **Cross-Platform** - Android & iOS support with native features
- **Smart Notifications** - Background call notifications with Answer/Decline actions
- **Socket.IO Integration** - Real-time signaling and presence
- **Authentication** - Secure user login and session management
- **Persistent Storage** - User data and call history with Hive
- **Call Management** - Incoming/outgoing calls with proper state handling

## Prerequisites

### For Development:
- **Flutter SDK** (>= 3.0.0)
- **Dart SDK** (>= 3.0.0)
- **Android Studio** or **VS Code** with Flutter extension
- **Xcode** (for iOS development, macOS only)
- **Node.js** (for backend server)

### For Android:
- **Android SDK** (API level 21+)
- **Java 8+**
- **Physical Android device** or **Android Emulator**

### For iOS:
- **macOS** with Xcode 12+
- **iOS Simulator** or **Physical iOS device**
- **Apple Developer Account** (for device testing)

## 🛠️ Setup Instructions

### 1. Clone the Repository
```bash
git clone https://github.com/your-username/Calling-System.git
cd Calling-System
```

### 2. Backend Setup
```bash
# Navigate to backend directory
cd backend

# Install dependencies
npm install

# Start the server
npm start

# Server will run on http://localhost:5000
```

### 3. Flutter Setup

#### Install Flutter Dependencies
```bash
# Navigate to frontend directory
cd frontend

# Get Flutter dependencies
flutter pub get

# Clean previous builds
flutter clean
```

#### Android Setup
```bash
# Connect Android device or start emulator
flutter devices

# Run the app
flutter run

# Or build APK
flutter build apk --release
```

#### iOS Setup (macOS only)
```bash
# Install CocoaPods dependencies
cd frontend/ios
pod install
pod update
cd ..

# Run on iOS Simulator
flutter run -d "iPhone 14 Pro"

# Or build IPA
./build_ios.sh
```

### 4. Environment Configuration

#### Backend URL Configuration
Update the server URLs in `frontend/lib/main.dart`:
```dart
final primaryUrl = 'http://YOUR_SERVER_IP:5000';
final fallbackUrl = 'http://YOUR_SERVER_IP:5000';
```

#### Firebase Setup
1. Create a Firebase project at https://console.firebase.google.com
2. Download `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
3. Place files in:
   - `frontend/android/app/google-services.json`
   - `frontend/ios/Runner/GoogleService-Info.plist`

## 📱 Running the App

### Step 1: Start Backend Server
```bash
cd backend
npm install
npm start
# Server runs on http://localhost:5000
```

### Step 2: Start Flutter App

#### Option A: Development Mode
```bash
cd frontend
flutter run
# Choose your device when prompted
```

#### Option B: Chrome Web Version
```bash
cd frontend
flutter run -d chrome
# Opens in Chrome browser
```

#### Option C: Android Device
```bash
cd frontend
flutter devices
# Note your device ID
flutter run -d <device-id>
```

#### Option D: iOS Simulator (macOS only)
```bash
cd frontend
flutter run -d "iPhone 14 Pro"
```

### Step 3: Test the Application

1. **Create User Accounts**
   - Open app on two devices/browsers
   - Register different usernames (e.g., "john" and "hibar")
   - Login to both accounts

2. **Test Voice Calling**
   - User A calls User B
   - User B receives incoming call notification
   - User B can Answer or Decline
   - Test audio quality and connection

3. **Test Video Calling**
   - User A initiates video call to User B
   - Verify video stream works both ways
   - Test camera switching and mute functionality

4. **Test Background Notifications**
   - Put app in background
   - Make incoming call
   - Verify notification appears with Answer/Decline buttons
   - Test notification tap opens call screen

## Configuration Files

### Android Configuration
- `frontend/android/app/src/main/AndroidManifest.xml` - Permissions and activities
- `frontend/android/app/src/main/kotlin/MainActivity.kt` - Main activity and intent handling
- `frontend/android/app/src/main/kotlin/CallRingingForegroundService.kt` - Background notifications

### iOS Configuration
- `frontend/ios/Runner/Info.plist` - App permissions and background modes
- `frontend/ios/Podfile` - CocoaPods dependencies and iOS configuration
- `frontend/ios/ExportOptions.plist` - IPA export settings

### Flutter Configuration
- `frontend/lib/main.dart` - App initialization and routing
- `frontend/lib/call_service.dart` - WebRTC and signaling logic
- `frontend/pubspec.yaml` - Flutter dependencies

##  Building for Production

### Android APK
```bash
cd frontend
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### iOS IPA (macOS only)
```bash
cd frontend
./build_ios.sh
# Output: build/ios/ipa/Calling System.ipa
```

### Using Codemagic CI/CD
```bash
# Push to GitHub repository
git add .
git commit -m "Ready for production build"
git push origin main

# Codemagic will automatically build:
# - Android APK
# - iOS IPA
# - Deploy to TestFlight/App Store (configured)
```

## Troubleshooting

### Common Issues

#### **Flutter Build Errors**
```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter run
```

#### **Android Notification Issues**
- Check permissions in Settings > Apps > Calling System
- Verify background app optimization is disabled
- Check notification permissions are granted

#### **iOS Build Issues**
```bash
# Clean CocoaPods
cd frontend/ios
rm -rf Pods Podfile.lock
pod install
```

#### **WebRTC Connection Issues**
- Verify backend server is running
- Check firewall settings
- Ensure both devices are on same network
- Test with different browsers/devices

#### **Socket Connection Issues**
- Check backend server logs
- Verify server IP address in Flutter code
- Test with `curl http://localhost:5000`

### Debug Mode
Enable debug logging in `frontend/lib/main.dart`:
```dart
// Set to true for detailed logs
const bool DEBUG_MODE = true;
```

## API Reference

### Main Components

#### **CallService**
- `callUser(userId, video: false)` - Initiate outgoing call
- `acceptCall(from, offerData, callId)` - Accept incoming call
- `endCall()` - End current call
- `muteMicrophone(bool mute)` - Toggle microphone
- `switchCamera()` - Switch front/back camera

#### **AuthService**
- `login(username, password)` - User authentication
- `register(username, password)` - User registration
- `getCurrentUserId()` - Get logged-in user ID
- `saveToken(token)` - Save authentication token

#### **NotificationService**
- `showIncomingCallNotification(from, isVideo)` - Display call notification
- `cancelNotification(id)` - Cancel specific notification
- `clearAllNotifications()` - Clear all notifications



### Calling Capabilities
- **Voice & Video Calls**: High-quality WebRTC-based peer-to-peer communication
- **Multi-User Support**: Add participants to ongoing calls (up to 7 users)
- **Call States**: Comprehensive call state management (dialing, ringing, connecting, connected, idle)
- **In-Call UI**: Professional interface with timer, mute/unmute, speaker toggle, and camera controls
- **Audio/Video Controls**: Full control over audio input/output and camera during calls

### Contacts & Discovery
- **Smart Search**: Real-time Call ID search with intelligent suggestions
- **Contact Management**: Sync and cache contacts locally for quick access
- **User Directory**: Browse and discover other users on the platform

### Call History
- **Complete Logs**: Backend-stored call history with detailed metadata
- **Call Statistics**: Track call duration, participants, and timestamps
- **Missed Call Notifications**: Never miss an important call

### Connectivity & Reliability
- **Dual-Server Strategy**: Primary zrok tunnel with automatic localhost fallback
- **Intelligent Failover**: Automatic switching between servers on connection issues
- **Robust Signaling**: Socket.IO-based signaling with reconnection support
- **ICE/STUN/TURN Support**: NAT traversal with multiple fallback options

### Mobile Optimizations
- **Background Support**: Handle calls when app is in background
- **Vibration & Sound**: Native-like call notifications with vibration patterns
- **Platform Integration**: Optimized for both Android and iOS platforms

## Architecture

### Frontend (Flutter)
- **WebRTC Integration**: Peer-to-peer audio/video streaming
- **Socket.IO Client**: Real-time signaling for call establishment
- **State Management**: Efficient call state handling
- **Local Storage**: Hive for persistent data and caching

### Backend (Node.js)
- **Socket.IO Server**: Real-time signaling and call coordination
- **Room Management**: Multi-user call room support
- **MySQL Database**: User data, call logs, and contact management
- **REST API**: User authentication and profile management

### Signaling Flow
1. User registration with signaling server
2. Call initiation creates a room (even for 1:1 calls)
3. Offer/answer exchange via Socket.IO
4. ICE candidate exchange for NAT traversal
5. Direct peer-to-peer media connection established

## Quick Start

### Prerequisites
- Node.js 16+ 
- Flutter 3.0+
- MySQL 8.0+
- Android Studio / Xcode for mobile development

### Database Setup

```bash
# Create MySQL database
mysql -u <username> -p -e "CREATE DATABASE calling_system"

# Import schema
mysql -u <username> -p calling_system < backend/schema.sql
```

### Backend Installation

```bash
cd backend
npm install
cp .env.example .env  # Configure your environment variables
npm start
```

### Frontend Installation

```bash
cd frontend
flutter pub get
flutter run
```

## Configuration

### Environment Variables (Backend)
Create `.env` file in backend directory:
```env
DB_HOST=localhost
DB_USER=your_username
DB_PASSWORD=your_password
DB_NAME=calling_system
JWT_SECRET=your_jwt_secret
PORT=5000
```

### Frontend URLs
Configure primary and fallback URLs in `frontend/lib/main.dart`:
```dart
const _primaryBaseUrl = 'https://your-zrok-url.share.zrok.io';
const _fallbackBaseUrl = 'http://localhost:5000';
```

## API Endpoints

### Authentication
- `POST /api/auth/register` - User registration
- `POST /api/auth/login` - User login
- `GET /api/auth/profile` - Get user profile
- `PUT /api/auth/profile` - Update profile

### Users
- `GET /api/users/search?q=<query>` - Search users by Call ID

### Call Logs
- `GET /api/calls/history` - Get call history
- `POST /api/calls/log` - Log call details

## Socket.IO Events

### Call Management
- `register` - Register user with signaling server
- `callUser` - Initiate a call
- `incomingCall` - Receive incoming call notification
- `answerCall` - Answer an incoming call
- `callAccepted` - Call was accepted
- `endCall` - End active call

### Multi-User Support
- `inviteToRoom` - Invite user to existing call
- `acceptRoomInvite` - Accept room invitation
- `declineRoomInvite` - Decline room invitation
- `roomIceCandidate` - Exchange ICE candidates in room

### Signaling
- `iceCandidate` - Exchange ICE candidates for 1:1 calls
- `callFailed` - Call failed notification

## Optional Features

### Sound Assets
Place audio files in `frontend/assets/sounds/`:
- `dialing.mp3` - Outgoing call sound
- `ringing.mp3` - Incoming call sound  
- `connected.mp3` - Call established sound
- `call_ended.mp3` - Call terminated sound


## Development

### Project Structure
```
Calling-System/
├── backend/
│   ├── server.js          # Main server file
│   ├── schema.sql         # Database schema
│   └── package.json       # Dependencies
├── frontend/
│   ├── lib/
│   │   ├── main.dart      # App entry point
│   │   ├── call_service.dart # WebRTC & signaling
│   │   └── ...
│   └── pubspec.yaml       # Flutter dependencies
└── README.md
```

