import { getSecret } from 'astro:env/server';

const runtimeProofKey = 'SERVER_RUNTIME_PROOF_VALUE';

export function isServerRuntimeConfigured() {
  return Boolean(getSecret(runtimeProofKey));
}
