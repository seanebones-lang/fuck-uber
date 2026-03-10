#!/usr/bin/env node
/**
 * Benchmark / sanity run for Destro dashboard and criteria.
 * Run: node shared/benchmark.js
 * Optional: start dashboard server first (npm run start in dashboard) and this script will send mock events.
 */

const WS_URL = process.env.MYSTRO_WS || 'ws://localhost:3000';

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function run() {
  console.log('Destro benchmark – connecting to', WS_URL);
  let ws;
  try {
    const WebSocket = (await import('ws')).default;
    ws = new WebSocket(WS_URL);
    await new Promise((resolve, reject) => {
      ws.on('open', resolve);
      ws.on('error', reject);
      setTimeout(() => reject(new Error('Connection timeout')), 3000);
    });
  } catch (e) {
    console.log('No dashboard server reachable:', e.message);
    console.log('Criteria check (mirrors Swift CriteriaEngine):');
    const minPrice = 7;
    const minPerMile = 0.9;
    const offers = [
      { price: 10, miles: 5, shared: false, stops: 1 },
      { price: 5, miles: 5, shared: false, stops: 1 },
      { price: 8, miles: 20, shared: false, stops: 1 },
    ];
    for (const o of offers) {
      const pass =
        o.price >= minPrice &&
        o.miles > 0 &&
        o.price / o.miles >= minPerMile &&
        !o.shared &&
        o.stops === 1;
      console.log(`  $${o.price} ${o.miles}mi shared=${o.shared} stops=${o.stops} => ${pass ? 'ACCEPT' : 'REJECT'}`);
    }
    process.exit(0);
    return;
  }

  let accepts = 0;
  let rejects = 0;
  ws.on('message', (data) => {
    try {
      const d = JSON.parse(data.toString());
      if (d.type === 'decision' && d.decision === 'accept') accepts++;
      if (d.type === 'decision' && d.decision === 'reject') rejects++;
    } catch (_) {}
  });

  const events = [
    { type: 'decision', app: 'com.ubercab.driver', decision: 'accept', reason: 'meets_criteria', price: 10 },
    { type: 'decision', app: 'me.lyft.driver', decision: 'reject', reason: 'below_min_price', price: 5 },
  ];
  for (const ev of events) {
    ws.send(JSON.stringify(ev));
    await sleep(100);
  }
  await sleep(200);
  console.log('Sent', events.length, 'mock events. Accepts:', accepts, 'Rejects:', rejects);
  ws.close();
  process.exit(0);
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
