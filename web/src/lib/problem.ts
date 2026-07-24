/** Pull a human-readable message out of an RFC-7807 problem+json body, a FastAPI
 *  422 validation array, or a plain error response. No SvelteKit deps so it's
 *  unit-testable on its own. */
export async function problemDetail(res: {
  status: number;
  json: () => Promise<unknown>;
}): Promise<string> {
  try {
    const body = (await res.json()) as {
      detail?: unknown;
      title?: unknown;
    };
    if (typeof body?.detail === 'string') return body.detail;
    // FastAPI 422 validation errors arrive as detail: [{loc, msg, ...}]
    if (Array.isArray(body?.detail)) {
      return body.detail
        .map((e: { loc?: (string | number)[]; msg?: string }) => {
          const field = e.loc?.filter((p) => p !== 'body').join('.') ?? '';
          return field ? `${field}: ${e.msg}` : (e.msg ?? '');
        })
        .filter(Boolean)
        .join('; ');
    }
    if (typeof body?.title === 'string') return body.title;
  } catch {
    /* fall through to status text */
  }
  return `API error ${res.status}`;
}
