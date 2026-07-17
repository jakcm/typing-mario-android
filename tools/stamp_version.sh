#!/bin/bash
# Stamp the current build time (yyyyMMddHHmm) into lib/version.dart, then you
# can run the release build so the on-screen Version matches the artifact.
set -euo pipefail
cd "$(dirname "$0")/.."
STAMP=$(date +%Y%m%d%H%M)
cat > lib/version.dart <<EOF
/// Build version stamp shown on the main menu.
///
/// Format: yyyyMMddHHmm, set at build time. Update this immediately before
/// running \`flutter build apk --release\` so the on-screen value matches the
/// artifact. See tools/stamp_version.sh which rewrites this file.
const String kBuildVersion = '${STAMP}';
EOF
echo "Stamped kBuildVersion = ${STAMP}"
