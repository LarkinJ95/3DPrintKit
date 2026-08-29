/**
 * Verification of Apple-signed JWS payloads (App Store Server Notifications V2
 * and StoreKit 2 signed transactions), using WebCrypto only.
 *
 * Apple signs with ES256 and ships the certificate chain in the JWS header's
 * `x5c` field: [leaf, intermediate, root]. Trusting the payload means proving
 * the chain terminates at Apple's own root — which is pinned below, never
 * fetched at runtime, so a compromised or spoofed chain cannot introduce its
 * own root.
 *
 * There is no code path here that returns a payload without a completed
 * signature check.
 */

// ---------------------------------------------------------------------------
// Pinned trust anchor
// ---------------------------------------------------------------------------

/**
 * Apple Root CA - G3 (ECDSA P-384), the anchor for App Store signing.
 *   subject/issuer  CN=Apple Root CA - G3, O=Apple Inc., C=US
 *   valid           2014-04-30 → 2039-04-30
 *   SHA-256         63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:
 *                   7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79
 */
export const APPLE_ROOT_CA_G3_BASE64 =
  "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwS" +
  "QXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9u" +
  "IEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcN" +
  "MTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBS" +
  "b290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y" +
  "aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49" +
  "AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtf" +
  "TjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517" +
  "IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySr" +
  "MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gA" +
  "MGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4" +
  "at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM" +
  "6BgD56KyKA==";

export class JwsVerificationError extends Error {}

// ---------------------------------------------------------------------------
// Minimal DER / ASN.1 reader
// ---------------------------------------------------------------------------

interface DerNode {
  tag: number;
  /** Contents, excluding tag and length bytes. */
  content: Uint8Array;
  /** The whole node including its header — needed to hash a TBSCertificate. */
  raw: Uint8Array;
  end: number;
}

function readNode(bytes: Uint8Array, offset: number): DerNode {
  if (offset + 2 > bytes.length) throw new JwsVerificationError("Truncated DER.");
  const start = offset;
  const tag = bytes[offset++] as number;

  let length = bytes[offset++] as number;
  if (length & 0x80) {
    const count = length & 0x7f;
    if (count === 0 || count > 4) throw new JwsVerificationError("Unsupported DER length.");
    length = 0;
    for (let i = 0; i < count; i++) length = (length << 8) | (bytes[offset++] as number);
  }
  const end = offset + length;
  if (end > bytes.length) throw new JwsVerificationError("DER length overruns buffer.");
  return { tag, content: bytes.subarray(offset, end), raw: bytes.subarray(start, end), end };
}

/** Read the sequence of nodes directly inside a constructed node. */
function children(node: DerNode): DerNode[] {
  const out: DerNode[] = [];
  let offset = 0;
  while (offset < node.content.length) {
    const child = readNode(node.content, offset);
    out.push(child);
    offset = child.end;
  }
  return out;
}

// ---------------------------------------------------------------------------
// X.509
// ---------------------------------------------------------------------------

export interface Certificate {
  /** DER of the TBSCertificate — the bytes the issuer signed. */
  tbs: Uint8Array;
  /** DER of SubjectPublicKeyInfo, importable straight into WebCrypto. */
  spki: Uint8Array;
  /** Signature over `tbs`, as raw r||s. */
  signature: Uint8Array;
  /** Curve of this certificate's own public key. */
  curve: "P-256" | "P-384";
  /** Curve of the signature algorithm used by its issuer. */
  signatureCurve: "P-256" | "P-384";
  notBefore: Date;
  notAfter: Date;
  der: Uint8Array;
}

const OID_EC_PUBLIC_KEY = "1.2.840.10045.2.1";
const OID_P256 = "1.2.840.10045.3.1.7";
const OID_P384 = "1.3.132.0.34";
const OID_ECDSA_SHA256 = "1.2.840.10045.4.3.2";
const OID_ECDSA_SHA384 = "1.2.840.10045.4.3.3";

function readOid(node: DerNode): string {
  const bytes = node.content;
  if (bytes.length === 0) throw new JwsVerificationError("Empty OID.");
  const first = bytes[0] as number;
  const parts = [Math.floor(first / 40), first % 40];
  let value = 0;
  for (let i = 1; i < bytes.length; i++) {
    const byte = bytes[i] as number;
    value = (value << 7) | (byte & 0x7f);
    if ((byte & 0x80) === 0) {
      parts.push(value);
      value = 0;
    }
  }
  return parts.join(".");
}

