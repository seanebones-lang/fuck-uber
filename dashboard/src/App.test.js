import React from 'react';
import { render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import App from './App';

test('renders app', () => {
  render(<App />);
  expect(screen.getByRole('heading', { name: /Destro dashboard/i })).toBeInTheDocument();
});

test('shows connection state', () => {
  render(<App />);
  expect(screen.getByText(/Connection:/)).toBeInTheDocument();
});

test('shows stats labels', () => {
  render(<App />);
  expect(screen.getByText(/Accepts:/)).toBeInTheDocument();
  expect(screen.getByText(/Rejects:/)).toBeInTheDocument();
});
