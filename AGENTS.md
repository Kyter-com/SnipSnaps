# Agent Notes

## App Store Connect CLI

Use the Homebrew `asc` binary for App Store Connect workflows:

```sh
/opt/homebrew/bin/asc
```

Do not assume the local Python development checkout of `asc-cli` has the same flags as the Homebrew CLI. In particular, Homebrew `asc` uses subcommands such as:

```sh
/opt/homebrew/bin/asc auth status
/opt/homebrew/bin/asc status --app <bundle-id-or-app-id>
/opt/homebrew/bin/asc builds info --app <bundle-id-or-app-id> --build-number <build> --version <version> --platform IOS
/opt/homebrew/bin/asc builds test-notes create --app <bundle-id-or-app-id> --build-number <build> --version <version> --platform IOS --locale en-US --whats-new "<notes>"
/opt/homebrew/bin/asc builds test-notes update --app <bundle-id-or-app-id> --build-number <build> --version <version> --platform IOS --locale en-US --whats-new "<notes>"
```

For release scripts, prefer the 1Password item-backed auth flow instead of storing private key paths in repo-local files:

```sh
ASC_OP_ITEM=<1password-item-id-or-name> npm run release:status
```

The script reads `key_id`, `issuer_id`, and `credential` from the 1Password item, writes the private key to a temporary `0600` file for `asc`, and deletes it on exit.

To discover the right item, inspect only 1Password item metadata and field labels/types. Do not print field values.

```sh
op item list --format json --long
op item get <candidate-item> --format json
```

If calling `asc` directly, use a private environment outside this repo and never print credential values.

Generic direct-`asc` variables:

```sh
ASC_KEY_ID=<from-private-env>
ASC_ISSUER_ID=<from-private-env>
ASC_PRIVATE_KEY_PATH=<local-private-key-path>
ASC_BYPASS_KEYCHAIN=1
```

Only use real private key paths from the local developer environment. Never commit `.p8` files, key IDs, issuer IDs, private key contents, or private `.env` files.

## Release Tracking

ASC plus git plus Changesets are the release source of truth.

- Use `npm run changeset` for user-facing changes.
- Use `npm run version` to snapshot `docs/next-release-notes.md`, consume changesets into `CHANGELOG.md`, and sync Xcode `MARKETING_VERSION`.
- Use `ASC_OP_ITEM=<1password-item-id-or-name> npm run release:next-build -- --apply` to get the next build number from ASC and sync Xcode `CURRENT_PROJECT_VERSION`.
- Use `ASC_OP_ITEM=<1password-item-id-or-name> npm run release:backfill` to regenerate `docs/apple-release-history.md` from ASC and git.
- Do not treat `marketing/app-store-metadata/app-store-connect.json` as authoritative release metadata; it may be stale.

Use the actual bullet glyph `•` for App Store "What's New" bullet-style notes.
