import React, { useState, useEffect } from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';

const WS_URL = 'ws://localhost:3000';
const RECONNECT_DELAY_MS = 2000;
const RECONNECT_MAX_MS = 30000;

function App() {
  const [statsHistory, setStatsHistory] = useState([]);
  const [stats, setStats] = useState({ accepts: 0, rejects: 0, uptime: 100, conflictState: 'idle', sessionEarnings: 0, todayEarnings: 0 });
  const [lastEvent, setLastEvent] = useState(null);
  const [wsError, setWsError] = useState(null);
  const [wsConnected, setWsConnected] = useState(false);
  const reconnectTimeoutRef = React.useRef(null);
  const wsRef = React.useRef(null);
  const mountedRef = React.useRef(true);

  useEffect(() => {
    mountedRef.current = true;
    let delay = RECONNECT_DELAY_MS;

    function connect() {
      if (!mountedRef.current) return;
      const ws = new WebSocket(WS_URL);
      wsRef.current = ws;
      setWsError(null);
      setWsConnected(false);
      ws.onopen = () => {
        if (!mountedRef.current) return;
        setWsError(null);
        setWsConnected(true);
        delay = RECONNECT_DELAY_MS;
      };
      ws.onerror = () => {
        if (mountedRef.current) setWsError('WebSocket error');
      };
      ws.onclose = () => {
        if (!mountedRef.current) return;
        setWsConnected(false);
        setWsError('Dashboard disconnected. Reconnecting…');
        reconnectTimeoutRef.current = setTimeout(() => {
          connect();
          delay = Math.min(delay * 1.5, RECONNECT_MAX_MS);
        }, delay);
      };
      ws.onmessage = (e) => {
        try {
          const data = JSON.parse(e.data);
          if (!data) return;
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
          if (data.type === 'earnings') {
            setStats((prev) => ({
              ...prev,
              sessionEarnings: typeof data.session === 'number' ? data.session : prev.sessionEarnings,
              todayEarnings: typeof data.today === 'number' ? data.today : prev.todayEarnings,
            }));
          }
          if (data.type === 'conflict_state' && data.state != null) {
            setStats((prev) => ({ ...prev, conflictState: data.state }));
          }
          setLastEvent(data);
        } catch (err) {
          console.warn('Dashboard message parse error:', err);
        }
      };
    }

    connect();
    return () => {
      mountedRef.current = false;
      if (reconnectTimeoutRef.current) clearTimeout(reconnectTimeoutRef.current);
      if (wsRef.current) wsRef.current.close();
    };
  }, []);

  return (
    <div style={{ minHeight: '100vh', background: '#0f0f0f', color: '#e0e0e0', padding: 24, fontFamily: 'system-ui, sans-serif' }}>
      <h1 style={{ margin: 0, fontSize: 24, fontWeight: 600 }} aria-label="Destro Dashboard">Destro Dashboard</h1>
      <p aria-label="Connection status" style={{ marginTop: 8, marginBottom: 8, fontSize: 14, fontWeight: 500 }}>
        <span style={{ display: 'inline-block', width: 8, height: 8, borderRadius: 4, marginRight: 8, verticalAlign: 'middle', backgroundColor: wsConnected ? '#2e7d32' : (wsError ? '#c62828' : '#757575') }} aria-hidden />
        {wsConnected ? <span style={{ color: '#4caf50' }}>Connected</span> : <span style={{ color: wsError ? '#ef5350' : '#9e9e9e' }}>Disconnected</span>}
      </p>
      {wsError && <p role="alert" style={{ color: '#ef5350', marginTop: 4 }}>{wsError}</p>}
      <p style={{ color: '#b0b0b0', marginTop: 8 }} aria-label="Stats: accepts, rejects, uptime">Accepts: {stats.accepts} | Rejects: {stats.rejects} | Uptime: {stats.uptime}%</p>
      <p style={{ color: '#b0b0b0', marginTop: 4 }} aria-label="Conflict and earnings">Conflict: {stats.conflictState} | Session: ${stats.sessionEarnings?.toFixed(2) ?? '0.00'} | Today: ${stats.todayEarnings?.toFixed(2) ?? '0.00'}</p>
      {lastEvent && (
        <p style={{ fontSize: 14, color: '#aaa', marginTop: 12 }}>
          <strong style={{ color: '#ff6b00' }}>Last event:</strong> {lastEvent.type} {lastEvent.app && `· ${lastEvent.app}`} {lastEvent.reason && `· ${lastEvent.reason}`}
        </p>
      )}
      <div aria-label="Accepts and rejects over time" style={{ width: '100%', maxWidth: 600, minHeight: 300, marginTop: 20 }}>
        {statsHistory.length === 0 ? (
          <div style={{ padding: 24, background: '#1a1a1a', borderRadius: 8, color: '#9e9e9e', textAlign: 'center' }}>
            <p style={{ margin: 0, fontSize: 15 }}>
              {wsConnected
                ? 'Connected, no events yet. Go online in the app to see the chart.'
                : 'No data yet. Start the server and connect the app to see the chart.'}
            </p>
          </div>
        ) : (
          <ResponsiveContainer width="100%" height={300}>
            <LineChart data={statsHistory} margin={{ top: 8, right: 8, left: 0, bottom: 8 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#333" />
              <XAxis dataKey="time" stroke="#9e9e9e" label={{ value: 'Time', position: 'insideBottom', offset: -4, fill: '#9e9e9e' }} />
              <YAxis stroke="#9e9e9e" label={{ value: 'Count', angle: -90, position: 'insideLeft', fill: '#9e9e9e' }} />
              <Tooltip contentStyle={{ background: '#1a1a1a', border: '1px solid #333' }} labelStyle={{ color: '#e0e0e0' }} />
              <Line type="monotone" dataKey="accepts" stroke="#82ca9d" name="Accepts" />
              <Line type="monotone" dataKey="rejects" stroke="#ff6b00" name="Rejects" />
            </LineChart>
          </ResponsiveContainer>
        )}
      </div>
    </div>
  );
}

export default App;
