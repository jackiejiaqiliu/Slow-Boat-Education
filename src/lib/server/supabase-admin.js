import { getSecret } from 'astro:env/server';
import { createClient } from '@supabase/supabase-js';
import { getPublicSupabaseConfig } from '../supabase-config.js';

const adminSecretName = 'SUPABASE_SECRET_KEY';

export function createAdminSupabaseClient() {
  const { supabaseUrl } = getPublicSupabaseConfig();
  const supabaseSecretKey = getSecret(adminSecretName);

  if (!supabaseSecretKey) {
    throw new Error('Server Supabase configuration is missing.');
  }

  return createClient(supabaseUrl, supabaseSecretKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
      detectSessionInUrl: false,
    },
  });
}
