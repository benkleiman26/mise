// Read only HTTP client for the Mealime export.
//
// Two hard guards, because this script runs against a live account that we must
// not damage and cannot restore:
//   1. Only GET and HEAD are permitted. Any other method throws before a socket
//      is opened.
//   2. Only hosts on ALLOWED_HOSTS are permitted, so a bad argument cannot send
//      the auth token to some other server.

const ALLOWED_HOSTS = new Set(['api.mealime.com', 'my.mealime.com']);
const SAFE_METHODS = new Set(['GET', 'HEAD']);

export class ReadOnlyViolation extends Error {}
export class HttpError extends Error {
  constructor(message, { status, url, body }) {
    super(message);
    this.status = status;
    this.url = url;
    this.body = body;
  }
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Builds the request headers for a given auth scheme. Mealime's v2 API is not
 * publicly documented, so the scheme is configurable and `discover` reports
 * which one the server actually accepts.
 */
export function authHeaders(token, scheme = 'bearer') {
  switch (scheme) {
    case 'bearer':
      return { authorization: `Bearer ${token}` };
    case 'token':
      return { authorization: `Token token="${token}"` };
    case 'x-auth-token':
      return { 'x-auth-token': token };
    case 'x-user-token':
      return { 'x-user-token': token };
    case 'query':
      return {};
    default:
      throw new Error(`Unknown auth scheme: ${scheme}`);
  }
}

export const AUTH_SCHEMES = ['bearer', 'token', 'x-auth-token', 'x-user-token', 'query'];

export class ReadOnlyClient {
  /**
   * @param {object} options
   * @param {string} options.token      Mealime auth token, from the environment.
   * @param {string} [options.scheme]   Auth scheme, see AUTH_SCHEMES.
   * @param {number} [options.minIntervalMs] Politeness delay between requests.
   * @param {number} [options.maxRetries]
   * @param {(msg: string) => void} [options.log]
   */
  constructor({ token, scheme = 'bearer', minIntervalMs = 250, maxRetries = 4, log = () => {} }) {
    if (!token) throw new Error('Missing auth token');
    this.token = token;
    this.scheme = scheme;
    this.minIntervalMs = minIntervalMs;
    this.maxRetries = maxRetries;
    this.log = log;
    this.lastRequestAt = 0;
    this.requestCount = 0;
  }

  assertSafe(url, method) {
    if (!SAFE_METHODS.has(method)) {
      throw new ReadOnlyViolation(
        `Refusing ${method}. This tool is read only and may only issue GET or HEAD.`
      );
    }
    const host = new URL(url).hostname;
    if (!ALLOWED_HOSTS.has(host)) {
      throw new ReadOnlyViolation(
        `Refusing request to ${host}. Allowed hosts: ${[...ALLOWED_HOSTS].join(', ')}.`
      );
    }
  }

  async throttle() {
    const wait = this.lastRequestAt + this.minIntervalMs - Date.now();
    if (wait > 0) await sleep(wait);
    this.lastRequestAt = Date.now();
  }

  /**
   * Performs a GET and returns { status, headers, text, json }. Retries on 429
   * and 5xx with exponential backoff, honouring Retry-After when present.
   * Does not throw on 4xx other than 429, so callers can probe endpoints.
   */
  async get(url, { method = 'GET' } = {}) {
    const target = new URL(url);
    if (this.scheme === 'query') target.searchParams.set('auth_token', this.token);
    this.assertSafe(target.toString(), method);

    let attempt = 0;
    for (;;) {
      await this.throttle();
      this.requestCount += 1;
      let response;
      try {
        response = await fetch(target, {
          method,
          redirect: 'follow',
          headers: {
            accept: 'application/json, text/plain;q=0.8, */*;q=0.5',
            'user-agent': 'mise-mealime-export/1.0 (personal data export)',
            ...authHeaders(this.token, this.scheme),
          },
        });
      } catch (cause) {
        if (attempt >= this.maxRetries) {
          throw new HttpError(`Network failure after ${attempt} retries: ${cause.message}`, {
            status: 0,
            url: target.toString(),
          });
        }
        const delay = backoffMs(attempt);
        this.log(`network error, retrying in ${delay}ms: ${cause.message}`);
        await sleep(delay);
        attempt += 1;
        continue;
      }

      if ((response.status === 429 || response.status >= 500) && attempt < this.maxRetries) {
        const delay = retryAfterMs(response.headers.get('retry-after')) ?? backoffMs(attempt);
        this.log(`HTTP ${response.status}, retrying in ${delay}ms`);
        await sleep(delay);
        attempt += 1;
        continue;
      }

      const text = await response.text();
      return {
        status: response.status,
        headers: Object.fromEntries(response.headers),
        text,
        json: tryParseJson(text),
        url: target.toString(),
      };
    }
  }
}

export function backoffMs(attempt) {
  return Math.min(16000, 1000 * 2 ** attempt);
}

export function retryAfterMs(header) {
  if (!header) return null;
  const seconds = Number(header);
  if (Number.isFinite(seconds)) return Math.max(0, seconds * 1000);
  const date = Date.parse(header);
  return Number.isNaN(date) ? null : Math.max(0, date - Date.now());
}

export function tryParseJson(text) {
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}
