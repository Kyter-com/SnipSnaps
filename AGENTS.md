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

If reusing environment files from a local `asc-cli` checkout, verify the variable names expected by Homebrew `asc`. Older env files may use `ASC_KEY_PATH`; Homebrew `asc` expects `ASC_PRIVATE_KEY_PATH`.

Generic mapping pattern:

```sh
set -a
source /path/to/asc-cli/.env.<profile>
set +a

export ASC_PRIVATE_KEY_PATH="$ASC_KEY_PATH"
export ASC_BYPASS_KEYCHAIN=1
```

Only use real private key paths from the local developer environment. Never commit `.p8` files, key IDs, issuer IDs, private key contents, or private `.env` files. If App Store Connect calls fail with a missing private key file, stop and report that the key must be restored locally; it cannot be recreated from the key ID or issuer ID.

## Release Metadata

Keep local release metadata in sync when bumping a build or marketing version:

- `SnipSnaps.xcodeproj/project.pbxproj`
- `marketing/app-store-metadata/README.md`
- `marketing/app-store-metadata/app-store-connect.json`

Use the actual bullet glyph `•` for App Store "What's New" bullet-style notes.
