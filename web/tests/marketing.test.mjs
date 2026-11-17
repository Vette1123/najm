// node --test web/tests/marketing.test.mjs
// The post guard: every paste-ready link in docs/marketing/ carries its source tag,
// so PostHog can tell which post brought a visit. A bare link reads as direct traffic.
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const docs = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "docs", "marketing");
const files = readdirSync(docs).filter((f) => f.endsWith(".md"));

/** The site links in a doc's ```text paste blocks that lack a ?s= source. */
export function untaggedLinks(markdown) {
  const out = [];
  for (const [, block] of markdown.matchAll(/```text\r?\n([\s\S]*?)```/g)) {
    for (const [url] of block.matchAll(/https:\/\/najm\.mohamedgado\.com[^\s)"']*/g)) {
      // `<source>` is the template in tracked-links.md, filled in per channel.
      if (!/[?&]s=([a-z0-9-]+|<source>)$/.test(url)) out.push(url);
    }
  }
  return out;
}

test("the guard catches a bare link and passes a tagged one", () => {
  assert.deepEqual(untaggedLinks("```text\nTry https://najm.mohamedgado.com/ar/\n```"), [
    "https://najm.mohamedgado.com/ar/",
  ]);
  assert.deepEqual(untaggedLinks("```text\nhttps://najm.mohamedgado.com/?s=hn\n```"), []);
  assert.deepEqual(untaggedLinks("```text\nhttps://najm.mohamedgado.com/ar/?s=<source>\n```"), []);
  assert.deepEqual(untaggedLinks("```text\nhttps://najm.mohamedgado.com/?s=\n```"), [
    "https://najm.mohamedgado.com/?s=",
  ]);
  // Prose outside a paste block may show the pattern with a placeholder.
  assert.deepEqual(untaggedLinks("Use https://najm.mohamedgado.com/ in prose."), []);
});

test("every paste-ready site link carries its source", () => {
  for (const file of files) {
    const bad = untaggedLinks(readFileSync(join(docs, file), "utf8"));
    assert.deepEqual(bad, [], `${file} has untagged links`);
  }
});

test("no marketing doc sends readers to the github.io mirror", () => {
  for (const file of files) {
    assert.doesNotMatch(readFileSync(join(docs, file), "utf8"), /vette1123\.github\.io/i, file);
  }
});

test("the post ledger is a list of {date, channel, source, url}", () => {
  const ledger = JSON.parse(readFileSync(join(docs, "posted.json"), "utf8"));
  assert.ok(Array.isArray(ledger));
  for (const entry of ledger) {
    assert.match(entry.date, /^\d{4}-\d{2}-\d{2}$/);
    for (const key of ["channel", "source", "url"]) assert.ok(entry[key], `${key} missing`);
    assert.match(entry.url, /[?&]s=/, `${entry.url} has no source`);
  }
});
