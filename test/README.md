# Beta Test Guide
1. iOS: Xcode Run + Uber/Lyft open
2. Trigger pings (manual/real)
3. Logs: `tail -f ~/Library/Logs/Mystro.log`
Target: 98% uptime, <60ms iOS

## Tests
- **iOS (Xcode)**: Add the MystroTests target, then Cmd+U or Product > Test. Tests cover CriteriaEngine, ProdDaemon.decide(), DaemonState, and ServiceReadinessStore.
- **Dashboard E2E**: From repo root, `pnpm i` then `node test/e2e-test.js` (start dashboard server first: `cd dashboard && npm run server`).
- **Chaos**: `node test/chaos-suite.js [runs]` (e.g. 500 runs) with server running.
- **Benchmark**: `node shared/benchmark.js` (no server: prints criteria checks; with server: sends mock events).