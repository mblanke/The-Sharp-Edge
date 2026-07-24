import { describe, expect, it } from 'vitest';
import { problemDetail } from './problem';

const res = (status: number, body: unknown) => ({
  status,
  json: async () => body
});

describe('problemDetail', () => {
  it('returns a plain string detail (RFC-7807 problem+json)', async () => {
    expect(await problemDetail(res(400, { detail: "'goulash' is a reference card" }))).toBe(
      "'goulash' is a reference card"
    );
  });

  it('flattens a FastAPI 422 validation array to field: msg, dropping the body prefix', async () => {
    const body = {
      detail: [
        { loc: ['body', 'base_yield'], msg: 'Input should be greater than or equal to 1' },
        { loc: ['body', 'title'], msg: 'Field required' }
      ]
    };
    expect(await problemDetail(res(422, body))).toBe(
      'base_yield: Input should be greater than or equal to 1; title: Field required'
    );
  });

  it('falls back to title when there is no detail', async () => {
    expect(await problemDetail(res(500, { title: 'Internal Server Error' }))).toBe(
      'Internal Server Error'
    );
  });

  it('falls back to a status message when the body is unusable', async () => {
    const bad = {
      status: 502,
      json: async () => {
        throw new Error('not json');
      }
    };
    expect(await problemDetail(bad)).toBe('API error 502');
  });
});
