# 2026-11-17: the site moves to najm.mohamedgado.com

## What

`web/` now builds for `https://najm.mohamedgado.com` (`SITE_URL`, `BASE_PATH = ""` in
`web/pages.mjs`) and writes `/robots.txt` naming the sitemap. DNS is a Namecheap CNAME `najm` →
`vette1123.github.io.`; the domain is set in the repo's Pages settings, HTTPS enforced. GitHub
301s every `vette1123.github.io/najm/*` URL here. README and launch-kit links point at the domain.
Details and traps: the 2026-11-17 entry in `docs/agents/log/docs-and-site.md`.

## Mistakes

- The Pages domain was first set while the record was still unpublished; GitHub never started a
  certificate until the domain was cleared and set again.
- The link test matched `/najm` literally, so an empty base path would have found zero links; it
  now builds its pattern from `BASE_PATH`.

## What worked

- The two-line `SITE_URL`/`BASE_PATH` switch: every canonical, hreflang and sitemap entry followed.

## Rules

- Push a base-path change only after DNS answers and the Pages domain is set, or the github.io
  copy serves root paths that 404.
