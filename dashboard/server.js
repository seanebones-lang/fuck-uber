// Update renderMetrics():
// + `🟢 SCANNING ${metrics.scan.uber} | ${metrics.scan.lyft} (Cycle: ${metrics.cycle}ms)`
// Green pulse: box.style.fg = metrics.scanning ? 'green' : 'yellow';
// WS broadcast scan state
wss.clients.forEach(ws => ws.send(JSON.stringify({...metrics, scan: metrics.scan})));