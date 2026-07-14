# Release Workflow

SnipSnaps uses App Store Connect (`asc`) as the source of truth for Apple versions/builds and Changesets as the source of truth for upcoming changelog and release-note text.

Do not treat `marketing/app-store-metadata/app-store-connect.json` as authoritative for releases.

## Tools

- Node/npm for Changesets release tooling.
- Homebrew `asc` at `/opt/homebrew/bin/asc` for App Store Connect.
- 1Password CLI (`op`) for injecting ASC credentials into the shell.

Keep ASC secrets in 1Password or a private local env file. Do not commit API key IDs, issuer IDs, private keys, private key paths, or private env filenames.

Preferred private env shape:

```sh
ASC_OP_ACCOUNT=<optional-account-domain>
ASC_OP_VAULT=<optional-vault-name>
ASC_OP_ITEM=<1password-item-id-or-name>
ASC_BYPASS_KEYCHAIN=1
```

The script reads `key_id`, `issuer_id`, and `credential` from that 1Password item, writes the private key to a temporary `0600` file for `asc`, and deletes it on exit.

The 1Password item must have fields labeled exactly `key_id`, `issuer_id`, and `credential`. `credential` should contain the App Store Connect `.p8` private key contents. Keep the actual item ID/name in a private env file or local shell history, not in git.

Run ASC-backed commands through `op run`:

```sh
op run --env-file <private-asc-env> -- npm run release:status
```

Or pass the item reference inline:

```sh
ASC_OP_ITEM=<1password-item-id-or-name> npm run release:status
```

Safe credential discovery for agents:

```sh
op item list --format json --long | node -e '<filter item titles/tags only; do not print fields>'
op item get <candidate-item> --format json | node -e '<print field labels/types only; do not print values>'
```

Never print `credential`, `key_id`, `issuer_id`, `.p8` contents, or private key paths in logs.

## Daily Development

For each user-facing change, add a changeset before merging or releasing:

```sh
npm run changeset
```

Use this syntax:

```md
---
"@kyter/snipsnaps-ios": patch
---

Improved similar-photo review progress so large libraries feel more predictable.
```

SnipSnaps commit messages can stay concise and imperative. Changeset bodies should be user-facing and App Store-ready.

## How release notes flow (changeset → App Store)

Release-note text has one source of truth (Changesets) and is transformed into App Store "What's New" automatically:

1. **Write** — each user-facing change adds a changeset (`npm run changeset`) whose body is App Store-ready prose. Leading `-`/`*`/`•` bullets are optional; the tooling normalizes them. **Prefer one change per changeset** (or one bullet per line): a single changeset whose body has multiple blank-line-separated paragraphs collapses in `CHANGELOG.md` into one bullet with indented sub-paragraphs, which reads as a single item.
2. **Snapshot** — `npm run version` runs `notes --write-default` (writing `docs/next-release-notes.md`) *before* `changeset version` consumes the changesets into `CHANGELOG.md`. This preserves the exact notes after the changesets are gone.
3. **Format** — `formatNotes()` dedupes and prepends `• ` to every line, so App Store notes always come out as `•`-prefixed bullets. **You never add the dot by hand.**
4. **Apply** — `npm run release:apply-notes -- --platform all --confirm` pushes notes to ASC (App Store "What's New" + TestFlight "What to Test"). It uses pending changesets if any, otherwise falls back to `docs/next-release-notes.md`.
5. **Verify** — `npm run release:notes:verify -- --platform all` compares the local notes against what is actually live in ASC for the current `MARKETING_VERSION`, per platform. Exit code is non-zero on drift, so it can gate a release.

**Ordering matters.** `docs/next-release-notes.md` is a generated file that lingers in git showing the *last* release's notes. Always run `npm run version` for the new release **before** `apply-notes`, so the file is regenerated. `apply-notes` dry-runs by default (omit `--confirm`) and prints the target version + exact notes — read that before confirming, and run `release:notes:verify` afterward.

**First release on a platform.** Apple does not allow "What's New" on the *first* App Store version for a platform (e.g. the first macOS build). The API returns `whatsNew cannot be edited at this time` and the App Store shows the **description** instead. `apply-notes` now skips this case with a message instead of failing (so `--platform all` survives a platform launch), and `verify-notes` reports it as `⚠` (expected), not drift.

**Use the tooling, not raw `asc`.** Apply notes via `npm run release:apply-notes` so both platforms and both targets (App Store + TestFlight) stay consistent, rather than editing localizations by hand.

## Release Prep

1. Review pending notes:

```sh
npm run release:notes
```

2. Snapshot the App Store notes, consume changesets into `CHANGELOG.md`, bump `package.json`, and sync Xcode `MARKETING_VERSION`:

```sh
npm run version
```

This writes `docs/next-release-notes.md` before Changesets consumes the pending changesets, so the exact notes can still be applied after the Apple build finishes processing.

3. Ask ASC for the next build number and apply it to Xcode:

```sh
op run --env-file <private-asc-env> -- npm run release:next-build -- --apply
```

4. Commit the release files and push to the release branch used by Xcode Cloud or your archive workflow.

5. After the build exists in App Store Connect, update TestFlight and App Store notes from pending changesets or `docs/next-release-notes.md`:

```sh
op run --env-file <private-asc-env> -- npm run release:apply-notes -- --target both --confirm
```

6. Tag the exact git commit that produced the Apple build:

```sh
npm run release:tag -- --confirm
git push --tags
```

Tags use `snipsnaps-ios@<marketing-version>+<build-number>`.

## Backfill

When ASC credentials are active, generate correlated Apple release history:

```sh
op run --env-file <private-asc-env> -- npm run release:backfill
```

This writes `docs/apple-release-history.md` from ASC versions/builds and git commits that changed Xcode version/build settings.