/** DER times are UTCTime (YYMMDDHHMMSSZ) or GeneralizedTime (YYYYMMDD…). */
function readTime(node: DerNode): Date {
  const text = new TextDecoder().decode(node.content);
  const generalized = node.tag === 0x18;
  const year = generalized
    ? Number(text.slice(0, 4))
    : 2000 + Number(text.slice(0, 2)) > 2049
      ? 1900 + Number(text.slice(0, 2))
      : 2000 + Number(text.slice(0, 2));
  const rest = generalized ? text.slice(4) : text.slice(2);
  const month = Number(rest.slice(0, 2));
  const day = Number(rest.slice(2, 4));
  const hour = Number(rest.slice(4, 6));
  const minute = Number(rest.slice(6, 8));
  const second = Number(rest.slice(8, 10) || "0");
  return new Date(Date.UTC(year, month - 1, day, hour, minute, second));
}

function curveForOid(oid: string): "P-256" | "P-384" {
  if (oid === OID_P256) return "P-256";
  if (oid === OID_P384) return "P-384";
  throw new JwsVerificationError(`Unsupported EC curve ${oid}.`);
}

function curveForSignatureOid(oid: string): "P-256" | "P-384" {
  if (oid === OID_ECDSA_SHA256) return "P-256";
  if (oid === OID_ECDSA_SHA384) return "P-384";
  throw new JwsVerificationError(`Unsupported signature algorithm ${oid}.`);
}

/**
 * An X.509 ECDSA signature is DER (SEQUENCE of two INTEGERs); WebCrypto wants
 * fixed-width r||s. Integers carry a leading zero when the high bit is set,
 * and may be shorter than the field — both cases are normalised here.
 */
function derSignatureToRaw(der: Uint8Array, fieldSize: number): Uint8Array {
  const sequence = readNode(der, 0);
  const [r, s] = children(sequence);
  if (!r || !s) throw new JwsVerificationError("Malformed ECDSA signature.");
  const out = new Uint8Array(fieldSize * 2);
  const place = (value: Uint8Array, offset: number) => {
    let bytes = value;
    while (bytes.length > 0 && bytes[0] === 0) bytes = bytes.subarray(1);
    if (bytes.length > fieldSize) throw new JwsVerificationError("ECDSA integer too large.");
    out.set(bytes, offset + fieldSize - bytes.length);
  };
  place(r.content, 0);
  place(s.content, fieldSize);
  return out;
}

const FIELD_SIZE: Record<"P-256" | "P-384", number> = { "P-256": 32, "P-384": 48 };

export function parseCertificate(der: Uint8Array): Certificate {
  const certificate = readNode(der, 0);
  const [tbsNode, algorithmNode, signatureNode] = children(certificate);
  if (!tbsNode || !algorithmNode || !signatureNode) {
    throw new JwsVerificationError("Malformed certificate.");
  }

  const tbsChildren = children(tbsNode);
  // Skip the optional [0] EXPLICIT version tag when present.
  let index = tbsChildren[0]?.tag === 0xa0 ? 1 : 0;
  index += 1; // serialNumber
  index += 1; // signature algorithm
  index += 1; // issuer
  const validity = tbsChildren[index++];
  index += 1; // subject
  const spkiNode = tbsChildren[index];
  if (!validity || !spkiNode) throw new JwsVerificationError("Certificate is missing fields.");

  const [notBeforeNode, notAfterNode] = children(validity);
  if (!notBeforeNode || !notAfterNode) throw new JwsVerificationError("Bad validity.");

  const [spkiAlgorithm] = children(spkiNode);
  if (!spkiAlgorithm) throw new JwsVerificationError("Bad SubjectPublicKeyInfo.");
  const [keyTypeOid, curveOid] = children(spkiAlgorithm);
  if (!keyTypeOid || !curveOid) throw new JwsVerificationError("Bad key algorithm.");
  if (readOid(keyTypeOid) !== OID_EC_PUBLIC_KEY) {
    throw new JwsVerificationError("Only EC certificates are accepted.");
  }
  const curve = curveForOid(readOid(curveOid));

  const [signatureAlgorithmOid] = children(algorithmNode);
  if (!signatureAlgorithmOid) throw new JwsVerificationError("Bad signature algorithm.");
  const signatureCurve = curveForSignatureOid(readOid(signatureAlgorithmOid));

  // BIT STRING content starts with the count of unused bits.
  const signatureBits = signatureNode.content.subarray(1);

  return {
    tbs: tbsNode.raw,
    spki: spkiNode.raw,
    signature: derSignatureToRaw(signatureBits, FIELD_SIZE[signatureCurve]),
    curve,
    signatureCurve,
    notBefore: readTime(notBeforeNode),
    notAfter: readTime(notAfterNode),
    der,
  };
}

async function importKey(certificate: Certificate): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "spki",
    certificate.spki as unknown as ArrayBuffer,
    { name: "ECDSA", namedCurve: certificate.curve },
    false,
    ["verify"],
  );
}

