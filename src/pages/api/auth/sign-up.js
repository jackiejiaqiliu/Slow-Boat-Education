import { provisionProfile } from '../../../lib/server/profile-provisioning.js';
import { rejectCrossOriginRequest } from '../../../lib/server/same-origin.js';
import { createAdminSupabaseClient } from '../../../lib/server/supabase-admin.js';
import { createSignupSupabaseClient } from '../../../lib/server/supabase-signup.js';

export const prerender = false;

const allowedFields = new Set([
  'email',
  'password',
  'legal_name',
  'username',
  'nccaom_membership_id',
  'marketing_consent',
]);

function invalidRequest() {
  return Response.json(
    { ok: false, error: 'Invalid account information.' },
    { status: 400, headers: { 'Cache-Control': 'no-store' } },
  );
}

function validateSignupInput(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    return null;
  }

  if (Object.keys(input).some((field) => !allowedFields.has(field))) {
    return null;
  }

  const email = typeof input.email === 'string' ? input.email.trim().toLowerCase() : '';
  const password = input.password;
  const legalName = typeof input.legal_name === 'string' ? input.legal_name.trim() : '';
  const username = typeof input.username === 'string' ? input.username.trim().toLowerCase() : '';
  const nccaomMembershipId =
    typeof input.nccaom_membership_id === 'string'
      ? input.nccaom_membership_id.trim() || null
      : input.nccaom_membership_id === undefined || input.nccaom_membership_id === null
        ? null
        : undefined;

  if (
    !email ||
    email.length > 254 ||
    typeof password !== 'string' ||
    !password ||
    !legalName ||
    legalName.length > 200 ||
    !/^[a-z0-9_]{3,30}$/.test(username) ||
    nccaomMembershipId === undefined ||
    (nccaomMembershipId && nccaomMembershipId.length > 100) ||
    typeof input.marketing_consent !== 'boolean'
  ) {
    return null;
  }

  return {
    email,
    password,
    profile: {
      legalName,
      username,
      nccaomMembershipId,
      marketingConsent: input.marketing_consent,
      marketingConsentAt: input.marketing_consent ? new Date().toISOString() : null,
    },
  };
}

async function compensateNewUser(adminSupabase, authUserId) {
  const { error: deleteError } = await adminSupabase.auth.admin.deleteUser(authUserId);

  if (deleteError) {
    console.error('Signup compensation could not delete the newly created Auth user.', {
      errorName: deleteError.name,
      status: deleteError.status,
    });
    return false;
  }

  return true;
}

async function clearProvisioningNonce(adminSupabase, authUserId) {
  const { error } = await adminSupabase.auth.admin.updateUserById(authUserId, {
    user_metadata: { signup_provisioning_nonce: null },
  });

  if (error) {
    console.error('Signup provisioning nonce cleanup failed.', {
      errorName: error.name,
      status: error.status,
    });
  }
}

export async function POST({ request }) {
  const originFailure = rejectCrossOriginRequest(request);

  if (originFailure) {
    return originFailure;
  }

  if (!request.headers.get('Content-Type')?.toLowerCase().startsWith('application/json')) {
    return invalidRequest();
  }

  let input;

  try {
    input = await request.json();
  } catch {
    input = null;
  }

  const signup = validateSignupInput(input);

  if (!signup) {
    return invalidRequest();
  }

  let adminSupabase;

  try {
    adminSupabase = createAdminSupabaseClient();
  } catch (error) {
    console.error('Signup server configuration is unavailable.', {
      errorName: error instanceof Error ? error.name : 'UnknownError',
    });
    return Response.json(
      { ok: false, error: 'Unable to create account.' },
      { status: 500, headers: { 'Cache-Control': 'no-store' } },
    );
  }

  const signupSupabase = createSignupSupabaseClient();
  const provisioningNonce = crypto.randomUUID();
  const { data: authData, error: signupError } = await signupSupabase.auth.signUp({
    email: signup.email,
    password: signup.password,
    options: {
      data: { signup_provisioning_nonce: provisioningNonce },
    },
  });

  if (signupError || !authData.user) {
    return Response.json(
      { ok: false, error: 'Unable to create account.' },
      { status: 400, headers: { 'Cache-Control': 'no-store' } },
    );
  }

  const { data: verifiedAuthData, error: verificationError } =
    await adminSupabase.auth.admin.getUserById(authData.user.id);
  const isGenuinelyNewUser =
    !verificationError &&
    verifiedAuthData.user?.user_metadata?.signup_provisioning_nonce === provisioningNonce;

  if (!isGenuinelyNewUser) {
    return Response.json(
      { ok: true, requiresEmailConfirmation: true },
      { status: 200, headers: { 'Cache-Control': 'no-store' } },
    );
  }

  const profileResult = await provisionProfile(adminSupabase, authData.user.id, signup.profile);

  if (profileResult.status === 'created' || profileResult.status === 'existing_valid') {
    await clearProvisioningNonce(adminSupabase, authData.user.id);
    return Response.json(
      { ok: true, requiresEmailConfirmation: !authData.session },
      {
        status: profileResult.status === 'created' ? 201 : 200,
        headers: { 'Cache-Control': 'no-store' },
      },
    );
  }

  const compensated = await compensateNewUser(adminSupabase, authData.user.id);

  if (!compensated) {
    console.error('Signup provisioning failed and compensation was incomplete.', {
      provisioningStatus: profileResult.status,
      errorCode: profileResult.errorCode,
    });
  }

  if (profileResult.status === 'username_unavailable') {
    return Response.json(
      { ok: false, error: 'Username unavailable.' },
      { status: 409, headers: { 'Cache-Control': 'no-store' } },
    );
  }

  console.error('Signup profile provisioning failed.', {
    errorCode: profileResult.errorCode,
    compensated,
  });

  return Response.json(
    { ok: false, error: 'Unable to create account.' },
    { status: 500, headers: { 'Cache-Control': 'no-store' } },
  );
}
