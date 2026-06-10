# F95Zone API Documentation (`/sam/latest_alpha/`)

Reverse-engineered documentation for the endpoint this app consumes. Verified live on
2026-06-09 with unauthenticated requests; cross-checked against the
[F95-Manager](https://github.com/farvend/F95-Manager) metadata dump and
[F95Checker](https://github.com/WillyJL/F95Checker)'s indexer.

> **2026-06-09: this file replaces the old guesswork mappings.** Several of the original
> prefix IDs were misassigned (see [Corrections](#corrections-vs-the-old-mappings)).
> The canonical prefix/tag vocabulary lives in [`assets/f95_metadata.json`](../assets/f95_metadata.json).

## Endpoint

```
GET https://f95zone.to/sam/latest_alpha/latest_data.php
```

- **No authentication required** for `cmd=list`, `cmd=tags`, `cmd=rss`. (The HTML page at
  `/sam/latest_alpha/` *does* require login, but the data endpoint does not.)
- Web browsers are blocked by CORS; mobile/desktop clients are fine.
- Any `User-Agent` works (the app sends `F95Portal/<version> (<build>)`).

### Response envelope

```json
{ "status": "ok", "msg": { "data": [ ...threads ], "pagination": { "page": 1, "total": 290 }, "count": 26057 } }
```

Errors come back as `{ "status": "error", "msg": "<reason>" }` — `msg` is `404` (number)
for an unknown `cmd`, `"Missing category"` for a bad `cat`, or a human-readable string
(e.g. `"You must be logged in to set options"`).

## Commands

| `cmd` | Auth | Returns |
|-------|------|---------|
| `list` | no | Thread list (the main feed/search). See parameters below. |
| `tags` | no | Popular tags for the category: `{"data":[{"tag_id":2214,"count":6268},…]}` — IDs and usage counts only, no names. |
| `rss` | no | RSS 2.0 XML of the latest updates. |
| `options` | **yes** | Persists feed display options for the logged-in user. |

There is **no metadata command** — prefix/tag names are only embedded in the logged-in
HTML page as the `latestUpdates.prefixes` / `latestUpdates.tags` JS globals. A captured
dump is committed as [`assets/f95_metadata.json`](../assets/f95_metadata.json) (shape:
`{"prefixes": {<category>: [<group>…]}, "tags": {<id>: <name>}}`).

## `cmd=list` parameters

| Param | Values | Notes |
|-------|--------|-------|
| `cat` | `games`, `comics`, `animations`, `assets`, `mods` | Required. `mods` is accepted but always returns `count: 0` — the feed doesn't index mods. |
| `page` | 1-based int | `msg.pagination.total` is the total page count. |
| `rows` | int | Page size (site uses 90). |
| `sort` | `date`, `likes`, `views`, `title`, `rating` | Unknown values silently fall back to `date`. |
| `search` | string | Title search (e.g. `search=goblin` → 81 games). |
| `creator` | string | Developer/creator name search. Independent of `search`. |
| `prefixes[N]` | prefix ID | Threads must have **all** listed prefixes. |
| `noprefixes[N]` | prefix ID | Excludes threads with any listed prefix. |
| `tags[N]` | tag ID | Threads must have **all** listed tags. |
| `notags[N]` | tag ID | Excludes threads with any listed tag. |
| `_` | timestamp | Cache buster, optional. |

Unknown parameter names are silently ignored (so a typo'd filter returns the unfiltered
list — verify with `msg.count` when testing).

## Prefix IDs

Prefixes are grouped per category. Group ID **4 = Status** everywhere; the rest are
engine/format groups. Full data in [`assets/f95_metadata.json`](../assets/f95_metadata.json); summary:

### Games — Engine group (group 1)

| ID | Engine | | ID | Engine |
|----|--------|-|----|--------|
| 1 | QSP | | 12 | ADRIFT |
| 2 | RPGM | | 14 | Others |
| 3 | Unity | | 17 | Tads |
| 4 | HTML | | 30 | Wolf RPG |
| 5 | RAGS | | 31 | Unreal Engine |
| 6 | Java | | 47 | WebGL |
| 7 | Ren'Py | | 116 | Godot¹ |
| 8 | Flash | | | |

¹ Not in the metadata dump (added later); identified live — `prefixes[0]=116` returns
known Godot games (Strive for Power, Queen's Brothel, Beat Banger, Hardcoded, Ero Dungeons).

### Games — Other group (group 3)

| ID | Meaning |
|----|---------|
| 13 | VN |
| 19 | Collection |
| 23 | SiteRip |

### Status group (group 4, all categories)

| ID | Status |
|----|--------|
| 18 | Completed |
| 20 | Onhold |
| 22 | Abandoned |

### Comics (group 3)

16 = Comics, 43 = Manga, 44 = Pinup, 49 = CG, 19 = Collection, 23 = SiteRip.

### Animations (group 6 + group 3)

37 = Flash, 38 = GIF, 39 = Video, 59 = App, 19 = Collection.

### Assets (group 5 + group 3)

33 = Daz, 35 = VAM, 36 = Illusion, 40 = AutoDesk, 41 = Poser, 42 = Blender, 45 = Tutorial,
71 = Other, 110 = Unreal, 114 = Unity, 115 = RPGM, 19 = Collection.

## Tag IDs

Tags are **content/genre descriptors, not engines**. The full ~150-entry map is in
[`assets/f95_metadata.json`](../assets/f95_metadata.json). Ones currently referenced in code/data:

| ID | Tag | | ID | Tag |
|----|-----|-|----|-----|
| 107 | 3dcg | | 191 | futa/trans |
| 130 | big tits | | 324 | no sexual content |
| 173 | male protagonist | | 522 | text based |
| 174 | male domination | | | |

## Corrections vs the old mappings

The original `ThreadUtils` mappings were derived from two sample threads and got the
ID→name pairing wrong (the *names* were right for those threads, but assigned to the
wrong IDs):

| ID | Old (wrong) | Actual | Verified by |
|----|-------------|--------|-------------|
| 3 | VN | **Unity** | metadata dump |
| 7 | HTML | **Ren'Py** | Summertime Saga = `[7]`, Eternum = `[13,7]`, `prefixes[0]=7` → 9 821 self-consistent results |
| 13 | WebGL | **VN** | Eternum = `[13,7]` (a Ren'Py VN) |
| 47 | Unity | **WebGL** | metadata dump |

Also wrong in spirit:

- **The tag→engine fallback is bogus.** Tags 107/130/191 are `3dcg`, `big tits`, and
  `futa/trans` — genres, not engines. Engine info comes exclusively from prefixes.
- **The hardcoded default query filters were personal browsing preferences**:
  `tags=[191]` means *only* futa/trans content; `noprefixes=[2,7,13]` excludes RPGM,
  Ren'Py, and VN threads; `notags=[173,174,324,522]` excludes male protagonist,
  male domination, no-sexual-content, and text-based threads.
- Status IDs (18/20/22) were already correct.

## Sample data

- [`samples/list_games_p1.json`](samples/list_games_p1.json) — live `cmd=list&cat=games`
  response (2026-06-09).
- [`sample API output.txt`](sample%20API%20output.txt) — original capture from project start.

### Thread object

```json
{
  "thread_id": 297700,
  "title": "Game Title",
  "creator": "Developer Name",
  "version": "v0.2",            // may be "Final", "Demo", etc.
  "views": 44337,
  "likes": 61,
  "prefixes": [13, 7],          // engine/format + status IDs (see tables)
  "tags": [30, 75, 107],        // content/genre tag IDs
  "rating": 2.67,               // 0 means unrated, render as "-"
  "cover": "https://preview.f95zone.to/...png",
  "screens": ["https://preview.f95zone.to/...png"],
  "date": "2 hrs",              // human-readable age of last update
  "watched": false,             // always false when unauthenticated
  "ignored": false,             // always false when unauthenticated
  "new": false,
  "ts": 1781044080              // unix timestamp of last update
}
```

## Refreshing the metadata

`assets/f95_metadata.json` changes only when F95Zone adds prefixes/tags (e.g. Godot). To
refresh: log in to <https://f95zone.to/sam/latest_alpha/> in a browser and run
`copy(JSON.stringify({prefixes: latestUpdates.prefixes, tags: latestUpdates.tags}))`
in the dev-tools console, then paste over the file. Unknown IDs encountered in API
responses should be flagged in the UI rather than crashing (render the raw ID).
