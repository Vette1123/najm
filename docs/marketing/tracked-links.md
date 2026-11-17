# Tracked links

Every link a reader sees is the easy link with a source tag on it. Use the one for
the channel you post to:

```text
https://najm.mohamedgado.com/?s=<source>
```

Arabic copy links the Arabic page, so the reader lands in Arabic whatever their
browser's language:

```text
https://najm.mohamedgado.com/ar/?s=<source>
```

The site sends `s` to PostHog as `utm_source` (`web/analytics.js`), next to
pageviews, `download_clicked {kind, version}` and `outbound_clicked {target}`.
Read it on the portfolio's PostHog project, filtered to `site = najm`.

## Rules

1. Never post the old GitHub Pages address; it only redirects here.
2. Never post a bare `najm.mohamedgado.com` link in a post, reply or bio. A bare link
   is counted as direct traffic and the source is lost.
3. The GitHub repo link is fine next to the site link (source code readers want it),
   never instead of it.
4. A new channel gets a row below before its first post.
5. Every post gets a line in `posted.json`: `{date, channel, source, url, note}`.
   Check the ledger before posting so nothing goes out twice.
6. LinkedIn is the owner's alone: never posted by an agent unless the owner names
   LinkedIn and says to post that time.
7. `node --test web/tests/*.test.mjs` fails on a bare or github.io link in any paste block
   under `docs/marketing/`.

## Sources

| Channel | `s` | Link |
|---|---|---|
| Show HN | `hn` | `https://najm.mohamedgado.com/?s=hn` |
| Reddit | `reddit` | `https://najm.mohamedgado.com/?s=reddit` |
| X | `x` | `https://najm.mohamedgado.com/?s=x` |
| Facebook | `facebook` | `https://najm.mohamedgado.com/?s=facebook` |
| Telegram | `telegram` | `https://najm.mohamedgado.com/?s=telegram` |
| Arabic communities (Hsoub I/O, groups) | `ar-community` | `https://najm.mohamedgado.com/ar/?s=ar-community` |
| dev.to / Hashnode / Medium articles | `devto` / `hashnode` / `medium` | `https://najm.mohamedgado.com/?s=devto` |
| Portfolio project page | none | Bare deep links: the referrer already names www.mohamedgado.com, and the links carry SEO weight |
| LinkedIn (owner posts by hand) | `linkedin` | `https://najm.mohamedgado.com/?s=linkedin` |

AlternativeTo forbids tracking tags on the website field: paste the bare site URL
there. It is the one exception, and it is not a post.
