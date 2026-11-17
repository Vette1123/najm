// node --test web/tests/analytics.test.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import {
  EVENT_AREA,
  POSTHOG_KEY,
  campaign,
  classifyHref,
  payload,
  shouldSend,
} from "../analytics.js";

const web = join(dirname(fileURLToPath(import.meta.url)), "..");
const origin = "https://najm.mohamedgado.com";
const memory = () => {
  const map = new Map();
  return {
    getItem: (k) => map.get(k) ?? null,
    setItem: (k, v) => map.set(k, v),
    removeItem: (k) => map.delete(k),
  };
};
const browser = {
  hostname: "najm.mohamedgado.com",
  userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/140",
  webdriver: false,
  search: "",
};

test("only real visits on the production host send", () => {
  assert.equal(shouldSend({ ...browser, store: memory() }), true);
  assert.equal(shouldSend({ ...browser, hostname: "localhost", store: memory() }), false);
  assert.equal(shouldSend({ ...browser, hostname: "vette1123.github.io", store: memory() }), false);
  assert.equal(shouldSend({ ...browser, webdriver: true, store: memory() }), false);
  assert.equal(shouldSend({ ...browser, userAgent: "Googlebot/2.1", store: memory() }), false);
  assert.equal(
    shouldSend({ ...browser, userAgent: "Mozilla/5.0 Chrome-Lighthouse", store: memory() }),
    false,
  );
});

test("?va-ignore=1 latches the owner's opt-out and ?va-ignore=0 clears it", () => {
  const store = memory();
  assert.equal(shouldSend({ ...browser, search: "?va-ignore=1", store }), false);
  assert.equal(shouldSend({ ...browser, store }), false);
  assert.equal(shouldSend({ ...browser, search: "?va-ignore=0", store }), true);
});

test("?s= and ?m= become the utm source and medium; explicit utm wins", () => {
  assert.deepEqual(campaign("?s=reddit&m=post"), { utm_source: "reddit", utm_medium: "post" });
  assert.deepEqual(campaign("?utm_source=x&s=reddit"), { utm_source: "x" });
  assert.deepEqual(campaign(""), {});
});

test("release assets are downloads, with their kind and version", () => {
  const base = "https://github.com/Vette1123/najm/releases/download/v1.0.17";
  assert.deepEqual(classifyHref(`${base}/najm-1.0.17-windows-x64-setup.exe`, origin), {
    event: "download_clicked",
    props: { kind: "setup", version: "1.0.17" },
  });
  assert.equal(
    classifyHref(`${base}/najm-1.0.17-windows-x64-portable.zip`, origin).props.kind,
    "portable",
  );
  assert.equal(
    classifyHref(`${base}/SHA256SUMS-windows-x64.txt`, origin).props.kind,
    "checksums",
  );
});

test("outbound links are named; same-site links are not events", () => {
  assert.equal(classifyHref("/download/", origin), null);
  assert.equal(classifyHref("#install", origin), null);
  assert.equal(classifyHref("mailto:a@b.c", origin), null);
  assert.deepEqual(classifyHref("https://github.com/Vette1123/najm", origin).props, {
    target: "repo",
  });
  assert.deepEqual(
    classifyHref("https://github.com/Vette1123/najm/releases/latest", origin).props,
    { target: "releases" },
  );
  assert.deepEqual(
    classifyHref("https://www.mohamedgado.com/projects/najm", origin).props,
    { target: "portfolio" },
  );
});

test("payloads are cookieless, carry an area, and refuse unknown events", () => {
  const body = payload("$pageview", {}, { $host: "najm.mohamedgado.com" });
  assert.equal(body.api_key, POSTHOG_KEY);
  assert.equal(body.distinct_id, "$posthog_cookieless");
  assert.equal(body.properties.area, "traffic");
  assert.equal(body.properties.$cookieless_mode, true);
  assert.equal(body.properties.$process_person_profile, false);
  assert.throws(() => payload("page_view", {}, {}), /Unknown event/);
});

test("every event has a sender", () => {
  const source = readFileSync(join(web, "analytics.js"), "utf8");
  const sent = new Set([
    ...[...source.matchAll(/track\("([$\w]+)"/g)].map((m) => m[1]),
    // classifyHref's results are sent by the click listener.
    ...[...source.matchAll(/event: "([$\w]+)"/g)].map((m) => m[1]),
  ]);
  for (const event of Object.keys(EVENT_AREA)) {
    assert.ok(sent.has(event), `${event} is in EVENT_AREA but nothing sends it`);
  }
});
