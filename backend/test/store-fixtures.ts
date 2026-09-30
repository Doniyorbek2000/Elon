import { execFileSync } from 'node:child_process';
import { createPrivateKey, createSign, generateKeyPairSync } from 'node:crypto';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const b64url = (input: Buffer | string) => Buffer.from(input).toString('base64url');

/**
 * Builds a throwaway "Apple" PKI with openssl: root → intermediate → leaf,
 * where the intermediate and leaf carry the marker extensions the verifier
 * insists on (1.2.840.113635.100.6.2.1 and 1.2.840.113635.100.6.11.1).
 */
export function createApplePki(options: { markers?: boolean } = {}) {
  const markers = options.markers ?? true;
  const dir = mkdtempSync(join(tmpdir(), 'apple-pki-'));
  const run = (...args: string[]) => execFileSync('openssl', args, { cwd: dir, stdio: 'pipe' });
  const ext = (name: string, body: string) => writeFileSync(join(dir, name), body);

  ext('root.cnf', '[v3]\nbasicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign\n');
  ext(
    'int.cnf',
    `[v3]\nbasicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign\n${markers ? '1.2.840.113635.100.6.2.1=ASN1:NULL\n' : ''}`,
  );
  ext(
    'leaf.cnf',
    `[v3]\nbasicConstraints=critical,CA:FALSE\n${markers ? '1.2.840.113635.100.6.11.1=ASN1:NULL\n' : ''}`,
  );

  for (const name of ['root', 'int', 'leaf'])
    run('ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', `${name}.key`);
  run(
    'req',
    '-new',
    '-x509',
    '-key',
    'root.key',
    '-subj',
    '/CN=Test Apple Root',
    '-days',
    '3650',
    '-out',
    'root.pem',
    '-config',
    'root.cnf',
    '-extensions',
    'v3',
  );
  run('req', '-new', '-key', 'int.key', '-subj', '/CN=Test Apple Intermediate', '-out', 'int.csr');
  run(
    'x509',
    '-req',
    '-in',
    'int.csr',
    '-CA',
    'root.pem',
    '-CAkey',
    'root.key',
    '-CAcreateserial',
    '-days',
    '3650',
    '-out',
    'int.pem',
    '-extfile',
    'int.cnf',
    '-extensions',
    'v3',
  );
  run('req', '-new', '-key', 'leaf.key', '-subj', '/CN=Test Apple Leaf', '-out', 'leaf.csr');
  run(
    'x509',
    '-req',
    '-in',
    'leaf.csr',
    '-CA',
    'int.pem',
    '-CAkey',
    'int.key',
    '-CAcreateserial',
    '-days',
    '3650',
    '-out',
    'leaf.pem',
    '-extfile',
    'leaf.cnf',
    '-extensions',
    'v3',
  );

  const der = (name: string) => readFileSync(join(dir, name), 'utf8').replace(/-----[A-Z ]+-----|\s/g, '');
  const rootPem = readFileSync(join(dir, 'root.pem'), 'utf8');
  const leafKey = readFileSync(join(dir, 'leaf.key'), 'utf8');

  /** Signs a payload the way App Store Server API / notifications do (JWS, ES256, x5c chain). */
  function signJws(payload: object): string {
    const header = { alg: 'ES256', x5c: [der('leaf.pem'), der('int.pem'), der('root.pem')] };
    const input = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
    const signature = createSign('SHA256')
      .update(input)
      .sign({ key: createPrivateKey(leafKey), dsaEncoding: 'ieee-p1363' });
    return `${input}.${b64url(signature)}`;
  }

  return { rootPem, signJws };
}

/** An App Store Connect API key (.p8): EC P-256, PKCS#8 PEM. */
export function createApiKey() {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  return {
    privatePem: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(),
    publicPem: publicKey.export({ type: 'spki', format: 'pem' }).toString(),
  };
}

/** A Google service account JSON with a fresh RSA key. */
export function createServiceAccount() {
  const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const privatePem = privateKey.export({ type: 'pkcs8', format: 'pem' }).toString();
  return {
    json: JSON.stringify({
      client_email: 'billing@bozor-test.iam.gserviceaccount.com',
      private_key: privatePem,
    }),
    publicPem: publicKey.export({ type: 'spki', format: 'pem' }).toString(),
  };
}
