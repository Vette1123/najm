# Najm's website and SEO

## What

- `web/`: a static site on GitHub Pages, seven pages aimed at real searches
  (Ghostty for Windows, Windows Terminal alternative, Arabic text, pasting
  images into Claude Code, download) plus an Arabic home page.
- One source for metadata (`web/pages.mjs`), a build with no dependencies, and
  47 checks in `web/tests/site.test.mjs`.
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
- The site, launch kit, repo description and topics all sold right-to-left Arabic
  that the app does not do. I copied the README line without testing it, and only
  retaking the screenshots showed the text reading backwards. Nothing had been
  posted yet, which was luck: the site had been live and indexed with it.
- The Show HN draft invented a developer in Egypt and a bilingual background.
  Both were removed.
- `robots.txt` was planned and dropped: a project page cannot serve it.

## What worked

- A new folder instead of editing `site/`: Noctty merges stay clean.
- Rendering at desktop and phone widths found what tests could not: a 3:1
  capture is unreadable in a narrow column.

## Rules

- Before auditing a surface, confirm it belongs to this product.
- Test both sides of anything reciprocal.
- A claim about another product needs a source, or it stays out.
- A claim about our own product needs a capture. A README line is not evidence.
- Take the marketing screenshots before writing the marketing.
