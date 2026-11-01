// Builds web/ into web/_site with Node's standard library only.
//   NAJM_VERSION=1.0.6 node web/build.mjs
// GOOGLE_SITE_VERIFICATION and BING_SITE_VERIFICATION, when set, add the
// ownership meta tags that Search Console and Bing Webmaster Tools ask for.
import { cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  BASE_PATH,
  INDEXNOW_KEY,
  REPO_URL,
  SITE_URL,
  pages,
  ui,
} from "./pages.mjs";

const root = dirname(fileURLToPath(import.meta.url));
const out = join(root, "_site");

const version = process.env.NAJM_VERSION;
if (!/^\d+\.\d+\.\d+$/.test(version ?? "")) {
  throw new Error(`NAJM_VERSION must be x.y.z, got "${version}"`);
}
const releaseUrl = `${REPO_URL}/releases/download/v${version}`;
const setupFile = `najm-${version}-windows-x64-setup.exe`;
const tokens = {
  base: BASE_PATH,
  version,
  setupFile,
  setupUrl: `${releaseUrl}/${setupFile}`,
  portableFile: `najm-${version}-windows-x64-portable.zip`,
  portableUrl: `${releaseUrl}/najm-${version}-windows-x64-portable.zip`,
  sumsUrl: `${releaseUrl}/SHA256SUMS-windows-x64.txt`,
  repo: REPO_URL,
};

const esc = (text) =>
  String(text)
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");

const stamp = (html) =>
  html.replace(/\{\{(\w+)\}\}/g, (match, name) => {
    if (!(name in tokens)) throw new Error(`Unknown token ${match}`);
    return tokens[name];
  });

const pageUrl = (slug) => `${SITE_URL}/${slug}`;

const mark = `<img class="mark" src="${BASE_PATH}/assets/najm-mark.svg" width="28" height="28" alt="" />`;

function softwareSchema(page) {
  return {
    "@type": "SoftwareApplication",
    name: "Najm",
    alternateName: "نجم",
    url: `${SITE_URL}/`,
    applicationCategory: "DeveloperApplication",
    applicationSubCategory: "Terminal emulator",
    operatingSystem: "Windows 10 version 1809 or later, Windows 11",
    softwareVersion: version,
    downloadUrl: tokens.setupUrl,
    installUrl: pageUrl("download/"),
    license: "https://opensource.org/license/mit",
    isAccessibleForFree: true,
    image: `${SITE_URL}/assets/najm-social.png`,
    screenshot: `${SITE_URL}/assets/shot-splits-dark.png`,
    description: page.description,
    inLanguage: ["en", "ar"],
    offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    author: { "@type": "Person", name: "Mohamed Gado" },
    sameAs: [REPO_URL],
  };
}

function schema(page) {
  const graph = [];
  if (page.slug === "") {
    graph.push({
      "@type": "WebSite",
      name: "Najm",
      alternateName: ["نجم", "Najm terminal"],
      url: `${SITE_URL}/`,
    });
  }
  graph.push({
    "@type": "WebPage",
    "@id": `${pageUrl(page.slug)}#webpage`,
    url: pageUrl(page.slug),
    name: page.title,
    description: page.description,
    inLanguage: page.lang,
    dateModified: page.updated,
    isPartOf: { "@type": "WebSite", name: "Najm", url: `${SITE_URL}/` },
  });
  if (page.software) graph.push(softwareSchema(page));
  if (page.slug !== "" && page.slug !== "ar/") {
    graph.push({
      "@type": "BreadcrumbList",
      itemListElement: [
        { name: ui[page.lang].home, item: `${SITE_URL}/` },
        { name: page.nav, item: pageUrl(page.slug) },
      ].map((crumb, i) => ({
        "@type": "ListItem",
        position: i + 1,
        ...crumb,
      })),
    });
  }
  if (page.faq) {
    graph.push({
      "@type": "FAQPage",
      mainEntity: page.faq.map(([name, text]) => ({
        "@type": "Question",
        name,
        acceptedAnswer: { "@type": "Answer", text },
      })),
    });
  }
  // JSON.stringify leaves "<" alone, and a "</script>" in copy would end the tag.
  const json = JSON.stringify({
    "@context": "https://schema.org",
    "@graph": graph,
  }).replaceAll("<", "\\u003c");
  return `<script type="application/ld+json">${json}</script>`;
}

