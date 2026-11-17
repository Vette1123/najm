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

  test(`${name} has Twitter cards, robots and a WebPage entry`, () => {
    for (const key of ["title", "description", "image", "image:alt"]) {
      assert.ok(attr(html, new RegExp(`twitter:${key}" content="([^"]+)"`)), key);
    }
    assert.equal(
      attr(html, /twitter:title" content="([^"]+)"/),
      attr(html, /og:title" content="([^"]+)"/),
    );
    assert.match(html, /name="robots" content="index, follow, max-image-preview:large"/);
    const web = jsonLd(html).find((item) => item["@type"] === "WebPage");
    assert.equal(web.inLanguage, page.lang);
    assert.match(web.dateModified, /^\d{4}-\d{2}-\d{2}$/);
    assert.ok(web.dateModified >= page.updated, "dateModified is older than pages.mjs says");
    const lastmod = read("sitemap.xml").match(
      new RegExp(`<loc>${SITE_URL}/${page.slug}</loc><lastmod>([^<]+)<`),
    )?.[1];
    assert.equal(lastmod, web.dateModified, "sitemap and JSON-LD disagree on the date");
  });

  test(`${name} has no broken internal links`, () => {
    const hrefs = [...html.matchAll(new RegExp(`(?:href|src)="(${BASE_PATH}/(?!/)[^"#]*)`, "g"))];
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

test("robots.txt points crawlers at the sitemap on the site's own host", () => {
  assert.match(read("robots.txt"), new RegExp(`^Sitemap: ${SITE_URL}/sitemap\\.xml$`, "m"));
  assert.ok(new URL(SITE_URL).pathname === "/", "robots.txt only counts at a host root");
});

test("sitemap pairs carry x-default and the image alt follows the page language", () => {
  assert.ok(read("sitemap.xml").match(/hreflang="x-default"/g).length >= 2);
  const ar = built.find(({ page }) => page.lang === "ar").html;
  assert.match(attr(ar, /og:image:alt" content="([^"]+)"/), /[\u0600-\u06FF]/);
});

test("the 404 page stays out of the index", () => {
  assert.match(read("404.html"), /name="robots" content="noindex"/);
  assert.doesNotMatch(read("404.html"), /rel="canonical"/);
});

// The portfolio declares the same Person @id, so search engines merge the two
// into one author; the app and the site each keep one @id across pages.
test("every page names one owner, one app and one site by @id", () => {
  for (const { page, html } of built) {
    const graph = jsonLd(html);
    const person = graph.find((item) => item["@type"] === "Person");
    assert.equal(person?.["@id"], "https://www.mohamedgado.com/#person", page.slug);
    assert.ok(person.sameAs.includes("https://github.com/Vette1123"), page.slug);
    assert.equal(
      graph.find((item) => item["@type"] === "WebPage").isPartOf["@id"],
      `${SITE_URL}/#website`,
      page.slug,
    );
    const app = graph.find((item) => item["@type"] === "SoftwareApplication");
    if (!page.software) continue;
    assert.equal(app["@id"], `${SITE_URL}/#app`, page.slug);
    assert.equal(app.author["@id"], person["@id"], page.slug);
    assert.ok(app.sameAs.includes("https://www.mohamedgado.com/projects/najm"), page.slug);
    assert.match(app.releaseNotes, /\/releases\/tag\/v\d+\.\d+\.\d+$/);
  }
});

test("the footer links the portfolio and discloses the site's analytics", () => {
  for (const { page, html } of built) {
    assert.match(html, /href="https:\/\/www\.mohamedgado\.com\/projects\/najm"/, page.slug);
    assert.match(html, /without cookies|دون ملفات تعريف الارتباط/, page.slug);
    assert.match(html, /<script type="module" src="\/analytics\.js">/, page.slug);
  }
  assert.ok(existsSync(join(out, "analytics.js")));
});

test("favicons, the touch icon and the manifest are linked and built", () => {
  const home = built.find(({ page }) => page.slug === "").html;
  for (const href of ["/favicon.ico", "/apple-touch-icon.png", "/manifest.webmanifest"]) {
    assert.ok(home.includes(`href="${href}"`), `${href} is not linked`);
    assert.ok(existsSync(join(out, href)), `${href} is not built`);
  }
  const ico = readFileSync(join(out, "favicon.ico"));
  assert.deepEqual([...ico.subarray(0, 4)], [0, 0, 1, 0], "favicon.ico has no ICO header");
  const manifest = JSON.parse(read("manifest.webmanifest"));
  for (const icon of manifest.icons) {
    assert.ok(existsSync(join(out, icon.src)), `manifest icon ${icon.src} is missing`);
  }
});

// Chat apps fetch the card on every share; it was 316 KB, 42 KB as a palette PNG.
test("the social card stays under 150 KB", () => {
  const size = readFileSync(join(out, "assets", "najm-social.png")).length;
  assert.ok(size < 150_000, `najm-social.png is ${size} bytes`);
});

test("Pages and IndexNow files exist", () => {
  assert.equal(read(`${INDEXNOW_KEY}.txt`), INDEXNOW_KEY);
  assert.ok(existsSync(join(out, ".nojekyll")));
  assert.match(read("llms.txt"), /not affiliated/);
});

// Right to left stops at the alternate screen and at IME composition, so "full"
// is false, and the page that covers Arabic has to name the limit.
test("nothing claims more Arabic support than the renderer has", () => {
  const banned = [/full Arabic support/i, /تدعم العربية بالكامل/];
  const arabic = built.find(({ page }) => page.slug === "arabic-terminal-windows/");
  assert.match(arabic.html, /stay left to right/);
  const readme = readFileSync(join(out, "..", "..", "README.md"), "utf8");
  const sources = built.map(({ page, html }) => [page.slug || "home", html]);
  sources.push(["README.md", readme], ["llms.txt", read("llms.txt")]);
  for (const [name, text] of sources) {
    for (const claim of banned) {
      assert.doesNotMatch(text, claim, `${name} repeats a false Arabic claim`);
    }
  }
});
