# AINCRAD Discovery

A native macOS file browser in the same SAO-style design as the AINCRAD launcher and AINCRAD Browser. It reads the shared AINCRAD theme from `~/Library/Application Support/AINCRAD/`.

## Build

    ./scripts/build.sh

Requires XcodeGen. Builds Release into `~/Library/Caches/AINCRAD-Discovery-build` (not inside iCloud-synced Documents) and installs to `/Applications/AINCRAD Discovery.app`.

## Permissions

None are needed up front. When you open a folder macOS protects (Desktop, Documents, Downloads, external volumes), macOS prompts once.
