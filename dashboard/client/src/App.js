import React, { useState, useEffect } from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip } from 'recharts';

const WS_URL = 'ws://localhost:3000';

function App() {
  const [statsHistory, setStatsHistory] = useState([]);
  const [stats, setStats] = useState({ accepts: 0, rejects: 0, uptime: 99.95 });
  const [lastEvent, setLastEvent] = useState(null);

  useEffect(() => {
    const ws = new WebSocket(WS_URL);
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
      } catch (_) {}
    };
    return () => ws.close();
  }, []);

  return (
    <div>
      <h1>Mystro Dashboard</h1>
      <p>Accepts: {stats.accepts} | Rejects: {stats.rejects} | Uptime: {stats.uptime}%</p>
      {lastEvent && (
        <p style={{ fontSize: 12, color: '#888' }}>
          Last: {lastEvent.type} {lastEvent.app && `· ${lastEvent.app}`} {lastEvent.reason && `· ${lastEvent.reason}`}
        </p>
      )}
      <LineChart width={600} height={300} data={statsHistory}>
        <CartesianGrid />
        <XAxis dataKey="time" />
        <YAxis />
        <Tooltip />
        <Line type="monotone" dataKey="accepts" stroke="#82ca9d" name="Accepts" />
        <Line type="monotone" dataKey="rejects" stroke="#ff7300" name="Rejects" />
      </LineChart>
    </div>
  );
}

export default App;
