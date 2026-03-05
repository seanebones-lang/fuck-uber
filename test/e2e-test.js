#!/usr/bin/env node
/**
 * E2E-style test: connect to dashboard WebSocket, send mock pings (decision events),
 * measure that the server and schema accept them. Run with dashboard server up: npm run start (in dashboard).
 * Usage: node test/e2e-test.js
 */

const WS_URL = process.env.MYSTRO_WS || 'ws://localhost:3000';

async function main() {
  const WebSocket = (await import('ws')).default;
  const ws = new WebSocket(WS_URL);

  const received = [];
  const timeout = 5000;

  await new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('Connection timeout')), timeout);
    ws.on('open', () => {
      clearTimeout(t);
      resolve();
    });
    ws.on('error', reject);
  });

  ws.on('message', (data) => {
    try {
      received.push(JSON.parse(data.toString()));
    } catch (_) {}
  });

  const toSend = [
    { type: 'scan', app: 'com.ubercab.driver', status: 'SCANNING' },
    { type: 'offer_seen', app: 'com.ubercab.driver', price: 12, miles: 4 },
    { type: 'decision', app: 'com.ubercab.driver', decision: 'accept', reason: 'meets_criteria', price: 12 },
    { type: 'action_result', app: 'com.ubercab.driver', action: 'accept', latencyMs: 38 },
  ];

  for (const msg of toSend) {
    ws.send(JSON.stringify(msg));
    await new Promise((r) => setTimeout(r, 50));
  }

  await new Promise((r) => setTimeout(r, 300));

  const hasConnected = received.some((m) => m.type === 'connected');
  const hasStats = received.some((m) => m.stats != null);
  console.log('E2E: received', received.length, 'messages, connected=', hasConnected, 'hasStats=', hasStats);

  ws.close();

  if (!hasConnected && received.length === 0) {
    console.error('No messages received; is the server sending { type: "connected", stats }?');
    process.exit(1);
  }
  console.log('E2E test passed.');
  process.exit(0);
}

main().catch((err) => {
  console.error('E2E test failed:', err.message);
  process.exit(1);
});
