import { describe, expect, it } from 'vitest';
import golden from '../../../api/tests/fixtures/scaling_golden.json';
import { formatAmount } from './scaling';

// Shared table with api/tests/test_scaling.py — the client mirror must agree
// with the canonical server implementation row for row.
describe('scaling golden parity', () => {
  for (const c of golden.cases) {
    it(`${c.value} ${c.unit || '(count)'} -> ${c.expected}`, () => {
      expect(formatAmount(c.value, c.unit)).toBe(c.expected);
    });
  }
});
