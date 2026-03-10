# Swarm perfection order

Checklist (tick as you implement or verify):

- [x] 1. Security
- [x] 2. Bug Hunter
- [x] 3. Code Review
- [x] 4. Testing
- [x] 5. Performance
- [x] 6. Accessibility
- [x] 7. Mobile
- [x] 8. Documentation
- [x] 9. UI/UX

---

Specialized agents were run in this priority order to perfect the app. Each agent had a focused task; results may appear in MCP/agent output or the grokcode dashboard.

| Order | Agent | Focus |
|-------|--------|--------|
| 1 | **Security** | Top 3 security/compliance risks (Keychain, network, entitlements, App Store); one fix each. |
| 2 | **Bug Hunter** | Top 3 bug risks or fragile patterns (force unwraps, races, error handling); file/area + fix. |
| 3 | **Code Review** | Top 3 quality improvements (clarity, maintainability, best practices). |
| 4 | **Testing** | Top 3 testing gaps or improvements (what to test, where, why). |
| 5 | **Performance** | Top 3 performance risks or optimizations (daemon, dashboard, React). |
| 6 | **Accessibility** | Top 3 a11y improvements (WCAG/AX, driver experience). |
| 7 | **Mobile** | Top 3 iOS-specific improvements (lifecycle, memory, background, App Store). |
| 8 | **Documentation** | Top 3 doc improvements (README, ENGINEERING_REPORT, comments). |
| 9 | **UI/UX** | Top 3 UI/UX improvements (clarity, feedback, flow for drivers). |

---

## Actions taken (orchestrate and execute all)

- **AppDelegate.swift** – Replaced `task as! BGAppRefreshTask` with a safe cast; added comment on iOS background time limits.
- **ServiceReadinessStore.swift** – Keychain: added `kSecAttrService` for app-scoped tokens; comment that we never log token values.
- **Dashboard (App.js)** – Connection label now shows "Connected" / "Disconnected"; added `role="status"`, `aria-live="polite"`, and `aria-label` for chart (a11y).
- **Dashboard (App.test.js)** – Added tests for connection state and stats labels.
- **ProdDaemon.swift** – Comment that scan loop is 30ms and to keep work minimal.
- **README.md** – Link to SWARM_PERFECTION_ORDER.md; dashboard test command in Test section.

**Next steps:** Re-run swarm agents after major changes; use this checklist for future passes.

---

## Continued (second pass)

- **Dashboard tests**: All 3 tests pass. `dashboard/package.json` test script now uses `node node_modules/.../react-scripts.js` so `npm test` works without react-scripts on PATH.
- **test/README.md**: Documented dashboard unit test command and clarified server vs `npm start`.

---

## Continued (third pass)

- **ENGINEERING_REPORT.md**: Section 9 (Testing) now lists shared + dashboard unit tests and points to test/README.md for the full matrix.
- **package.json**: Added `test:dashboard` script so from root you can run `pnpm test && pnpm run test:dashboard` for the full JS test suite.
