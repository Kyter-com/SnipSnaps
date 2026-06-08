# Changesets

Use Changesets for user-facing release notes and version bumps.

```sh
npm run changeset
```

Write the changeset body as App Store-ready prose. The release script converts each note into a `•` bullet for App Store Connect.

Example:

```md
---
"@kyter/snipsnaps-ios": patch
---

Improved similar-photo review progress so large libraries feel more predictable.
```

Use `patch` for fixes and polish, `minor` for user-visible feature work, and `major` only for coordinated compatibility or product-breaking changes.
