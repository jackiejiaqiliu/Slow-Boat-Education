import { rejectCrossOriginRequest } from '../../../lib/server/same-origin.js';
import { createRequestSupabaseClient } from '../../../lib/server/supabase.js';

export const prerender = false;

export async function POST({ request, cookies }) {
  const originFailure = rejectCrossOriginRequest(request);

  if (originFailure) {
    return originFailure;
  }

  if (!request.headers.get('Content-Type')?.toLowerCase().startsWith('application/json')) {
    return Response.json(
      { ok: false, error: 'Invalid request.' },
      { status: 400, headers: { 'Cache-Control': 'no-store' } },
    );
  }

  let credentials;

  try {
    credentials = await request.json();
  } catch {
    credentials = null;
  }

  const email = credentials?.email;
  const password = credentials?.password;

  if (
    typeof email !== 'string' ||
    !email.trim() ||
    email.length > 254 ||
    typeof password !== 'string' ||
    !password
  ) {
    return Response.json(
      { ok: false, error: 'Invalid request.' },
      { status: 400, headers: { 'Cache-Control': 'no-store' } },
    );
  }

  const supabase = createRequestSupabaseClient(request, cookies);
  const { error } = await supabase.auth.signInWithPassword({
    email: email.trim(),
    password,
  });

  if (error) {
    return Response.json(
      { ok: false, error: 'Invalid email or password.' },
      { status: 401, headers: { 'Cache-Control': 'no-store' } },
    );
  }

  return Response.json(
    { ok: true },
    { status: 200, headers: { 'Cache-Control': 'no-store' } },
  );
}
