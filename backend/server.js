const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');

require('dotenv').config();
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const { getPool } = require('./db');

const app = express();
app.use(cors());
app.use(express.json());

const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: "*" }
});

let onlineUsers = {};

// Users who are currently in a call (ringing/connecting/connected)
const busyUsers = new Set();
// Bidirectional mapping of active peer (userId -> otherUserId)
const activePeer = {};

// Track DB call_id for active (ringing/connected) calls, keyed by pair
const activeCallDbId = {};

function pairKey(a, b) {
  return `${a}::${b}`;
}

async function resolveUserIdByCallId(callUserId) {
  if (!callUserId) return null;
  try {
    const pool = getPool();
    const [rows] = await pool.execute(
      'SELECT user_id FROM users WHERE call_user_id = ? LIMIT 1',
      [String(callUserId).trim()]
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

  // Register user
  socket.on("register", (userId) => {
    onlineUsers[userId] = socket.id;
  });

  // Call someone
  socket.on("callUser", ({ userToCall, signalData, from }) => {
    if (!userToCall || !from) return;

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
      // mark both busy as soon as call is initiated to avoid multiple incoming calls
      markBusyPair(from, userToCall);

      // Create call log row
      createCallLog(from, userToCall).then((callDbId) => {
        if (!callDbId) return;
        activeCallDbId[pairKey(from, userToCall)] = callDbId;
        activeCallDbId[pairKey(userToCall, from)] = callDbId;
      });

      io.to(onlineUsers[userToCall]).emit("incomingCall", { signal: signalData, from });
    } else {
      if (onlineUsers[from]) {
        io.to(onlineUsers[from]).emit("callFailed", { from: userToCall, reason: 'offline' });
      }

      // Log as missed (offline)
      createCallLog(from, userToCall).then((callDbId) => finalizeCallLog(callDbId, 'missed'));
    }
  });

  // Answer call
  socket.on("answerCall", ({ to, signal }) => {
    if (onlineUsers[to]) {
      io.to(onlineUsers[to]).emit("callAccepted", signal);
    }
  });

  // Reject call
  socket.on("rejectCall", ({ to, from, reason }) => {
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
  socket.on("iceCandidate", ({ to, candidate }) => {
    if (onlineUsers[to]) {
      io.to(onlineUsers[to]).emit("iceCandidate", candidate);
    }
  });

  socket.on("disconnect", () => {
    for (let user in onlineUsers) {
      if (onlineUsers[user] === socket.id) {
        delete onlineUsers[user];
        // If a user disappears while busy, clear their busy pair. Call will be marked missed
        const other = activePeer[user];
        const callDbId = other ? activeCallDbId[pairKey(user, other)] : null;
        if (other) {
          delete activeCallDbId[pairKey(user, other)];
          delete activeCallDbId[pairKey(other, user)];
        }
        finalizeCallLog(callDbId, 'missed');
        clearBusy(user);
      }
    }
  });

  socket.on("endCall", ({ to, from }) => {
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
