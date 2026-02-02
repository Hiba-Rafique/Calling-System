# Calling System

A real-time communication platform built with Flutter and Node.js, featuring peer-to-peer voice and video calls powered by WebRTC technology.

## Features

### Authentication & User Management
- **Secure Authentication**: Email/password registration with JWT token-based authentication
- **Persistent Sessions**: Automatic login using local storage (Hive)
- **Unique Call IDs**: Each user gets a unique public Call ID for easy connection
- **Profile Management**: Customizable user profiles

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

*Note: App falls back to generated tones if assets are missing*

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

### Testing
- Unit tests for business logic
- Integration tests for API endpoints
- Manual testing for WebRTC functionality

## Production Deployment

### Backend
- Use PM2 for process management
- Configure reverse proxy (nginx)
- Set up SSL certificates
- Configure firewall rules

### Frontend
- Build release APK/IPA
- Configure app signing
- Submit to app stores

## Security Considerations

- JWT tokens with expiration
- Input validation and sanitization
- Rate limiting on API endpoints
- Secure WebRTC configuration
- Database connection encryption

## Contributing

1. Fork the repository
2. Create feature branch
3. Commit changes
4. Push to branch
5. Create Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:
- Create an issue on GitHub
- Check existing documentation
- Review troubleshooting guide

