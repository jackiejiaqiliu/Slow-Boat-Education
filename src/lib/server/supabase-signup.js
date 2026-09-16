import { createClient } from '@supabase/supabase-js';
import { getPublicSupabaseConfig } from '../supabase-config.js';

export function createSignupSupabaseClient() {
  const { supabaseUrl, supabasePublishableKey } = getPublicSupabaseConfig();

  return createClient(supabaseUrl, supabasePublishableKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
      detectSessionInUrl: false,
    },
  });
}
