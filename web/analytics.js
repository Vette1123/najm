// Site analytics: one cookieless beacon per event to the portfolio's PostHog relay
// (www.mohamedgado.com/ingest/e, which adds the country and forwards to PostHog EU).
// No SDK, no cookie, nothing stored but the owner's opt-out flag. The Najm app
// itself sends nothing; this file only runs on the website.
//
// Every reader-facing link carries ?s=<source> (marketing/tracked-links.md), sent
// as utm_source so PostHog's source breakdowns read it.

export const INGEST_URL = "https://www.mohamedgado.com/ingest/e";
// PostHog's public project token (the same one the portfolio ships in its bundle).
export const POSTHOG_KEY = "phc_mTuqCSZxECXYHxrPbEK5bXkxKUpEG32frvfZNsaMS6U7";
export const SITE_HOST = "najm.mohamedgado.com";
export const OPT_OUT_KEY = "va-ignore";

// The typed event map: track() takes only these, and each has an area.
export const EVENT_AREA = Object.freeze({
  $pageview: "traffic",
  not_found: "health",
  download_clicked: "conversion",
  outbound_clicked: "conversion",
});

const SYNTHETIC_UA = /Chrome-Lighthouse|HeadlessChrome|PTST|GTmetrix|bot|crawl|spider/i;

/** Production host, a real browser, and not the owner (?va-ignore=1 latches the opt-out). */
export function shouldSend({ hostname, userAgent, webdriver, search, store }) {
  if (hostname !== SITE_HOST) return false;
  if (webdriver || SYNTHETIC_UA.test(userAgent)) return false;
  try {
    const flag = new URLSearchParams(search).get(OPT_OUT_KEY);
    if (flag === "1") store.setItem(OPT_OUT_KEY, "1");
    if (flag === "0") store.removeItem(OPT_OUT_KEY);
    return store.getItem(OPT_OUT_KEY) !== "1";
  } catch {
    return true; // Storage blocked: count the visit.
  }
}

/** ?s=<source> plus any utm_* the link carried. */
export function campaign(search) {
  const q = new URLSearchParams(search);
  const out = {};
  for (const key of ["utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term"]) {
    const value = q.get(key);
    if (value) out[key] = value;
  }
  const source = q.get("s") || q.get("ref");
  if (source && !out.utm_source) out.utm_source = source;
  const medium = q.get("m");
  if (medium && !out.utm_medium) out.utm_medium = medium;
  return out;
}

const RELEASE_ASSET =
  /^https:\/\/github\.com\/Vette1123\/najm\/releases\/download\/v(\d+\.\d+\.\d+)\/(.+)$/;

function assetKind(file) {
  if (file.endsWith("-setup.exe")) return "setup";
  if (file.endsWith("-portable.zip")) return "portable";
  if (file.startsWith("SHA256SUMS")) return "checksums";
  return "other";
}

/** Which conversion, if any, a clicked link is. Pure, so tests pin every case. */
export function classifyHref(href, origin) {
  let url;
  try {
    url = new URL(href, origin);
  } catch {
    return null;
  }
  const asset = url.href.match(RELEASE_ASSET);
  if (asset) {
    return {
      event: "download_clicked",
      props: { kind: assetKind(asset[2]), version: asset[1] },
    };
  }
  if (url.origin === origin || !/^https?:$/.test(url.protocol)) return null;
  if (url.hostname === "github.com" && url.pathname.startsWith("/Vette1123/najm")) {
    const target = url.pathname.includes("/releases") ? "releases" : "repo";
    return { event: "outbound_clicked", props: { target } };
  }
  if (url.hostname.endsWith("mohamedgado.com")) {
    return { event: "outbound_clicked", props: { target: "portfolio" } };
  }
  return { event: "outbound_clicked", props: { target: url.hostname } };
}

export function payload(event, props, context) {
  if (!(event in EVENT_AREA)) throw new Error(`Unknown event ${event}`);
  return {
    api_key: POSTHOG_KEY,
    event,
    distinct_id: "$posthog_cookieless",
    timestamp: new Date().toISOString(),
    properties: {
      ...context,
      area: EVENT_AREA[event],
      ...props,
      $cookieless_mode: true,
      $process_person_profile: false,
    },
  };
}

function context() {
  const loc = window.location;
  const lang = document.documentElement.lang;
  return {
    $current_url: loc.href,
    $host: loc.host,
    $pathname: loc.pathname,
    route: document.body.dataset.route || loc.pathname,
    $referrer: document.referrer || "$direct",
    $referring_domain: document.referrer ? new URL(document.referrer).host : "$direct",
    ...campaign(loc.search),
    $raw_user_agent: navigator.userAgent,
    $browser_language: navigator.language,
    $timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    $screen_width: screen.width,
    $screen_height: screen.height,
    $viewport_width: window.innerWidth,
    $viewport_height: window.innerHeight,
    $lib: "najm-web-beacon",
    site: "najm",
    page_lang: lang,
  };
}

let enabled = false;

export function track(event, props = {}) {
  if (!enabled) return;
  // text/plain keeps the cross-origin beacon a simple request (no CORS preflight).
  const blob = new Blob([JSON.stringify(payload(event, props, context()))], {
    type: "text/plain",
  });
  if (!navigator.sendBeacon?.(INGEST_URL, blob)) {
    fetch(INGEST_URL, { method: "POST", body: blob, keepalive: true, mode: "no-cors" }).catch(
      () => {},
    );
  }
}

if (typeof document !== "undefined") {
  let store;
  try {
    store = window.localStorage;
  } catch {
    store = null;
  }
  enabled = shouldSend({
    hostname: location.hostname,
    userAgent: navigator.userAgent,
    webdriver: navigator.webdriver === true,
    search: location.search,
    store: store ?? { getItem: () => null, setItem() {}, removeItem() {} },
  });
  if (document.body.dataset.route === "/404") {
    track("not_found", { path: location.pathname });
  } else {
    track("$pageview");
  }
  document.addEventListener(
    "click",
    (e) => {
      const a = e.target instanceof Element ? e.target.closest("a[href]") : null;
      if (!a) return;
      const hit = classifyHref(a.getAttribute("href"), location.origin);
      if (hit) track(hit.event, { ...hit.props, placement: a.dataset.place || "body" });
    },
    { capture: true },
  );
}
