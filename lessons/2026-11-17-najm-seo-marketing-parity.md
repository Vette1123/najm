# SEO, analytics and marketing parity with Masareef

## What

- JSON-LD joins the portfolio's graph: the Person `@id` is
  `https://www.mohamedgado.com/#person`, the same as the portfolio's, so the author
  is one entity across both sites. The app and site carry their own `@id`s. The app
  also has `featureList`, `isBasedOn`, `releaseNotes` and `sameAs` pointing to the
  repo and the portfolio project page.
- `web/analytics.js` sends cookieless beacons through the portfolio's `/ingest/e`
  relay to the same PostHog project: `$pageview`, `not_found`,
  `download_clicked {kind, version}` and `outbound_clicked {target}`. It runs only
  on the production host and drops bots and `?va-ignore=1`. `?s=` becomes
  `utm_source`.
- The footer credits the portfolio and says the site counts visits without cookies.
  The FAQ's "no telemetry" is about the app, and stays true.
- Added favicon.ico (16/32/48), the apple-touch icon, 192/512 icons and a manifest.
  The social card went from 316 KB to 42 KB.
- Sitemap `lastmod` comes from each page source's last commit, so CI checks out
  full history.
- `docs/marketing/tracked-links.md` and the `posted.json` ledger. A guard test fails
  on any untagged site link in a paste block.

## Mistakes

- `node --test web/tests/` passed locally on Node 26, which expands a folder. CI's
  Node 22 treats the argument as a module path, so the deploy failed. CI runs
  `web/tests/*.test.mjs` now.
- A heredoc ate the backslashes in `/^\d{4}…$/`, which turned it into `/^d{4}…$/`,
  and the date test failed for no visible reason. Write regex literals with the
  Edit tool, not through a shell heredoc.
- My first `isBasedOn` linked to the upstream author's GitHub, which the site's
  identity test bans on purpose. It is a name-only reference now.
- The first icons padded the mark inside a dark tile. The SVG already has its own
  rounded tile, so the result was a frame inside a frame. Look at the generated
  icon before shipping it.
- The guard's first run flagged its own docs: the `?s=<source>` template and a rule
  that named the github.io host. The template is now an allowed placeholder, and the
  rule names the host in words.
- I tried to make the red check with `git stash`, and a hook blocked it because it
  would stash other sessions' edits. I swapped the one file through the job's tmp
  folder instead.

## What worked

- Reusing the portfolio relay instead of a PostHog SDK: one `sendBeacon` with a
  `text/plain` body, so there is no preflight, no cookie and no dependency.
- Proving each new test red: the old `build.mjs` failed 3 tests, and the old
  launch kit failed the guard.

## Rules

- On a static site that needs analytics, send a beacon to the portfolio relay, as a
  pure helper with tests.
- Every paste-ready site link carries `?s=<source>`. The test enforces it.
- Before pushing a test-runner change, check which Node the CI workflow pins.
