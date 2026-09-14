// Records the API calls the Mealime web app makes, so the export script can
// target the real endpoints instead of guessing at them.
//
// Guessing did not work: every candidate route returned 404 under every auth
// scheme, which means the base URL or the paths are wrong. The web app knows
// the right ones, so watch it.
//
// How to use:
//   1. Sign in at https://my.mealime.com.
//   2. Open the browser console (Cmd+Option+J in Chrome).
//   3. Paste this whole file and press enter.
//   4. Now click around the app: open your meal plan, open the grocery list,
//      open your favorites, open Your Recipes, and open two or three individual
//      recipes. Every request gets recorded.
//   5. Run:  __mealimeCapture.dump()
//      That prints a summary and copies it to your clipboard.
//
// Token values are redacted. The output keeps the header name and the scheme
// word (Bearer, Token) but replaces the secret with its length, so the summary
// is safe to paste into a chat or an issue.

(function captureMealimeApi() {
  const calls = [];
  const SENSITIVE = /authorization|token|cookie|api[-_]?key|session/i;

  function redact(name, value) {
    if (!SENSITIVE.test(name)) return value;
    const text = String(value ?? '');
    // Keep the scheme word so we can see how the token is presented.
    const match = text.match(/^(\w+)\s+(.*)$/);
    if (match) return `${match[1]} <redacted, ${match[2].length} chars>`;
    return `<redacted, ${text.length} chars>`;
  }

  function record(method, url, headers, status) {
    let absolute = url;
    try {
      absolute = new URL(url, location.origin).toString();
    } catch {
      // Keep whatever was passed in.
    }
    // Only interested in data calls, not images, fonts, or analytics pixels.
    if (/\.(png|jpe?g|gif|webp|svg|woff2?|css|js)(\?|$)/i.test(absolute)) return;
    calls.push({ method, url: absolute, headers, status });
  }

  const originalFetch = window.fetch;
  window.fetch = async function patchedFetch(input, init = {}) {
    const url = typeof input === 'string' ? input : input?.url;
    const method = (init.method ?? (typeof input === 'object' ? input?.method : null) ?? 'GET').toUpperCase();
    const headers = {};
    const source = init.headers ?? (typeof input === 'object' ? input?.headers : null);
    if (source) {
      const entries = typeof source.forEach === 'function'
        ? (() => { const out = []; source.forEach((v, k) => out.push([k, v])); return out; })()
        : Object.entries(source);
      for (const [k, v] of entries) headers[k] = redact(k, v);
    }
    const response = await originalFetch.apply(this, arguments);
    record(method, url, headers, response.status);
    return response;
  };

  const originalOpen = XMLHttpRequest.prototype.open;
  const originalSetHeader = XMLHttpRequest.prototype.setRequestHeader;
  const originalSend = XMLHttpRequest.prototype.send;

  XMLHttpRequest.prototype.open = function (method, url) {
    this.__capture = { method: String(method).toUpperCase(), url, headers: {} };
    return originalOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.setRequestHeader = function (name, value) {
    if (this.__capture) this.__capture.headers[name] = redact(name, value);
    return originalSetHeader.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function () {
    const capture = this.__capture;
    if (capture) {
      this.addEventListener('loadend', () => {
        record(capture.method, capture.url, capture.headers, this.status);
      });
    }
    return originalSend.apply(this, arguments);
  };

  window.__mealimeCapture = {
    calls,
    dump() {
      // One row per distinct method and path, with ids collapsed so the shape
      // of the route is visible rather than one line per recipe.
      const byRoute = new Map();
      for (const call of calls) {
        let shape = call.url;
        try {
          const parsed = new URL(call.url);
          const pathShape = parsed.pathname
            .replace(/\/[0-9a-f]{8}-[0-9a-f-]{27,}/gi, '/<uuid>')
            .replace(/\/\d+/g, '/<id>');
          shape = `${parsed.origin}${pathShape}`;
        } catch {
          // Keep the raw url.
        }
        const key = `${call.method} ${shape}`;
        const existing = byRoute.get(key);
        if (existing) {
          existing.count += 1;
          existing.statuses.add(call.status);
        } else {
          byRoute.set(key, { route: key, count: 1, statuses: new Set([call.status]), headers: call.headers, example: call.url });
        }
      }

      const summary = {
        capturedAt: new Date().toISOString(),
        origin: location.origin,
        totalCalls: calls.length,
        routes: [...byRoute.values()].map((r) => ({
          route: r.route,
          count: r.count,
          statuses: [...r.statuses],
          requestHeaders: r.headers,
          example: r.example,
        })),
      };

      const text = JSON.stringify(summary, null, 2);
      console.log(text);
      try {
        copy(text);
        console.log('%cCopied to clipboard.', 'color: green; font-weight: bold');
      } catch {
        console.log('Select the JSON above and copy it by hand.');
      }
      return summary;
    },
    reset() {
      calls.length = 0;
    },
  };

  console.log(
    '%cRecording Mealime API calls.',
    'color: green; font-weight: bold',
    '\nNow open your meal plan, grocery list, favorites, Your Recipes, and a few individual recipes.',
    '\nThen run: __mealimeCapture.dump()'
  );
})();
