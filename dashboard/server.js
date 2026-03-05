const WebSocket = require('ws');

const PORT = 3000;
const wss = new WebSocket.Server({ port: PORT });

let clients = [];

// Aggregate stats from events for new clients and display
const stats = {
  accepts: 0,
  rejects: 0,
  uptime: 99.95,
  lastEventAt: null,
};

function broadcast(data) {
  const payload = typeof data === 'string' ? data : JSON.stringify(data);
  clients.forEach((c) => {
    if (c.readyState === WebSocket.OPEN) c.send(payload);
  });
}

function handleEvent(msg) {
  try {
    const data = typeof msg === 'string' ? JSON.parse(msg) : msg;
    if (data.type === 'decision') {
      if (data.decision === 'accept') stats.accepts += 1;
      else stats.rejects += 1;
    }
    if (data.type === 'action_result') {
      if (data.action === 'accept') stats.accepts += 1;
      else stats.rejects += 1;
    }
    stats.lastEventAt = Date.now();
  } catch (_) {}
}

wss.on('connection', (ws) => {
  clients.push(ws);
  ws.send(JSON.stringify({ type: 'connected', stats }));
  ws.on('message', (data) => {
    const raw = data.toString();
    handleEvent(raw);
    clients.forEach((c) => {
      if (c !== ws && c.readyState === WebSocket.OPEN) c.send(raw);
    });
  });
  ws.on('close', () => {
    clients = clients.filter((c) => c !== ws);
  });
});

console.log(`Mystro dashboard WebSocket on ws://localhost:${PORT}`);
