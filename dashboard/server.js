const WebSocket = require('ws');

const PORT = process.env.PORT || 3000;
const wss = new WebSocket.Server({ port: PORT });

process.on('uncaughtException', (err) => {
  console.error('uncaughtException:', err.message);
  process.exit(1);
});
process.on('unhandledRejection', (reason) => {
  console.error('unhandledRejection:', String(reason));
  process.exit(1);
});

let clients = [];

// Aggregate stats from events for new clients and display
const stats = {
  accepts: 0,
  rejects: 0,
  uptime: 100,
  lastEventAt: null,
  conflictState: 'idle',
  sessionEarnings: 0,
  todayEarnings: 0,
};

function getStats() {
  return { ...stats, uptime: 100, lastEventAt: stats.lastEventAt };
}

function broadcast(data) {
  const payload = typeof data === 'string' ? data : JSON.stringify(data);
  clients.forEach((c) => {
    if (c.readyState === WebSocket.OPEN) c.send(payload);
  });
}

function handleEvent(msg) {
  try {
    const data = typeof msg === 'string' ? JSON.parse(msg) : msg;
    if (!data || typeof data !== 'object') return;
    if (data.type === 'decision') {
      if (data.decision === 'accept') stats.accepts += 1;
      else if (data.decision === 'reject') stats.rejects += 1;
    }
    if (data.type === 'action_result') {
      if (data.action === 'accept') stats.accepts += 1;
      else if (data.action === 'reject') stats.rejects += 1;
    }
    if (data.type === 'conflict_state' && data.state != null) stats.conflictState = data.state;
    if (data.type === 'earnings' && typeof data.session === 'number') stats.sessionEarnings = data.session;
    if (data.type === 'earnings' && typeof data.today === 'number') stats.todayEarnings = data.today;
    stats.lastEventAt = Date.now();
  } catch (err) {
    console.error('handleEvent error:', err.message);
  }
}

wss.on('connection', (ws) => {
  clients.push(ws);
  ws.send(JSON.stringify({ type: 'connected', stats: getStats() }));
  ws.on('message', (data) => {
    try {
      const raw = data.toString();
      handleEvent(raw);
      clients.forEach((c) => {
        if (c !== ws && c.readyState === WebSocket.OPEN) c.send(raw);
      });
    } catch (err) {
      console.error('WebSocket message handler error:', err.message);
    }
  });
  ws.on('close', () => {
    clients = clients.filter((c) => c !== ws);
  });
});

console.log(`Destro dashboard WebSocket listening on port ${PORT} (ws://localhost:${PORT})`);
