import React, { useState, useEffect } from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip } from 'recharts';

const WS_URL = process.env.REACT_APP_WS_URL || 'ws://localhost:3000';

function App() {
  const [statsHistory, setStatsHistory] = useState([]);
  const [stats, setStats] = useState({ accepts: 0, rejects: 0, uptime: 99.95, conflictState: 'idle', sessionEarnings: 0, todayEarnings: 0 });
  const [lastEvent, setLastEvent] = useState(null);
  const [wsState, setWsState] = useState('connecting');
  const [wsError, setWsError] = useState(null);

  useEffect(() => {
    const ws = new WebSocket(WS_URL);
    ws.onopen = () => {
      setWsState('open');
      setWsError(null);
    };
    ws.onclose = () => setWsState('closed');
    ws.onerror = () => {
      setWsState('error');
      setWsError('WebSocket connection error');
    };
    ws.onmessage = (e) => {
      try {
        const data = JSON.parse(e.data);
        if (data.type === 'connected' && data.stats) {
          setStats(data.stats);
          setStatsHistory((prev) => [...prev.slice(-19), { ...data.stats, time: new Date().toLocaleTimeString() }]);
          return;
        }
        if (data.type === 'decision' || data.type === 'action_result') {
          const isAccept = data.decision === 'accept' || data.action === 'accept';
          setStats((prev) => ({
            ...prev,
            accepts: isAccept ? prev.accepts + 1 : prev.accepts,
            rejects: isAccept ? prev.rejects : prev.rejects + 1,
          }));
          setStatsHistory((prev) => {
            const last = prev[prev.length - 1] || { accepts: 0, rejects: 0 };
            const next = {
              accepts: isAccept ? last.accepts + 1 : last.accepts,
              rejects: isAccept ? last.rejects : last.rejects + 1,
              time: new Date().toLocaleTimeString(),
            };
            return [...prev.slice(-19), next];
          });
        }
        setLastEvent(data);
      } catch (err) {
        console.error('WebSocket onmessage error:', err.message);
      }
    };
    return () => ws.close();
  }, []);

  return (
    <div>
      <h1>Destro Dashboard</h1>
      <p role="status" aria-live="polite" aria-atomic="true">
        Connection: {wsState === 'open' ? 'Connected' : wsState === 'closed' ? 'Disconnected' : wsState}{wsError && ` — ${wsError}`}
      </p>
      <p role="status" aria-live="polite">
        Accepts: {stats.accepts} | Rejects: {stats.rejects} | Uptime: {stats.uptime}%
      </p>
      <p role="status" aria-live="polite">
        Conflict: {stats.conflictState} | Session: ${stats.sessionEarnings?.toFixed(2) ?? '0.00'} | Today: ${stats.todayEarnings?.toFixed(2) ?? '0.00'}
      </p>
      {lastEvent && (
        <p style={{ fontSize: 12, color: '#888' }} role="status" aria-live="polite">
          Last: {lastEvent.type} {lastEvent.app && `· ${lastEvent.app}`} {lastEvent.reason && `· ${lastEvent.reason}`}
        </p>
      )}
      <div role="img" aria-label="Accepts and rejects over time">
        <LineChart width={600} height={300} data={statsHistory}>
        <CartesianGrid />
        <XAxis dataKey="time" />
        <YAxis />
        <Tooltip />
        <Line type="monotone" dataKey="accepts" stroke="#82ca9d" name="Accepts" />
        <Line type="monotone" dataKey="rejects" stroke="#ff7300" name="Rejects" />
      </LineChart>
      </div>
    </div>
  );
}

export default App;