function hreflang(page) {
  if (page.alternate === undefined) return "";
  const en = page.lang === "en" ? page.slug : page.alternate;
  const ar = page.lang === "ar" ? page.slug : "ar/";
  return [
    `<link rel="alternate" hreflang="en" href="${pageUrl(en)}" />`,
    `<link rel="alternate" hreflang="ar" href="${pageUrl(ar)}" />`,
    `<link rel="alternate" hreflang="x-default" href="${pageUrl(en)}" />`,
  ].join("\n  ");
}

function verificationTags() {
  const tags = [];
  const google = process.env.GOOGLE_SITE_VERIFICATION;
  const bing = process.env.BING_SITE_VERIFICATION;
  if (google) {
    tags.push(
      `<meta name="google-site-verification" content="${esc(google)}" />`,
    );
  }
  if (bing) tags.push(`<meta name="msvalidate.01" content="${esc(bing)}" />`);
  return tags.join("\n  ");
}

function faqBlock(page) {
  if (!page.faq) return "";
  const t = ui[page.lang];
  const items = page.faq
    .map(
      ([question, answer]) =>
        `<details><summary>${esc(question)}</summary><p>${esc(answer)}</p></details>`,
    )
    .join("\n      ");
  return `<section class="faq" aria-labelledby="faq-title">
    <div class="frame">
      <h2 id="faq-title">${t.faqTitle}</h2>
      ${items}
    </div>
  </section>`;
}

function relatedBlock(page) {
  const links = pages
    .filter(
      (other) =>
        other.lang === page.lang &&
        other.slug !== page.slug &&
        other.slug !== "" &&
        other.slug !== "ar/",
    )
    .map(
      (other) => `<li><a href="${BASE_PATH}/${other.slug}">${other.nav}</a></li>`,
    );
  if (links.length === 0) return "";
  return `<nav class="related" aria-label="${ui[page.lang].relatedTitle}"><h2>${ui[page.lang].relatedTitle}</h2><ul>${links.join("")}</ul></nav>`;
}

function shell(page, body, { indexable = true } = {}) {
  const t = ui[page.lang];
  const canonical = pageUrl(page.slug);
  const homeHref = `${BASE_PATH}/${page.lang === "ar" ? "ar/" : ""}`;
  const menu = t.menu
    .map(([slug, label]) => {
      const lang = label === "العربية" ? ' lang="ar"' : "";
      return `<a href="${BASE_PATH}/${slug}"${lang}>${label}</a>`;
    })
    .join("");
  const seo = indexable
    ? `<meta name="robots" content="index, follow, max-image-preview:large" />
  <link rel="canonical" href="${canonical}" />
  ${hreflang(page)}
  <meta property="og:url" content="${canonical}" />
  ${schema(page)}`
    : `<meta name="robots" content="noindex" />`;
  const preload = page.image
    ? `<link rel="preload" as="image" href="${BASE_PATH}/${page.image}" fetchpriority="high" />`
    : "";
  return `<!DOCTYPE html>
<html lang="${page.lang}" dir="${t.dir}">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${esc(page.title)}</title>
  <meta name="description" content="${esc(page.description)}" />
  <meta name="theme-color" content="#0B1026" />
  <meta name="color-scheme" content="dark" />
  ${verificationTags()}
  ${seo}
  <meta property="og:type" content="website" />
  <meta property="og:site_name" content="Najm" />
  <meta property="og:locale" content="${t.locale}" />
  <meta property="og:title" content="${esc(page.title)}" />
  <meta property="og:description" content="${esc(page.description)}" />
  <meta property="og:image" content="${SITE_URL}/assets/najm-social.png" />
  <meta property="og:image:width" content="1280" />
  <meta property="og:image:height" content="640" />
  <meta property="og:image:alt" content="${esc(t.socialAlt)}" />
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content="${esc(page.title)}" />
  <meta name="twitter:description" content="${esc(page.description)}" />
  <meta name="twitter:image" content="${SITE_URL}/assets/najm-social.png" />
  <meta name="twitter:image:alt" content="${esc(t.socialAlt)}" />
  <link rel="icon" href="${BASE_PATH}/assets/najm-mark.svg" type="image/svg+xml" />
  <link rel="preload" as="font" type="font/woff2" href="${BASE_PATH}/assets/fonts/geist.woff2" crossorigin />
  ${preload}
  <link rel="stylesheet" href="${BASE_PATH}/styles.css" />
  <script src="${BASE_PATH}/copy.js" defer></script>
</head>
<body>
  <a class="skip" href="#main">${t.skip}</a>
  <header class="site-header">
    <div class="frame site-header__inner">
      <a class="brand" href="${homeHref}" aria-label="${t.logoAlt}">${mark}<span>${page.lang === "ar" ? "نجم" : "Najm"}</span></a>
      <nav class="site-nav" aria-label="Main">${menu}</nav>
      <a class="button button--small" href="${BASE_PATH}/${page.lang === "ar" ? "ar/#install" : "download/"}">${t.download}</a>
    </div>
  </header>
  <main id="main">
${body}
  ${faqBlock(page)}
  <section class="close">
    <div class="frame">
      <h2>${t.closeTitle}</h2>
      <p>${t.closeText}</p>
      <div class="actions">
        <a class="button" href="${tokens.setupUrl}">${t.download}</a>
        <a class="button button--ghost" href="${REPO_URL}">${t.github}</a>
      </div>
    </div>
  </section>
  </main>
  <footer class="site-footer">
    <div class="frame">
      ${relatedBlock(page)}
      <p>${t.footer}</p>
    </div>
  </footer>
</body>
</html>
`;
}

