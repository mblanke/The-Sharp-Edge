import { describe, expect, it } from 'vitest';
import fixture from '../../../shared/fixtures/scaling.convert_amount.json';
import { convertAmount, convertDisplay, type UnitSystem } from './scaling';

// The shared parity fixture (see shared/fixtures/README.md): generated from the
// Python, the specification for this port.
describe('convert_amount parity', () => {
  for (const c of fixture.cases) {
    it(c.id, () => {
      const [amount, unit] = convertAmount(c.args.amount, c.args.unit, c.args.system as UnitSystem);
      expect(Math.abs(amount - c.expect.amount)).toBeLessThan(fixture.tolerance ?? 0.001);
      expect(unit).toBe(c.expect.unit);
      expect(convertDisplay(c.args.amount, c.args.unit, c.args.system as UnitSystem)).toBe(c.expect.display);
    });
  }
});
