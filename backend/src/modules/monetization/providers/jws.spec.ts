import { createPublicKey, verify } from 'node:crypto';

import { createApiKey, createApplePki, createServiceAccount } from '../../../../test/store-fixtures';
import { JwsError, fromB64url, readPem, signEs256Jwt, signRs256Jwt, verifyAppleJws } from './jws';

describe('Apple JWS verification', () => {
  const pki = createApplePki();
  const payload = { transactionId: '2000000123456789', productId: 'uz.bozor.top7' };

  it('accepts a payload signed through the pinned chain', () => {
    expect(verifyAppleJws(pki.signJws(payload), pki.rootPem)).toEqual(payload);
  });

  it('rejects a chain that does not end at the pinned root', () => {
    const other = createApplePki();
    expect(() => verifyAppleJws(pki.signJws(payload), other.rootPem)).toThrow(/pinned Apple root/);
  });

  it('rejects certificates without Apple’s marker extensions (any Apple-issued cert must not be enough)', () => {
    const unmarked = createApplePki({ markers: false });
    expect(() => verifyAppleJws(unmarked.signJws(payload), unmarked.rootPem)).toThrow(/marker extensions/);
  });

  it('rejects tampered payloads and signatures', () => {
    const [h, p, s] = pki.signJws(payload).split('.');
    const forged = Buffer.from(JSON.stringify({ ...payload, productId: 'uz.bozor.vip' })).toString(
      'base64url',
    );
    expect(() => verifyAppleJws(`${h}.${forged}.${s}`, pki.rootPem)).toThrow(JwsError);
    expect(() => verifyAppleJws(`${h}.${p}.${s.slice(0, -4)}AAAA`, pki.rootPem)).toThrow(JwsError);
    expect(() => verifyAppleJws('not.a.jws.at.all', pki.rootPem)).toThrow(JwsError);
  });

  it('rejects expired chains', () => {
    const farFuture = new Date(Date.now() + 20 * 365 * 24 * 3600 * 1000);
    expect(() => verifyAppleJws(pki.signJws(payload), pki.rootPem, farFuture)).toThrow(/expired/);
  });
});

describe('JWT signing helpers', () => {
  it('ES256 tokens verify with the public key', () => {
    const key = createApiKey();
    const jwt = signEs256Jwt({ kid: 'ABC123' }, { iss: 'issuer' }, key.privatePem);
    const [h, p, s] = jwt.split('.');
    expect(JSON.parse(fromB64url(h).toString())).toMatchObject({ alg: 'ES256', kid: 'ABC123' });
    const ok = verify(
      'SHA256',
      Buffer.from(`${h}.${p}`),
      { key: createPublicKey(key.publicPem), dsaEncoding: 'ieee-p1363' },
      fromB64url(s),
    );
    expect(ok).toBe(true);
  });

  it('RS256 tokens verify with the public key', () => {
    const account = createServiceAccount();
    const pem = JSON.parse(account.json).private_key as string;
    const [h, p, s] = signRs256Jwt({ iss: 'x' }, pem).split('.');
    expect(
      verify('RSA-SHA256', Buffer.from(`${h}.${p}`), createPublicKey(account.publicPem), fromB64url(s)),
    ).toBe(true);
  });

  it('reads PEMs from raw text, escaped newlines and base64', () => {
    const pem = '-----BEGIN KEY-----\nabc\n-----END KEY-----';
    expect(readPem(pem)).toBe(pem);
    expect(readPem(pem.replace(/\n/g, '\\n'))).toBe(pem);
    expect(readPem(Buffer.from(pem).toString('base64'))).toBe(pem);
  });
});
