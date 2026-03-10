# Beta Test Guide
1. iOS: Xcode Run + Uber/Lyft open
2. Trigger pings (manual/real)
3. Logs: `tail -f ~/Library/Logs/Destro.log`
Target: 98% uptime, <60ms iOS

## Tests
- **iOS (Xcode)**: Add the DestroTests target, then Cmd+U or Product > Test. Tests cover CriteriaEngine, ProdDaemon.decide(), DaemonState, and ServiceReadinessStore.
- **Shared criteria (Vitest)**: From repo root: `pnpm i` then `pnpm test`.
- **Dashboard unit**: `cd dashboard && npm i && npm test -- --watchAll=false` (or `node node_modules/react-scripts/bin/react-scripts.js test --watchAll=false`).
- **Dashboard E2E**: From repo root, `pnpm i` then `node test/e2e-test.js`. Start dashboard server first: `cd dashboard && npm run server` (or `npm start` for server + client).
- **Chaos**: `node test/chaos-suite.js [runs]` (e.g. 500 runs) with server running.
- **Benchmark**: `pnpm run benchmark` (no server: prints criteria checks; with server: sends mock events).