export function isSameOriginRequest(request) {
  const origin = request.headers.get('Origin');

  if (!origin) {
    return false;
  }

  try {
    return new URL(origin).origin === new URL(request.url).origin;
  } catch {
    return false;
  }
}

export function rejectCrossOriginRequest(request) {
  if (isSameOriginRequest(request)) {
    return null;
  }

  return Response.json(
    { ok: false, error: 'Request origin is not allowed.' },
    { status: 403, headers: { 'Cache-Control': 'no-store' } },
  );
}
