# Calling System

Flutter + Node.js (Socket.IO) calling app using WebRTC (P2P).

## Features (implemented)

- **Auth**
  - Email/password registration + login (JWT)
  - Persistent login (Hive)
  - Profile + set a unique public **Call ID** (`call_user_id`)

- **Calling (1:1)**
  - Voice calls + video calls
  - Call states: dialing/ringing/connecting/connected/idle
  - In-call UI (timer + controls)
  - Sound + vibration (with fallback tones if assets missing)

- **Contacts & Search**
  - Search Call IDs with suggestions (excludes self)
  - Contacts sync + local cache

- **Call log**
  - Backend stores call history (`calls` table)
  - Frontend displays call history

- **Connectivity strategy**
  - **zrok first** with automatic **localhost fallback**
    - REST calls: fallback also triggers on `>=500` gateway/server errors
    - Socket.IO signaling: connects to primary, then fallback if primary fails

## Tech stack

- **Frontend**: Flutter, `flutter_webrtc`, `socket_io_client`, Hive
- **Backend**: Node.js + Express, Socket.IO
- **DB**: MySQL

## Quick start

## Database (run schema.sql first)

Before starting the backend, create the MySQL schema:

```bash
# from repo root
mysql -u <user> -p <database_name> < backend/schema.sql
```

Or inside MySQL:

```sql
SOURCE backend/schema.sql;
```

### Backend

```bash
cd backend
npm install
npm start
```

### Frontend

```bash
cd frontend
flutter pub get
flutter run
```

## Configuration

- **Frontend base URLs**: `frontend/lib/main.dart`
  - Primary (zrok): `https://...share.zrok.io`
  - Fallback (local): `http://localhost:5000`

- **Signaling default URL**: `frontend/lib/call_service.dart` (`kSignalingServerUrl`)
  - In practice the app initializes signaling using the same primary→fallback strategy.

## Optional sound assets

Place files in `frontend/assets/sounds/`:

- `dialing.mp3`
- `ringing.mp3`
- `connected.mp3`
- `call_ended.mp3`

If missing, the app falls back to generated tones.

## What’s left to implement

- **Reliable media across platforms**
  - Stabilize audio/video transfer across web↔mobile and mobile↔mobile.
  - Harden reconnection/ICE failure handling.

- **Group calls / Add participant mid-call**
  - Requires multi-peer (mesh) or SFU; current architecture is 1:1.
  - `call_participants` table is planned for membership tracking.

- **Native incoming call UX**
  - Android full-screen call notification / foreground service integration
  - iOS CallKit

- **iOS screen sharing**
  - Requires ReplayKit Broadcast Extension (native iOS target).

