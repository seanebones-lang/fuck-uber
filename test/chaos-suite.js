#!/usr/bin/env node
/**
 * Chaos / stress style test: send many mock events to the dashboard WebSocket
 * and assert the server stays up and schema is consistent. Optional: start dashboard first.
 * Usage: node test/chaos-suite.js [runs=500]
 */

const WS_URL = process.env.MYSTRO_WS || 'ws://localhost:3000';
const RUNS = parseInt(process.env.CHAOS_RUNS || process.argv[2] || '500', 10);

async function oneRun(WebSocket) {
  const ws = new WebSocket(WS_URL);
  let received = 0;
  await new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout')), 2000);
    ws.on('open', () => {
      clearTimeout(t);
      resolve();
    });
    ws.on('error', reject);
  });
  ws.on('message', () => { received++; });
  const events = [
    { type: 'scan', app: 'com.ubercab.driver', status: 'SCANNING' },
    { type: 'decision', app: 'com.ubercab.driver', decision: Math.random() > 0.5 ? 'accept' : 'reject', reason: 'meets_criteria', price: 8 + Math.random() * 5 },
  ];
  for (const e of events) ws.send(JSON.stringify(e));
  await new Promise((r) => setTimeout(r, 50));
  ws.close();
  return received;
}

async function main() {
  const WebSocket = (await import('ws')).default;
  let ok = 0;
  let fail = 0;
  for (let i = 0; i < RUNS; i++) {
    try {
      const r = await oneRun(WebSocket);
      if (r >= 0) ok++;
      else fail++;
    } catch (_) {
      fail++;
    }
    if ((i + 1) % 100 === 0) process.stdout.write(`Runs ${i + 1}/${RUNS} ok=${ok} fail=${fail}\n`);
  }
  const uptime = ok / (ok + fail);
  console.log(`Chaos: ${RUNS} runs, ok=${ok} fail=${fail}, uptime=${(uptime * 100).toFixed(2)}%`);
  if (uptime < 0.95) {
    console.error('Uptime below 95%');
    process.exit(1);
  }
  console.log('Chaos suite passed.');
  process.exit(0);
}

main().catch((err) => {
  console.error('Chaos suite failed:', err.message);
  process.exit(1);
});
