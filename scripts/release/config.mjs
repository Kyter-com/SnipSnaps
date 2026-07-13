export default {
  appName: "SnipSnaps",
  packageName: "@kyter/snipsnaps-ios",
  bundleId: "com.kyter.SnipSnaps",
  appId: "6746975535",
  // Default platform for single-platform commands. SnipSnaps ships as one
  // universal-purchase record, so `platforms` lists every ASC platform the
  // same app id serves; pass `--platform all` to act on all of them.
  platform: "IOS",
  platforms: ["IOS", "MAC_OS"],
  locale: "en-US",
  xcodeProject: "SnipSnaps.xcodeproj/project.pbxproj",
  releaseHistoryPath: "docs/apple-release-history.md",
  nextReleaseNotesPath: "docs/next-release-notes.md",
  gitTagPrefix: "snipsnaps-ios@",
  commitSyntax: "imperative",
};
