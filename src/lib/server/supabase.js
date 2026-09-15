import { createServerClient, parseCookieHeader } from '@supabase/ssr';
import { getPublicSupabaseConfig } from '../supabase-config.js';

export function createRequestSupabaseClient(request, cookies) {
  const { supabaseUrl, supabasePublishableKey } = getPublicSupabaseConfig();

  return createServerClient(supabaseUrl, supabasePublishableKey, {
    cookies: {
      getAll() {
        return parseCookieHeader(request.headers.get('Cookie') ?? '');
      },
      setAll(cookiesToSet) {
        for (const { name, value, options } of cookiesToSet) {
          cookies.set(name, value, options);
        }
      },
    },
  });
}