function sitemap() {
  const urls = pages
    .map((page) => {
      const links = [];
      if (page.alternate !== undefined) {
        const en = page.lang === "en" ? page.slug : page.alternate;
        const ar = page.lang === "ar" ? page.slug : "ar/";
        links.push(
          `<xhtml:link rel="alternate" hreflang="en" href="${pageUrl(en)}"/>`,
          `<xhtml:link rel="alternate" hreflang="ar" href="${pageUrl(ar)}"/>`,
          `<xhtml:link rel="alternate" hreflang="x-default" href="${pageUrl(en)}"/>`,
        );
      }
      return `  <url><loc>${pageUrl(page.slug)}</loc><lastmod>${page.updated}</lastmod>${links.join("")}</url>`;
    })
    .join("\n");
  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
${urls}
</urlset>
`;
}

// A plain-text map for AI assistants: https://llmstxt.org
function llms() {
  const lines = pages
    .filter((page) => page.lang === "en")
    .map((page) => `- [${page.title}](${pageUrl(page.slug)}): ${page.description}`);
  return `# Najm

> Najm (Arabic for star, نجم) is a free, open-source, GPU-accelerated terminal emulator for Windows 10 and 11, built on Ghostty's terminal core through Noctty. It is not affiliated with either project.

Latest version: ${version}. Download: ${tokens.setupUrl}

${lines.join("\n")}
- [Arabic home page](${pageUrl("ar/")})
- [Source code](${REPO_URL})
`;
}

await rm(out, { recursive: true, force: true });
await mkdir(out, { recursive: true });
await cp(join(root, "assets"), join(out, "assets"), { recursive: true });
await cp(join(root, "styles.css"), join(out, "styles.css"));
await cp(join(root, "copy.js"), join(out, "copy.js"));

for (const page of pages) {
  const body = await readFile(join(root, "pages", `${page.source}.html`), "utf8");
  const dir = join(out, page.slug);
  await mkdir(dir, { recursive: true });
  await writeFile(join(dir, "index.html"), stamp(shell(page, body)));
}

const missing = {
  lang: "en",
  slug: "404.html",
  title: "Page not found | Najm",
  description: "This page does not exist.",
};
const missingBody = await readFile(join(root, "pages", "404.html"), "utf8");
await writeFile(
  join(out, "404.html"),
  stamp(shell(missing, missingBody, { indexable: false })),
);

await writeFile(join(out, "sitemap.xml"), sitemap());
await writeFile(join(out, "llms.txt"), llms());
await writeFile(join(out, `${INDEXNOW_KEY}.txt`), INDEXNOW_KEY);
await writeFile(join(out, ".nojekyll"), "");

console.log(`Built ${pages.length} pages for Najm ${version} into ${out}`);