async function verifySignature(
  issuer: Certificate,
  subject: Certificate,
): Promise<boolean> {
  const key = await importKey(issuer);
  const hash = subject.signatureCurve === "P-384" ? "SHA-384" : "SHA-256";
  return crypto.subtle.verify(
    { name: "ECDSA", hash },
    key,
    subject.signature as unknown as ArrayBuffer,
    subject.tbs as unknown as ArrayBuffer,
  );
}

// ---------------------------------------------------------------------------
// Base64 helpers
// ---------------------------------------------------------------------------

function base64ToBytes(value: string): Uint8Array {
  const binary = atob(value);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

function base64UrlToBytes(value: string): Uint8Array {
  const padded = value.replaceAll("-", "+").replaceAll("_", "/");
  return base64ToBytes(padded + "=".repeat((4 - (padded.length % 4)) % 4));
}

// ---------------------------------------------------------------------------
// JWS verification
// ---------------------------------------------------------------------------

export interface VerifyOptions {
  /** Overridable so tests can pin their own root. Defaults to Apple Root CA G3. */
  rootCertificateBase64?: string;
  /** Defaults to now; injectable so certificate validity can be tested. */
  now?: Date;
}

/**
 * Verify an Apple JWS and return its decoded payload.
 *
 * Throws `JwsVerificationError` on any failure — a malformed header, a chain
 * that does not reach the pinned root, an expired certificate, or a bad
 * payload signature. There is no lenient mode.
 */
export async function verifyAppleJws<T>(jws: string, options: VerifyOptions = {}): Promise<T> {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new JwsVerificationError("JWS must have three parts.");
  const [headerPart, payloadPart, signaturePart] = parts as [string, string, string];

  let header: { alg?: string; x5c?: string[] };
  try {
    header = JSON.parse(new TextDecoder().decode(base64UrlToBytes(headerPart)));
  } catch {
    throw new JwsVerificationError("JWS header is not valid JSON.");
  }

  if (header.alg !== "ES256") {
    throw new JwsVerificationError(`Unexpected JWS algorithm ${header.alg ?? "(none)"}.`);
  }
  const chain = header.x5c;
  if (!Array.isArray(chain) || chain.length < 2) {
    throw new JwsVerificationError("JWS header is missing a certificate chain.");
  }

  const certificates = chain.map((entry) => parseCertificate(base64ToBytes(entry)));
  const leaf = certificates[0] as Certificate;

  // 1. Every certificate in the chain must be inside its validity window.
  const now = options.now ?? new Date();
  for (const certificate of certificates) {
    if (now < certificate.notBefore || now > certificate.notAfter) {
      throw new JwsVerificationError("A certificate in the chain is outside its validity period.");
    }
  }

  // 2. The chain's own root must be byte-identical to the pinned root. Comparing
  //    the DER (rather than just verifying a self-signature) is what stops an
  //    attacker supplying a self-consistent chain of their own.
  const pinned = base64ToBytes(options.rootCertificateBase64 ?? APPLE_ROOT_CA_G3_BASE64);
  const presentedRoot = certificates[certificates.length - 1] as Certificate;
  if (
    presentedRoot.der.length !== pinned.length ||
    !presentedRoot.der.every((byte, i) => byte === pinned[i])
  ) {
    throw new JwsVerificationError("Chain does not terminate at the pinned Apple root.");
  }

  // 3. Each certificate must be signed by the next one up.
  for (let i = 0; i < certificates.length - 1; i++) {
    const subject = certificates[i] as Certificate;
    const issuer = certificates[i + 1] as Certificate;
    if (!(await verifySignature(issuer, subject))) {
      throw new JwsVerificationError("Certificate chain signature is invalid.");
    }
  }

  // 4. The leaf must have signed the payload.
  const signingInput = new TextEncoder().encode(`${headerPart}.${payloadPart}`);
  const signature = base64UrlToBytes(signaturePart);
  const leafKey = await importKey(leaf);
  const signatureValid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    leafKey,
    signature as unknown as ArrayBuffer,
    signingInput as unknown as ArrayBuffer,
  );
  if (!signatureValid) throw new JwsVerificationError("JWS payload signature is invalid.");

  try {
    return JSON.parse(new TextDecoder().decode(base64UrlToBytes(payloadPart))) as T;
  } catch {
    throw new JwsVerificationError("JWS payload is not valid JSON.");
  }
}

/**
 * Decode a JWS payload **without** verifying it. Only for reading routing
 * fields (such as the notification UUID) from a payload that is verified
 * separately — never for anything that grants entitlement.
 */
export function decodeJwsPayloadUnsafe<T>(jws: string): T {
  const payload = jws.split(".")[1];
  if (!payload) throw new JwsVerificationError("JWS has no payload.");
  return JSON.parse(new TextDecoder().decode(base64UrlToBytes(payload))) as T;
}
