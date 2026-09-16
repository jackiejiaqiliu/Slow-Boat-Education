export async function provisionProfile(adminSupabase, authUserId, profile) {
  const { data: existingProfile, error: lookupError } = await adminSupabase
    .from('profiles')
    .select('id, legal_name, username, marketing_consent, marketing_consent_at')
    .eq('id', authUserId)
    .maybeSingle();

  if (lookupError) {
    return { status: 'failed', errorCode: lookupError.code };
  }

  if (existingProfile) {
    const isValid =
      typeof existingProfile.legal_name === 'string' &&
      existingProfile.legal_name.trim() &&
      typeof existingProfile.username === 'string' &&
      /^[a-z0-9_]{3,30}$/.test(existingProfile.username) &&
      typeof existingProfile.marketing_consent === 'boolean' &&
      (!existingProfile.marketing_consent || existingProfile.marketing_consent_at);

    return { status: isValid ? 'existing_valid' : 'existing_invalid' };
  }

  const { error: insertError } = await adminSupabase.from('profiles').insert({
    id: authUserId,
    legal_name: profile.legalName,
    username: profile.username,
    nccaom_membership_id: profile.nccaomMembershipId,
    marketing_consent: profile.marketingConsent,
    marketing_consent_at: profile.marketingConsentAt,
  });

  if (!insertError) {
    return { status: 'created' };
  }

  if (insertError.code === '23505') {
    return { status: 'username_unavailable' };
  }

  return { status: 'failed', errorCode: insertError.code };
}
