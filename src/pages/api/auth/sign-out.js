import { rejectCrossOriginRequest } from '../../../lib/server/same-origin.js';
import { createRequestSupabaseClient } from '../../../lib/server/supabase.js';

export const prerender = false;

export async function POST({ request, cookies }) {
  const originFailure = rejectCrossOriginRequest(request);

  if (originFailure) {
    return originFailure;
  }

  const supabase = createRequestSupabaseClient(request, cookies);
  const { error } = await supabase.auth.signOut({ scope: 'local' });

  if (error && error.name !== 'AuthSessionMissingError') {
    return Response.json(
      { ok: false, error: 'Unable to sign out.' },
      { status: 500, headers: { 'Cache-Control': 'no-store' } },
    );
  }

  return Response.json(
    { ok: true },
    { status: 200, headers: { 'Cache-Control': 'no-store' } },
  );
}
