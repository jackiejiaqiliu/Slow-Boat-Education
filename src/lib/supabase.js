import { createBrowserClient } from '@supabase/ssr';
import { getPublicSupabaseConfig } from './supabase-config.js';

const { supabaseUrl, supabasePublishableKey } = getPublicSupabaseConfig();

export const supabase = createBrowserClient(supabaseUrl, supabasePublishableKey);
