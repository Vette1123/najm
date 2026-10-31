// Checks the built site. Run: NAJM_VERSION=1.0.6 node web/build.mjs
// then: node --test web/tests/site.test.mjs
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { BASE_PATH, INDEXNOW_KEY, SITE_URL, pages } from "../pages.mjs";

const out = join(dirname(fileURLToPath(import.meta.url)), "..", "_site");
const read = (...parts) => readFileSync(join(out, ...parts), "utf8");

const built = pages.map((page) => ({
  page,
  html: read(page.slug, "index.html"),
}));

const attr = (html, regex) => html.match(regex)?.[1];

function jsonLd(html) {
  const raw = attr(html, /application\/ld\+json">(.*?)<\/script>/s);
  assert.ok(raw, "no JSON-LD");
  return JSON.parse(raw)["@graph"];
}

for (const { page, html } of built) {
  const name = `/${page.slug}`;

  test(`${name} title and description fit a search result`, () => {
    assert.ok(page.title.length <= 60, `title is ${page.title.length} chars`);
    assert.ok(
      page.description.length <= 160,
      `description is ${page.description.length} chars`,
    );
    assert.ok(
      page.description.length >= 90,
      `description is ${page.description.length} chars`,
    );
  });

  test(`${name} has one h1 and a self canonical`, () => {
    assert.equal(html.match(/<h1[ >]/g)?.length, 1);
    assert.equal(
      attr(html, /rel="canonical" href="([^"]+)"/),
      `${SITE_URL}/${page.slug}`,
    );
  });

  test(`${name} has valid structured data`, () => {
    const graph = jsonLd(html);
    assert.ok(graph.length > 0);
    if (page.faq) {
      const faq = graph.find((item) => item["@type"] === "FAQPage");
      assert.equal(faq.mainEntity.length, page.faq.length);
      assert.equal(html.match(/<details>/g).length, page.faq.length);
    }
    if (page.software) {
      const app = graph.find((item) => item["@type"] === "SoftwareApplication");
      assert.match(app.softwareVersion, /^\d+\.\d+\.\d+$/);
      assert.equal(app.offers.price, "0");
      assert.equal(app.aggregateRating, undefined);
    }
  });

  test(`${name} images have alt text and a reserved size`, () => {
    for (const tag of html.match(/<img [^>]+>/g) ?? []) {
      if (!tag.includes(`class="mark"`)) assert.match(tag, /alt="[^"]{12,}"/, tag);
      assert.match(tag, /width="\d+" height="\d+"/, tag);
    }
  });

  test(`${name} has no broken internal links`, () => {
    const hrefs = [...html.matchAll(/(?:href|src)="(\/najm[^"#]*)/g)];
    assert.ok(hrefs.length > 3);
    for (const [, href] of hrefs) {
      const path = href.slice(BASE_PATH.length + 1);
      const file = path === "" || path.endsWith("/") ? `${path}index.html` : path;
      assert.ok(existsSync(join(out, file)), `broken link ${href}`);
    }
  });

  test(`${name} has no leftover tokens, dashes or wrong identity`, () => {
    assert.doesNotMatch(html, /\{\{/);
    assert.doesNotMatch(html, /[–—]/);
    assert.doesNotMatch(html, /noctty\.com|AmanThanvi/i);
  });
}

test("hreflang pairs are reciprocal", () => {
  // Google ignores a pair unless each page names the other and itself.
  const pair = (html) => ({
    ar: attr(html, /hreflang="ar" href="([^"]+)"/),
    en: attr(html, /hreflang="en" href="([^"]+)"/),
  });
  const paired = built.filter(({ page }) => page.alternate !== undefined);
  assert.ok(paired.length >= 2);
  for (const { page, html } of paired) {
    const mine = pair(html);
    const self = `${SITE_URL}/${page.slug}`;
    assert.equal(mine[page.lang], self, `${page.slug} does not name itself`);
    assert.ok(attr(html, /hreflang="x-default" href="([^"]+)"/), page.slug);
    const otherUrl = mine[page.lang === "ar" ? "en" : "ar"];
    const other = built.find((b) => `${SITE_URL}/${b.page.slug}` === otherUrl);
    assert.deepEqual(pair(other.html), mine, `${page.slug} is not reciprocal`);
  }
});

test("the sitemap lists exactly the pages, with dates", () => {
  const sitemap = read("sitemap.xml");
  const locs = [...sitemap.matchAll(/<loc>([^<]+)</g)].map((m) => m[1]).sort();
  const expected = pages.map((page) => `${SITE_URL}/${page.slug}`).sort();
  assert.deepEqual(locs, expected);
  assert.equal(sitemap.match(/<lastmod>\d{4}-\d{2}-\d{2}</g).length, pages.length);
});

test("the 404 page stays out of the index", () => {
  assert.match(read("404.html"), /name="robots" content="noindex"/);
  assert.doesNotMatch(read("404.html"), /rel="canonical"/);
});

test("Pages and IndexNow files exist", () => {
  assert.equal(read(`${INDEXNOW_KEY}.txt`), INDEXNOW_KEY);
  assert.ok(existsSync(join(out, ".nojekyll")));
  assert.match(read("llms.txt"), /not affiliated/);
});

// A capture of v1.0.6 showed Arabic in cell order, reading backwards: the shaper
// forces LTR and nothing reorders a line. These claims stay out until that changes.
test("nothing claims right-to-left Arabic the renderer does not do", () => {
  const banned = [
    /reads? right to left|lays (it|out)|right-to-left Arabic/i,
    /joined letters|letters join|full Arabic support|Arabic that/i,
    /بأحرف متصلة|ويصل الأحرف|تدعم العربية|تتحدث العربية/,
  ];
  const readme = readFileSync(join(out, "..", "..", "README.md"), "utf8");
  const sources = built.map(({ page, html }) => [page.slug || "home", html]);
  sources.push(["README.md", readme], ["llms.txt", read("llms.txt")]);
  for (const [name, text] of sources) {
    for (const claim of banned) {
      assert.doesNotMatch(text, claim, `${name} repeats a false Arabic claim`);
    }
  }
});
