import { describe, it, expect } from 'vitest';
import { FIXED_CRITERIA } from './criteria.js';

describe('FIXED_CRITERIA', () => {
  it('accepts offer with price >= 7, >= 0.90/mi, !shared, stops === 1', () => {
    expect(FIXED_CRITERIA({ price: 10, miles: 5, shared: false, stops: 1 })).toBe(true);
  });

  it('rejects offer below min price', () => {
    expect(FIXED_CRITERIA({ price: 5, miles: 5, shared: false, stops: 1 })).toBe(false);
  });

  it('rejects offer below min per-mile', () => {
    expect(FIXED_CRITERIA({ price: 8, miles: 20, shared: false, stops: 1 })).toBe(false);
  });

  it('rejects shared or multiple stops', () => {
    expect(FIXED_CRITERIA({ price: 10, miles: 5, shared: true, stops: 1 })).toBe(false);
    expect(FIXED_CRITERIA({ price: 10, miles: 5, shared: false, stops: 2 })).toBe(false);
  });
});
