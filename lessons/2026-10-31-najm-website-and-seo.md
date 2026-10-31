# Najm's website and SEO

## What

- `web/`: a static site on GitHub Pages, seven pages aimed at real searches
  (Ghostty for Windows, Windows Terminal alternative, Arabic terminal, pasting
  images into Claude Code, download) plus an Arabic home page.
- One source for metadata (`web/pages.mjs`), a build with no dependencies, and
  46 checks in `web/tests/site.test.mjs`.
- JSON-LD, a sitemap, `llms.txt`, IndexNow on deploy, and a version stamped from
  the latest release.
- README, repo description and topics now lead to the site;
  `docs/marketing/launch-kit.md` holds the posts.

## Mistakes

- `site/` looked like the thing to optimize. It is Noctty's noctty.com and has
  no Najm in it. Najm had no site at all, and the repo homepage pointed at the
  releases page.
- The first hreflang test passed a broken pair: it checked that each page named
  itself, not that the pages named each other. Found by reading the output.
- A hand-drawn logo approximation went into the first build; the real mark was
  in `assets/brand/` all along.
- A comparison row said to check Arabic in Windows Terminal "against your own
  text". That hid a fact nobody had verified, so the row was removed.
- `robots.txt` was planned and dropped: a project page cannot serve it.

## What worked

- A new folder instead of editing `site/`: Noctty merges stay clean.
- Rendering at desktop and phone widths found what tests could not: a 3:1
  capture is unreadable in a narrow column.

## Rules

- Before auditing a surface, confirm it belongs to this product.
- Test both sides of anything reciprocal.
- A claim about another product needs a source, or it stays out.
