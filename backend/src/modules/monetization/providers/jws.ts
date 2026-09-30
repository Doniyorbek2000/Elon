import {
  X509Certificate,
  createPublicKey,
  createSign,
  verify,
  KeyObject,
  createPrivateKey,
} from 'node:crypto';

/** Base64url helpers (JWS/JWT use the URL-safe alphabet without padding). */
export const b64url = (input: Buffer | string): string => Buffer.from(input).toString('base64url');
export const fromB64url = (input: string): Buffer => Buffer.from(input, 'base64url');

/** PEM from raw text or base64 of the PEM (how secrets are usually injected). */
export function readPem(value: string): string {
  const trimmed = value.trim();
  if (trimmed.includes('-----BEGIN')) return trimmed.replace(/\\n/g, '\n');
  return Buffer.from(trimmed, 'base64').toString('utf8');
}

/** ES256 JWT (App Store Server API authentication). */
export function signEs256Jwt(
  header: Record<string, unknown>,
  payload: Record<string, unknown>,
  privateKeyPem: string,
): string {
  const signingInput = `${b64url(JSON.stringify({ ...header, alg: 'ES256' }))}.${b64url(JSON.stringify(payload))}`;
  const signature = createSign('SHA256')
    .update(signingInput)
    .sign({
      key: createPrivateKey(privateKeyPem),
      dsaEncoding: 'ieee-p1363',
    });
  return `${signingInput}.${b64url(signature)}`;
}

/** RS256 JWT (Google service-account assertion). */
export function signRs256Jwt(payload: Record<string, unknown>, privateKeyPem: string): string {
  const signingInput = `${b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64url(JSON.stringify(payload))}`;
  const signature = createSign('RSA-SHA256').update(signingInput).sign(createPrivateKey(privateKeyPem));
  return `${signingInput}.${b64url(signature)}`;
}

/** DER encodings of the Apple marker extensions (1.2.840.113635.100.6.x). */
const OID_LEAF = Buffer.from('060a2a864886f76364060b01', 'hex'); // 6.11.1 (Mac App Store receipt signing)
const OID_INTERMEDIATE = Buffer.from('060a2a864886f76364060201', 'hex'); // 6.2.1 (WWDR intermediate)

export class JwsError extends Error {}

/**
 * Verifies an App Store signed payload (JWS, ES256) exactly as Apple's
 * reference libraries do:
 *   1. `x5c` carries leaf → intermediate; the chain must end at the pinned Apple root,
 *   2. every certificate must be valid now and signed by its parent,
 *   3. the leaf/intermediate must carry Apple's marker extensions (otherwise any
 *      Apple-issued developer certificate could forge receipts),
 *   4. the JWS signature must verify with the leaf key.
 * Returns the decoded payload.
 */
export function verifyAppleJws<T>(token: string, rootPem: string, now = new Date()): T {
  const parts = token.split('.');
  if (parts.length !== 3) throw new JwsError('Malformed JWS');
  const header = JSON.parse(fromB64url(parts[0]).toString('utf8')) as { alg?: string; x5c?: string[] };
  if (header.alg !== 'ES256') throw new JwsError('Unexpected JWS algorithm');
  if (!Array.isArray(header.x5c) || header.x5c.length !== 3)
    throw new JwsError('Unexpected certificate chain');

  const [leaf, intermediate, rootFromHeader] = header.x5c.map(
    (c) => new X509Certificate(Buffer.from(c, 'base64')),
  );
  const root = new X509Certificate(rootPem);
  if (!rootFromHeader.raw.equals(root.raw)) throw new JwsError('Chain does not end at the pinned Apple root');

  const valid = (cert: X509Certificate) => new Date(cert.validFrom) <= now && now <= new Date(cert.validTo);
  if (![leaf, intermediate, root].every(valid)) throw new JwsError('Certificate expired or not yet valid');
  if (!leaf.verify(intermediate.publicKey) || !intermediate.verify(root.publicKey)) {
    throw new JwsError('Certificate chain signature mismatch');
  }
  if (!leaf.raw.includes(OID_LEAF) || !intermediate.raw.includes(OID_INTERMEDIATE)) {
    throw new JwsError('Missing Apple marker extensions');
  }

  const key: KeyObject = createPublicKey(leaf.publicKey.export({ type: 'spki', format: 'pem' }));
  const ok = verify(
    'SHA256',
    Buffer.from(`${parts[0]}.${parts[1]}`),
    { key, dsaEncoding: 'ieee-p1363' },
    fromB64url(parts[2]),
  );
  if (!ok) throw new JwsError('Bad JWS signature');
  return JSON.parse(fromB64url(parts[1]).toString('utf8')) as T;
}
