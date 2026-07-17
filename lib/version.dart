/// Build version stamp shown on the main menu.
///
/// Format: yyyyMMddHHmm, set at build time. Update this immediately before
/// running `flutter build apk --release` so the on-screen value matches the
/// artifact. See tools/stamp_version.sh which rewrites this file.
const String kBuildVersion = '202607160034';
