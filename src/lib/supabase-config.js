const supabaseUrl = import.meta.env.PUBLIC_SUPABASE_URL;
const supabasePublishableKey = import.meta.env.PUBLIC_SUPABASE_PUBLISHABLE_KEY;

export function getPublicSupabaseConfig() {
  if (!supabaseUrl || !supabasePublishableKey) {
    throw new Error(
      'Supabase configuration is missing. Set PUBLIC_SUPABASE_URL and PUBLIC_SUPABASE_PUBLISHABLE_KEY.',
    );
  }

  let parsedUrl;

  try {
    parsedUrl = new URL(supabaseUrl);
  } catch {
    throw new Error('Supabase configuration is invalid.');
  }

  if (import.meta.env.DEV && parsedUrl.hostname !== '127.0.0.1') {
    throw new Error('Development Supabase configuration must use 127.0.0.1.');
  }

  return { supabaseUrl, supabasePublishableKey };
}
