const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');

require('dotenv').config();
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const { getPool } = require('./db');
const admin = require('firebase-admin');

const app = express();
app.use(cors());
app.use(express.json());

const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: "*" }
});

let onlineUsers = {};

async function upsertFcmToken(userId, token) {
  const pool = getPool();
  try {
    await pool.execute(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token)
       VALUES (?, ?)
       ON DUPLICATE KEY UPDATE fcm_token = VALUES(fcm_token)`,
      [Number(userId), String(token)]
    );
  } catch (e) {
    if (e && e.code === 'ER_NO_SUCH_TABLE') {
      await ensureUserFcmTokensTable();
      await pool.execute(
        `INSERT INTO user_fcm_tokens (user_id, fcm_token)
         VALUES (?, ?)
         ON DUPLICATE KEY UPDATE fcm_token = VALUES(fcm_token)`,
        [Number(userId), String(token)]
      );
      return;
    }
    throw e;
  }
}

async function getFcmTokenByUserId(userId) {
  const pool = getPool();
  let rows;
  try {
    [rows] = await pool.execute(
      'SELECT fcm_token FROM user_fcm_tokens WHERE user_id = ? LIMIT 1',
      [Number(userId)]
    );
  } catch (e) {
    if (e && e.code === 'ER_NO_SUCH_TABLE') {
      await ensureUserFcmTokensTable();
      [rows] = await pool.execute(
        'SELECT fcm_token FROM user_fcm_tokens WHERE user_id = ? LIMIT 1',
        [Number(userId)]
      );
    } else {
      throw e;
    }
  }
  if (!rows || rows.length === 0) return null;
  const t = rows[0].fcm_token;
  return t ? String(t) : null;
}

async function ensureUserFcmTokensTable() {
  const pool = getPool();
  await pool.execute(
    `CREATE TABLE IF NOT EXISTS user_fcm_tokens (
      user_id INT NOT NULL,
      fcm_token VARCHAR(512) NOT NULL,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (user_id),
      CONSTRAINT fk_user_fcm_tokens_user_id FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
    )`
  );
}

// Best-effort ensure at startup (prevents first request from failing on missing table).
ensureUserFcmTokensTable().catch((e) => {
  console.error('Failed to ensure user_fcm_tokens table:', e);
});

let firebaseEnabled = false;
try {
  // Configure with either a path to a service account JSON file, or the JSON itself.
  // - FIREBASE_SERVICE_ACCOUNT_PATH="/path/to/service-account.json"
  // - FIREBASE_SERVICE_ACCOUNT_JSON='{...}'
  const serviceAccountPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
  const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;

  if (serviceAccountPath) {
    // eslint-disable-next-line import/no-dynamic-require, global-require
    const serviceAccount = require(serviceAccountPath);
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    firebaseEnabled = true;
  } else if (serviceAccountJson) {
    const serviceAccount = JSON.parse(serviceAccountJson);
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    firebaseEnabled = true;
  } else {
    // If backend already sends FCM elsewhere, you can leave this disabled.
    firebaseEnabled = false;
  }
} catch (e) {
  console.error('Failed to initialize firebase-admin:', e);
  firebaseEnabled = false;
}

console.log('FCM firebaseEnabled:', firebaseEnabled);

async function sendFcmDataMessage(token, data) {
  if (!firebaseEnabled) return false;
  if (!token) return false;
  try {
    const messageId = await admin.messaging().send({
      token,
      android: {
        priority: 'high',
      },
      data: Object.fromEntries(
        Object.entries(data || {}).map(([k, v]) => [k, v == null ? '' : String(v)])
      ),
    });
    console.log('FCM send ok messageId=', messageId, 'type=', data && data.type);
    return true;
  } catch (e) {
    console.error('FCM send failed:', e);
    return false;
  }
}

// Users who are currently in a call (ringing/connecting/connected)
const busyUsers = new Set();
// Bidirectional mapping of active peer (userId -> otherUserId)
const activePeer = {};

// Room state for group calls.
// rooms[roomId] -> Set(userId)
const rooms = {};
// roomMeta[roomId] -> { isVideoCall: boolean }
const roomMeta = {};
// userRoom[userId] -> roomId
const userRoom = {};
// Pending invites (roomId::invitee -> inviter)
const pendingRoomInvites = {};

const MAX_ROOM_PARTICIPANTS = 7;

// Pending 1:1 call offers for offline callees.
// pendingCalls[calleeCallId] -> { from, signalData, roomId, createdAt, timeoutHandle }
const pendingCalls = {};
const PENDING_CALL_TIMEOUT_MS = 30000;

function clearPendingCallFor(calleeCallId, status, notifyCaller) {
  const pending = pendingCalls[calleeCallId];
  if (!pending) return;

  try {
    clearTimeout(pending.timeoutHandle);
  } catch (_) {}

  const from = pending.from;
  const to = calleeCallId;
  const roomId = pending.roomId;

  const callDbId = activeCallDbId[pairKey(from, to)];
  delete activeCallDbId[pairKey(from, to)];
  delete activeCallDbId[pairKey(to, from)];
  finalizeCallLog(callDbId, status || 'missed');

  if (roomId && rooms[roomId]) {
    delete rooms[roomId];
    delete roomMeta[roomId];
  }

  delete userRoom[from];
  delete userRoom[to];

  clearBusy(from);
  clearBusy(to);

  delete pendingCalls[calleeCallId];

  if (notifyCaller && onlineUsers[from]) {
    io.to(onlineUsers[from]).emit('callFailed', { from: to, reason: status || 'offline' });
  }
}

// Track DB call_id for active (ringing/connected) calls, keyed by pair
const activeCallDbId = {};

function pairKey(a, b) {
  return `${a}::${b}`;
}

async function resolveUserIdByCallId(callUserId) {
  if (!callUserId) return null;
  const raw = String(callUserId).trim();

  // Some clients may still send numeric internal user_id instead of call_user_id.
  // Support both to avoid silently skipping FCM for offline calls.
  if (/^\d+$/.test(raw)) {
    return Number(raw);
  }
  try {
    const pool = getPool();
    const [rows] = await pool.execute(
      'SELECT user_id FROM users WHERE call_user_id = ? LIMIT 1',
      [raw]
    );
    if (!rows || rows.length === 0) return null;
    return rows[0].user_id;
  } catch (_) {
    return null;
  }
}

async function createCallLog(fromCallId, toCallId) {
  const callerId = await resolveUserIdByCallId(fromCallId);
  const receiverId = await resolveUserIdByCallId(toCallId);
  if (!callerId || !receiverId) return null;

  const pool = getPool();
  const [result] = await pool.execute(
    "INSERT INTO calls (caller_id, receiver_id, call_status, started_at) VALUES (?, ?, 'ongoing', NOW())",
    [callerId, receiverId]
  );
  return result?.insertId ?? null;
}

async function finalizeCallLog(callDbId, status) {
  if (!callDbId) return;
  try {
    const pool = getPool();
    await pool.execute(
      'UPDATE calls SET call_status = ?, ended_at = NOW() WHERE call_id = ?',
      [status, callDbId]
    );
  } catch (_) {}
}

function markBusyPair(a, b) {
  if (!a || !b) return;
  busyUsers.add(a);
  busyUsers.add(b);
  activePeer[a] = b;
  activePeer[b] = a;
}

function clearBusy(userId) {
  if (!userId) return;
  const other = activePeer[userId];
  busyUsers.delete(userId);
  delete activePeer[userId];
  if (other) {
    busyUsers.delete(other);
    delete activePeer[other];
  }
}

function roomIdForInvite(roomId, invitee) {
  return `${roomId}::${invitee}`;
}

function ensureRoom(roomId) {
  if (!roomId) return null;
  if (!rooms[roomId]) {
    rooms[roomId] = new Set();
  }
  return rooms[roomId];
}

function isVideoCallFromSignal(signalData) {
  try {
    const sdp = signalData && signalData.sdp ? String(signalData.sdp) : '';
    if (!sdp) return false;
    // SDP media section for video
    return /m=video\s/i.test(sdp);
  } catch (_) {
    return false;
  }
}

function addUserToRoom(roomId, userId) {
  const set = ensureRoom(roomId);
  if (!set) return;
  set.add(userId);
  userRoom[userId] = roomId;
  busyUsers.add(userId);
}

function removeUserFromRoom(userId) {
  const roomId = userRoom[userId];
  if (!roomId) return;
  const set = rooms[roomId];
  if (set) {
    set.delete(userId);
    if (set.size === 0) {
      delete rooms[roomId];
    }
  }
  delete userRoom[userId];
  busyUsers.delete(userId);
}

function broadcastRoom(roomId, event, payload) {
  const set = rooms[roomId];
  if (!set) return;
  for (const uid of set) {
    const sid = onlineUsers[uid];
    if (sid) {
      io.to(sid).emit(event, payload);
    }
  }
}

function endRoom(roomId, endedBy) {
  const set = rooms[roomId];
  if (!set) return [];
  const participants = Array.from(set);
  for (const uid of participants) {
    clearBusy(uid);
    delete userRoom[uid];
  }
  delete rooms[roomId];
  delete roomMeta[roomId];

  for (const uid of participants) {
    if (uid === endedBy) continue;
    if (onlineUsers[uid]) {
      io.to(onlineUsers[uid]).emit('callEnded', { from: endedBy });
    }
  }

  return participants;
}

function makeRoomId(a, b) {
  return `${a}__${b}__${Date.now()}`;
}

function getJwtSecret() {
  const secret = process.env.JWT_SECRET;
  if (!secret) {
    throw new Error('Missing JWT_SECRET in environment');
  }
  return secret;
}

function authMiddleware(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing Authorization header' });
  }

  const token = authHeader.substring('Bearer '.length);
  try {
    const payload = jwt.verify(token, getJwtSecret());
    req.user = payload;
    return next();
  } catch (e) {
    return res.status(401).json({ error: 'Invalid token' });
  }
}

app.get('/health', (req, res) => {
  res.json({ ok: true });
});

app.post('/api/auth/register', async (req, res) => {
  try {
    const { first_name, last_name, email, password } = req.body || {};
    if (!first_name || !last_name || !email || !password) {
      return res.status(400).json({ error: 'first_name, last_name, email, password are required' });
    }

    const pool = getPool();
    const password_hash = await bcrypt.hash(password, 12);

    try {
      const [result] = await pool.execute(
        'INSERT INTO users (first_name, last_name, email, password_hash) VALUES (?, ?, ?, ?)',
        [first_name, last_name, email.toLowerCase(), password_hash]
      );
      return res.status(201).json({ user_id: result.insertId, email: email.toLowerCase() });
    } catch (err) {
      if (err && err.code === 'ER_DUP_ENTRY') {
        return res.status(409).json({ error: 'Email already exists' });
      }
      throw err;
    }
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Server error' });
  }
});

// Register/update FCM token for the current user.
// Data-only push requires the backend to know the device token.
app.post('/api/push/fcm-token', authMiddleware, async (req, res) => {
  try {
    const { token } = req.body || {};
    const t = token ? String(token).trim() : '';
    if (!t) {
      return res.status(400).json({ error: 'token is required' });
    }
    await upsertFcmToken(req.user.user_id, t);
    return res.json({ ok: true });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Server error' });
  }
});

// Debug helper to verify FCM is configured and whether the current user has a token.
app.get('/api/push/status', authMiddleware, async (req, res) => {
  try {
    const t = await getFcmTokenByUserId(req.user.user_id);
    return res.json({
      firebaseEnabled,
      hasToken: !!t,
    });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Server error' });
  }
});

app.post('/api/auth/login', async (req, res) => {
  try {
    const { email, password } = req.body || {};
    if (!email || !password) {
      return res.status(400).json({ error: 'email and password are required' });
    }

    const pool = getPool();
    const [rows] = await pool.execute(
      'SELECT user_id, email, password_hash, first_name, last_name FROM users WHERE email = ? LIMIT 1',
      [email.toLowerCase()]
    );

    if (!rows || rows.length === 0) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const user = rows[0];
    const ok = await bcrypt.compare(password, user.password_hash);
    if (!ok) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const token = jwt.sign(
      { user_id: user.user_id, email: user.email },
      getJwtSecret(),
      { expiresIn: '7d' }
    );

    return res.json({
      token,
      user: {
        user_id: user.user_id,
        email: user.email,
        first_name: user.first_name,
        last_name: user.last_name,
      },
    });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Server error' });
  }
});

app.get('/api/me', authMiddleware, async (req, res) => {
  try {
    const pool = getPool();
    const [rows] = await pool.execute(
      'SELECT user_id, first_name, last_name, email, call_user_id, created_at FROM users WHERE user_id = ? LIMIT 1',
      [req.user.user_id]
    );
    if (!rows || rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }
    return res.json(rows[0]);
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Server error' });
  }
});

app.get('/api/users/search', authMiddleware, async (req, res) => {
  try {
    const q = (req.query.q ?? '').toString().trim();
    if (!q) {
      return res.json([]);
    }

    const pool = getPool();
    const like = `${q}%`;
    const [rows] = await pool.execute(
      `SELECT user_id, first_name, last_name, call_user_id
       FROM users
       WHERE call_user_id IS NOT NULL
         AND call_user_id LIKE ?
       ORDER BY call_user_id ASC
       LIMIT 10`,
      [like]
    );

    const result = (rows || []).map((r) => ({
      user_id: r.user_id,
      first_name: r.first_name,
      last_name: r.last_name,
      call_user_id: r.call_user_id,
    }));

    return res.json(result);
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Server error' });
  }
});

app.post('/api/me/call-user-id', authMiddleware, async (req, res) => {
  try {
    const { call_user_id } = req.body || {};
    if (!call_user_id) {
      return res.status(400).json({ error: 'call_user_id is required' });
    }

    const value = String(call_user_id).trim();
    if (value.length < 3 || value.length > 30) {
      return res.status(400).json({ error: 'call_user_id must be 3-30 characters' });
    }

    if (!/^[a-zA-Z0-9_]+$/.test(value)) {
      return res.status(400).json({ error: 'call_user_id can only contain letters, numbers, and underscores' });
    }

    const pool = getPool();
    try {
      await pool.execute(
        'UPDATE users SET call_user_id = ? WHERE user_id = ?',
        [value, req.user.user_id]
      );
    } catch (err) {
      if (err && err.code === 'ER_DUP_ENTRY') {
        return res.status(409).json({ error: 'call_user_id already taken' });
      }
      throw err;
    }

    const [rows] = await pool.execute(
      'SELECT user_id, first_name, last_name, email, call_user_id, created_at FROM users WHERE user_id = ? LIMIT 1',
      [req.user.user_id]
    );

    if (!rows || rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    return res.json(rows[0]);
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Server error' });
  }
});

app.get('/api/contacts', authMiddleware, async (req, res) => {
  try {
    const pool = getPool();
    const [rows] = await pool.execute(
      `SELECT 
        c.contact_id,
        c.user_id,
        c.contact_user_id,
        c.nickname,
        c.created_at,
        u.first_name,
        u.last_name,
        u.email,
        u.call_user_id
      FROM contacts c
      JOIN users u ON u.user_id = c.contact_user_id
      WHERE c.user_id = ?
      ORDER BY c.created_at DESC`,
      [req.user.user_id]
    );
    return res.json(rows);
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Server error' });
  }
});

app.post('/api/contacts', authMiddleware, async (req, res) => {
  try {
    const { contact_user_id, contact_call_id, nickname } = req.body || {};
    if (!contact_user_id && !contact_call_id) {
      return res.status(400).json({ error: 'contact_user_id or contact_call_id is required' });
    }

    const pool = getPool();

    let resolvedContactUserId = contact_user_id;
    if (!resolvedContactUserId && contact_call_id) {
      const callIdValue = String(contact_call_id).trim();
      const [rows] = await pool.execute(
        'SELECT user_id FROM users WHERE call_user_id = ? LIMIT 1',
        [callIdValue]
      );
      if (!rows || rows.length === 0) {
        return res.status(404).json({ error: 'Contact not found for that Call ID' });
      }
      resolvedContactUserId = rows[0].user_id;
    }

    if (!resolvedContactUserId) {
      return res.status(400).json({ error: 'Invalid contact_user_id' });
    }

    if (Number(resolvedContactUserId) === Number(req.user.user_id)) {
      return res.status(400).json({ error: 'Cannot add yourself as a contact' });
    }

    const [userRows] = await pool.execute(
      'SELECT user_id FROM users WHERE user_id = ? LIMIT 1',
      [resolvedContactUserId]
    );
    if (!userRows || userRows.length === 0) {
      return res.status(404).json({ error: 'Contact user not found' });
    }

    try {
      const [result] = await pool.execute(
        'INSERT INTO contacts (user_id, contact_user_id, nickname) VALUES (?, ?, ?)',
        [req.user.user_id, resolvedContactUserId, nickname || null]
      );
      return res.status(201).json({ contact_id: result.insertId });
    } catch (err) {
      if (err && err.code === 'ER_DUP_ENTRY') {
        return res.status(409).json({ error: 'Contact already exists' });
      }
      throw err;
    }
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Server error' });
  }
});

app.delete('/api/contacts/:contact_id', authMiddleware, async (req, res) => {
  try {
    const { contact_id } = req.params;
    const pool = getPool();
    const [result] = await pool.execute(
      'DELETE FROM contacts WHERE contact_id = ? AND user_id = ?',
      [contact_id, req.user.user_id]
    );
    if (!result || result.affectedRows === 0) {
      return res.status(404).json({ error: 'Contact not found' });
    }
    return res.json({ ok: true });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Server error' });
  }
});

app.get('/api/calls', authMiddleware, async (req, res) => {
  try {
    const pool = getPool();
    const [rows] = await pool.execute(
      `SELECT 
        call_id,
        caller_id,
        receiver_id,
        call_status,
        started_at,
        ended_at,
        cu.call_user_id AS caller_call_user_id,
        ru.call_user_id AS receiver_call_user_id
      FROM calls
      JOIN users cu ON cu.user_id = calls.caller_id
      JOIN users ru ON ru.user_id = calls.receiver_id
      WHERE caller_id = ? OR receiver_id = ?
      ORDER BY started_at DESC, call_id DESC`,
      [req.user.user_id, req.user.user_id]
    );
    return res.json(rows);
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Server error' });
  }
});

app.post('/api/calls/start', authMiddleware, async (req, res) => {
  try {
    const { receiver_id } = req.body || {};
    if (!receiver_id) {
      return res.status(400).json({ error: 'receiver_id is required' });
    }

    const pool = getPool();
    const [userRows] = await pool.execute(
      'SELECT user_id FROM users WHERE user_id = ? LIMIT 1',
      [receiver_id]
    );
    if (!userRows || userRows.length === 0) {
      return res.status(404).json({ error: 'Receiver not found' });
    }

    const [result] = await pool.execute(
      "INSERT INTO calls (caller_id, receiver_id, call_status, started_at) VALUES (?, ?, 'ongoing', NOW())",
      [req.user.user_id, receiver_id]
    );
    return res.status(201).json({ call_id: result.insertId });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Server error' });
  }
});

app.post('/api/calls/end', authMiddleware, async (req, res) => {
  try {
    const { call_id, call_status } = req.body || {};
    if (!call_id || !call_status) {
      return res.status(400).json({ error: 'call_id and call_status are required' });
    }

    const pool = getPool();
    const [result] = await pool.execute(
      "UPDATE calls SET call_status = ?, ended_at = NOW() WHERE call_id = ? AND (caller_id = ? OR receiver_id = ?)",
      [call_status, call_id, req.user.user_id, req.user.user_id]
    );
    if (!result || result.affectedRows === 0) {
      return res.status(404).json({ error: 'Call not found' });
    }
    return res.json({ ok: true });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Server error' });
  }
});

io.on("connection", (socket) => {
  console.log("User connected:", socket.id);

  let socketUserId = null;

  // Register user
  socket.on("register", (userId) => {
    console.log('Registering user:', userId, 'socket:', socket.id);
    socketUserId = userId;
    // Only update if user not already online or if socket has changed
    if (!onlineUsers[userId] || onlineUsers[userId] !== socket.id) {
      onlineUsers[userId] = socket.id;
      console.log('Updated onlineUsers for:', userId);
    }
    console.log('Current online users:', Object.keys(onlineUsers));

    // If this user had a pending 1:1 call while offline, deliver it now.
    const pending = pendingCalls[userId];
    if (pending && onlineUsers[userId]) {
      try {
        console.log('Delivering pending incomingCall to:', userId, 'roomId:', pending.roomId, 'from:', pending.from);
        io.to(onlineUsers[userId]).emit('incomingCall', {
          signal: pending.signalData,
          from: pending.from,
          roomId: pending.roomId,
        });
      } catch (e) {
        console.error('Failed to deliver pending call:', e);
      }

      try {
        clearTimeout(pending.timeoutHandle);
      } catch (_) {}
      delete pendingCalls[userId];
    }
  });

  // Call someone
  socket.on("callUser", ({ userToCall, signalData, from }) => {
    if (!userToCall || !from) return;

    // Caller already in a room/call
    if (userRoom[from]) {
      if (onlineUsers[from]) {
        io.to(onlineUsers[from]).emit("callFailed", { from: userToCall, reason: 'busy' });
      }
      return;
    }

    // Caller is already busy
    if (busyUsers.has(from)) {
      if (onlineUsers[from]) {
        io.to(onlineUsers[from]).emit("callFailed", { from: userToCall, reason: 'busy' });
      }
      return;
    }

    // Callee is busy
    if (busyUsers.has(userToCall)) {
      if (onlineUsers[from]) {
        io.to(onlineUsers[from]).emit("callFailed", { from: userToCall, reason: 'busy' });
      }

      // Log as missed (busy)
      createCallLog(from, userToCall).then((callDbId) => finalizeCallLog(callDbId, 'missed'));
      return;
    }

    if (onlineUsers[userToCall]) {
      console.log('Callee found online:', userToCall, 'socket:', onlineUsers[userToCall]);
      // mark both busy as soon as call is initiated to avoid multiple incoming calls
      console.log('Marking busy pair...');
      markBusyPair(from, userToCall);
      console.log('Busy pair marked');

      // Create a room for this call (used for group calls later)
      console.log('Creating room...');
      const roomId = makeRoomId(from, userToCall);
      rooms[roomId] = new Set([from, userToCall]);
      roomMeta[roomId] = { isVideoCall: isVideoCallFromSignal(signalData) };
      userRoom[from] = roomId;
      userRoom[userToCall] = roomId;
      console.log('Room created:', roomId);

      // Create call log row
      console.log('Creating call log...');
      createCallLog(from, userToCall).then((callDbId) => {
        console.log('Call log created:', callDbId);
        if (!callDbId) return;
        activeCallDbId[pairKey(from, userToCall)] = callDbId;
        activeCallDbId[pairKey(userToCall, from)] = callDbId;
        console.log('Active call DB ID set');
      });

      console.log('About to emit incomingCall to:', onlineUsers[userToCall]);
      io.to(onlineUsers[userToCall]).emit("incomingCall", { signal: signalData, from, roomId });
      console.log('Emitted incomingCall');
    } else {
      console.log('Callee NOT found online:', userToCall);

      // Queue the call instead of failing immediately.
      // Caller will continue ringing; callee will be woken by FCM and when they register,
      // we deliver the pending offer via Socket.IO.

      // If there is already a pending call to this callee, treat as busy.
      if (pendingCalls[userToCall]) {
        if (onlineUsers[from]) {
          io.to(onlineUsers[from]).emit('callFailed', { from: userToCall, reason: 'busy' });
        }
        return;
      }

      // Mark busy pair to prevent other parallel calls while pending.
      markBusyPair(from, userToCall);

      // Create a room for this call so once callee comes online both sides share the same roomId.
      const roomId = makeRoomId(from, userToCall);
      rooms[roomId] = new Set([from, userToCall]);
      roomMeta[roomId] = { isVideoCall: isVideoCallFromSignal(signalData) };
      userRoom[from] = roomId;
      userRoom[userToCall] = roomId;

      // Create call log row and keep it active until timeout/cancel/end.
      createCallLog(from, userToCall).then((callDbId) => {
        if (!callDbId) return;
        activeCallDbId[pairKey(from, userToCall)] = callDbId;
        activeCallDbId[pairKey(userToCall, from)] = callDbId;
      });

      const timeoutHandle = setTimeout(() => {
        const pending = pendingCalls[userToCall];
        if (!pending) return;
        console.log('Pending call timed out for offline callee:', userToCall);

        const callDbId = activeCallDbId[pairKey(from, userToCall)];
        delete activeCallDbId[pairKey(from, userToCall)];
        delete activeCallDbId[pairKey(userToCall, from)];
        finalizeCallLog(callDbId, 'missed');

        // Clean up room and busy state.
        const rid = pending.roomId;
        if (rid && rooms[rid]) {
          delete rooms[rid];
          delete roomMeta[rid];
        }
        delete userRoom[from];
        delete userRoom[userToCall];
        clearBusy(from);
        clearBusy(userToCall);

        delete pendingCalls[userToCall];

        if (onlineUsers[from]) {
          io.to(onlineUsers[from]).emit('callFailed', { from: userToCall, reason: 'offline' });
        }
      }, PENDING_CALL_TIMEOUT_MS);

      pendingCalls[userToCall] = {
        from,
        signalData,
        roomId,
        createdAt: Date.now(),
        timeoutHandle,
      };

      // Send data-only FCM so Android can display a full-screen incoming call notification.
      resolveUserIdByCallId(userToCall).then((calleeInternalId) => {
        if (!calleeInternalId) {
          console.log('[FCM][offline] could not resolve user_id for callee=', userToCall);
          return;
        }
        return getFcmTokenByUserId(calleeInternalId)
          .then((token) => {
            if (!token) {
              console.log('[FCM][offline] no token for user_id=', calleeInternalId, 'callee=', userToCall);
              return false;
            }
            console.log('[FCM][offline] sending INCOMING_CALL to user_id=', calleeInternalId, 'callee=', userToCall);
            return sendFcmDataMessage(token, {
              type: 'INCOMING_CALL',
              from,
              to: userToCall,
              roomId,
              isVideoCall: roomMeta[roomId] && roomMeta[roomId].isVideoCall ? 'true' : 'false',
            });
          })
          .then((ok) => {
            if (ok) {
              console.log('[FCM][offline] send result=ok callee=', userToCall);
            } else {
              console.log('[FCM][offline] send result=skipped/failed callee=', userToCall, 'firebaseEnabled=', firebaseEnabled);
            }
            return ok;
          })
          .catch((e) => {
            console.error('[FCM][offline] error sending push callee=', userToCall, e);
            return false;
          });
      });
    }
  });

  // Answer call
  socket.on("answerCall", ({ to, signal, from, roomId }) => {
    if (!to || !signal) return;
    if (onlineUsers[to]) {
      if (roomId) {
        io.to(onlineUsers[to]).emit("callAccepted", { from, roomId, signal });
      } else {
        io.to(onlineUsers[to]).emit("callAccepted", signal);
      }
    }
  });

  // Reject call
  socket.on("rejectCall", ({ to, from, reason }) => {
    // If caller was offline-queued and callee rejects after coming online,
    // ensure pending state is cleaned up.
    if (from && pendingCalls[from] && pendingCalls[from].from === to) {
      clearPendingCallFor(from, 'missed', false);
    }

    const roomId = from ? userRoom[from] : null;
    if (roomId && rooms[roomId] && rooms[roomId].has(from)) {
      endRoom(roomId, from);
    }

    const callDbId = activeCallDbId[pairKey(from, to)];
    delete activeCallDbId[pairKey(from, to)];
    delete activeCallDbId[pairKey(to, from)];
    finalizeCallLog(callDbId, 'missed');

    // clear busy for both ends
    clearBusy(to);
    clearBusy(from);
    if (onlineUsers[to]) {
      io.to(onlineUsers[to]).emit("callRejected", { from, reason: reason || 'rejected' });
    }
  });

  // Caller cancels before callee answers
  socket.on('cancelCall', ({ to, from }) => {
    if (!to || !from) return;

    // Caller cancels while callee is still offline and call is queued.
    if (pendingCalls[to] && pendingCalls[to].from === from) {
      clearPendingCallFor(to, 'missed', false);
      return;
    }

    const roomId = userRoom[from];
    if (roomId && rooms[roomId] && rooms[roomId].has(from)) {
      endRoom(roomId, from);
    }

    const callDbId = activeCallDbId[pairKey(from, to)];
    delete activeCallDbId[pairKey(from, to)];
    delete activeCallDbId[pairKey(to, from)];
    finalizeCallLog(callDbId, 'missed');

    clearBusy(to);
    clearBusy(from);

    if (onlineUsers[to]) {
      io.to(onlineUsers[to]).emit('callCanceled', { from });
      // Backward compatible: older clients only listen for callEnded
      io.to(onlineUsers[to]).emit('callEnded', { from });
    }
  });

  // Call failed (timeout/ICE failure/etc)
  socket.on("callFailed", ({ to, from, reason }) => {
    // If caller reports failure while callee is still offline queued, clean it up.
    if (to && pendingCalls[to] && pendingCalls[to].from === from) {
      clearPendingCallFor(to, 'missed', false);
      return;
    }

    const roomId = from ? userRoom[from] : null;
    if (roomId && rooms[roomId] && rooms[roomId].has(from)) {
      endRoom(roomId, from);
    }

    const callDbId = activeCallDbId[pairKey(from, to)];
    delete activeCallDbId[pairKey(from, to)];
    delete activeCallDbId[pairKey(to, from)];
    finalizeCallLog(callDbId, 'missed');

    // clear busy for both ends
    clearBusy(to);
    clearBusy(from);
    if (onlineUsers[to]) {
      io.to(onlineUsers[to]).emit("callFailed", { from, reason: reason || 'failed' });
    }
  });

  // ICE candidates
  socket.on("iceCandidate", ({ to, candidate, from }) => {
    console.log('Received iceCandidate: to=', to, 'from=', from, 'hasCandidate=', !!candidate);
    if (!to || !candidate) {
      console.log('Missing to or candidate in iceCandidate');
      return;
    }
    if (onlineUsers[to]) {
      console.log('Forwarding ICE candidate to', to, 'via socket', onlineUsers[to]);
      io.to(onlineUsers[to]).emit("iceCandidate", { from, candidate });
    } else {
      console.log('User', to, 'not online for ICE candidate');
    }
  });

  // Invite a participant to an existing room
  socket.on('inviteToRoom', ({ roomId, to, from }) => {
    if (!roomId || !to || !from) return;

    const set = rooms[roomId];
    if (!set || !set.has(from)) {
      if (onlineUsers[from]) {
        io.to(onlineUsers[from]).emit('roomInviteFailed', { roomId, to, reason: 'invalid_room' });
      }
      return;
    }

    if (set.size >= MAX_ROOM_PARTICIPANTS) {
      if (onlineUsers[from]) {
        io.to(onlineUsers[from]).emit('roomInviteFailed', { roomId, to, reason: 'room_full' });
      }
      return;
    }

    if (busyUsers.has(to) || userRoom[to]) {
      if (onlineUsers[from]) {
        io.to(onlineUsers[from]).emit('roomInviteFailed', { roomId, to, reason: 'busy' });
      }
      return;
    }

    if (!onlineUsers[to]) {
      if (onlineUsers[from]) {
        io.to(onlineUsers[from]).emit('roomInviteFailed', { roomId, to, reason: 'offline' });
      }

      // Invitee offline: send data-only push so they can open the app and see an incoming invite.
      resolveUserIdByCallId(to).then((inviteeInternalId) => {
        if (!inviteeInternalId) return;
        getFcmTokenByUserId(inviteeInternalId)
          .then((token) => {
            if (!token) return;
            return sendFcmDataMessage(token, {
              type: 'INCOMING_CALL',
              from,
              roomId,
              to,
              isVideoCall: roomMeta[roomId] && roomMeta[roomId].isVideoCall ? 'true' : 'false',
            });
          })
          .catch(() => {});
      });
      return;
    }

    pendingRoomInvites[roomIdForInvite(roomId, to)] = from;
    io.to(onlineUsers[to]).emit('roomInvite', {
      roomId,
      from,
      participants: Array.from(set),
      isVideoCall: !!(roomMeta[roomId] && roomMeta[roomId].isVideoCall),
    });
  });

  socket.on('cancelRoomInvite', ({ roomId, to, from }) => {
    if (!roomId || !to || !from) return;
    delete pendingRoomInvites[roomIdForInvite(roomId, to)];
    if (onlineUsers[to]) {
      io.to(onlineUsers[to]).emit('roomInviteCanceled', { roomId, from });
    }
  });

  socket.on('declineRoomInvite', ({ roomId, from }) => {
    if (!roomId || !from) return;
    const key = roomIdForInvite(roomId, from);
    const inviter = pendingRoomInvites[key];
    delete pendingRoomInvites[key];
    if (inviter && onlineUsers[inviter]) {
      io.to(onlineUsers[inviter]).emit('roomInviteDeclined', { roomId, from });
    }
  });

  // Accept invite: join room and notify everyone.
  socket.on('acceptRoomInvite', ({ roomId, from }) => {
    if (!roomId || !from) return;
    const key = roomIdForInvite(roomId, from);
    const inviter = pendingRoomInvites[key];
    delete pendingRoomInvites[key];

    const set = rooms[roomId];
    if (!set) return;
    if (set.size >= MAX_ROOM_PARTICIPANTS) {
      if (onlineUsers[from]) {
        io.to(onlineUsers[from]).emit('roomJoinFailed', { roomId, reason: 'room_full' });
      }
      return;
    }

    addUserToRoom(roomId, from);

    // Notify joiner of current participants (including self)
    if (onlineUsers[from]) {
      io.to(onlineUsers[from]).emit('roomJoined', {
        roomId,
        participants: Array.from(rooms[roomId] || []),
        isVideoCall: !!(roomMeta[roomId] && roomMeta[roomId].isVideoCall),
      });
    }

    // Notify existing participants (including inviter) that a new participant joined
    broadcastRoom(roomId, 'roomParticipantJoined', { roomId, userId: from });

    if (inviter && onlineUsers[inviter]) {
      io.to(onlineUsers[inviter]).emit('roomInviteAccepted', { roomId, from });
    }
  });

  // Generic signaling within a room (offer/answer)
  socket.on('roomSignal', ({ roomId, to, from, signal }) => {
    if (!roomId || !to || !from || !signal) return;
    const set = rooms[roomId];
    if (!set || !set.has(from) || !set.has(to)) return;
    if (onlineUsers[to]) {
      io.to(onlineUsers[to]).emit('roomSignal', { roomId, from, signal });
    }
  });

  socket.on('roomIceCandidate', ({ roomId, to, from, candidate }) => {
    if (!roomId || !to || !from || !candidate) return;
    const set = rooms[roomId];
    if (!set || !set.has(from) || !set.has(to)) return;
    if (onlineUsers[to]) {
      io.to(onlineUsers[to]).emit('roomIceCandidate', { roomId, from, candidate });
    }
  });

  socket.on("disconnect", () => {
    const user = socketUserId;
    if (!user) return;

    if (onlineUsers[user] === socket.id) {
      delete onlineUsers[user];
    }

    // If a user disconnects while in a room, notify the room and remove them.
    const roomId = userRoom[user];
    if (roomId) {
      removeUserFromRoom(user);
      broadcastRoom(roomId, 'roomParticipantLeft', { roomId, userId: user });
    }

    // If a user had a queued pending call while offline (callee), clear it.
    if (pendingCalls[user]) {
      clearPendingCallFor(user, 'missed', false);
    }

    // If a user disappears while busy, clear their busy pair. Call will be marked missed
    const other = activePeer[user];
    const callDbId = other ? activeCallDbId[pairKey(user, other)] : null;
    if (other) {
      delete activeCallDbId[pairKey(user, other)];
      delete activeCallDbId[pairKey(other, user)];
    }
    finalizeCallLog(callDbId, 'missed');
    clearBusy(user);
  });

  socket.on("endCall", ({ to, from }) => {
    // If callee is still offline queued, treat as cancel/end and clean up.
    if (to && pendingCalls[to] && pendingCalls[to].from === from) {
      clearPendingCallFor(to, 'completed', false);
      return;
    }

    // If the caller is in a room, end the call for all participants.
    const roomId = from ? userRoom[from] : null;
    if (roomId && rooms[roomId] && rooms[roomId].has(from)) {
      endRoom(roomId, from);

      // finalize call log as completed for initial pair if we have it
      if (to && from) {
        const callDbId = activeCallDbId[pairKey(from, to)];
        delete activeCallDbId[pairKey(from, to)];
        delete activeCallDbId[pairKey(to, from)];
        finalizeCallLog(callDbId, 'completed');
      }

      return;
    }

    const callDbId = activeCallDbId[pairKey(from, to)];
    delete activeCallDbId[pairKey(from, to)];
    delete activeCallDbId[pairKey(to, from)];
    finalizeCallLog(callDbId, 'completed');

    clearBusy(to);
    clearBusy(from);
    if (onlineUsers[to]) {
      io.to(onlineUsers[to]).emit("callEnded", { from });
    }
  });
});
const PORT = process.env.PORT ? Number(process.env.PORT) : 5000;
server.listen(PORT, () => console.log(`Server running on port ${PORT}`));
