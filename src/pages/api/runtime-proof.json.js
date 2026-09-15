import { isServerRuntimeConfigured } from '../../lib/server/runtime-config.js';

export const prerender = false;

export function GET() {
  return Response.json(
    {
      ok: true,
      serverRuntime: true,
      serverConfigPresent: isServerRuntimeConfigured(),
    },
    {
      headers: {
        'Cache-Control': 'no-store',
      },
    },
  );
}
