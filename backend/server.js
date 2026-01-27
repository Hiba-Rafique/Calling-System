const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');

const app = express();
app.use(cors());

const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: "*" }
});

let onlineUsers = {};

io.on("connection", (socket) => {
  console.log("User connected:", socket.id);

  // Register user
  socket.on("register", (userId) => {
    onlineUsers[userId] = socket.id;
  });

  // Call someone
  socket.on("callUser", ({ userToCall, signalData, from }) => {
    if (onlineUsers[userToCall]) {
      io.to(onlineUsers[userToCall]).emit("incomingCall", { signal: signalData, from });
    }
  });

  // Answer call
  socket.on("answerCall", ({ to, signal }) => {
    if (onlineUsers[to]) {
      io.to(onlineUsers[to]).emit("callAccepted", signal);
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
      if (onlineUsers[user] === socket.id) delete onlineUsers[user];
    }
  });
});

server.listen(5000, () => console.log("Server running on port 5000"));
