import { createRequestSupabaseClient } from '../../../lib/server/supabase.js';

export const prerender = false;

export async function GET({ request, cookies }) {
  const supabase = createRequestSupabaseClient(request, cookies);
  const { data, error } = await supabase.auth.getClaims();
  const userId = data?.claims?.sub;

  if (error || typeof userId !== 'string') {
    return Response.json(
      { authenticated: false },
      { status: 200, headers: { 'Cache-Control': 'no-store' } },
    );
  }

  return Response.json(
    { authenticated: true, userId },
    { status: 200, headers: { 'Cache-Control': 'no-store' } },
  );
}
