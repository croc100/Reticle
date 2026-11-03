#!/usr/bin/env python3
"""Fail the build when the two changelogs and the bundle version disagree.

Three files have to tell the same story about what shipped:

  CHANGELOG.md                    the repository's record
  site/src/pages/changelog.astro  the page Sparkle sends updating users to
  App/Info.plist                  the version the app reports

They drifted once already. Versions 0.2.0 through 0.5.0 were tagged and
released and the site page was updated each time, while CHANGELOG.md went
untouched for four releases -- two commits even claimed to have updated it.
Nothing noticed, because nothing checked.
"""

from __future__ import annotations

import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

CHANGELOG = ROOT / "CHANGELOG.md"
SITE_CHANGELOG = ROOT / "site" / "src" / "pages" / "changelog.astro"
INFO_PLIST = ROOT / "App" / "Info.plist"

# "## [0.4.0] - 2026-06-03", and "## [Unreleased]", which carries no version.
HEADING = re.compile(r"^##\s*\[([^\]]+)\]")
# "version: '0.4.0'," in the site page's release array.
SITE_VERSION = re.compile(r"^\s*version:\s*'([^']+)'", re.MULTILINE)

UNRELEASED = "unreleased"


def changelog_versions() -> list[str]:
    """Released versions from CHANGELOG.md, newest first."""
    versions = []
    for line in CHANGELOG.read_text(encoding="utf-8").splitlines():
        match = HEADING.match(line)
        if match and match.group(1).strip().lower() != UNRELEASED:
            versions.append(match.group(1).strip())
    return versions


def site_versions() -> list[str]:
    """Versions listed on the site's changelog page, in page order."""
    return SITE_VERSION.findall(SITE_CHANGELOG.read_text(encoding="utf-8"))


def bundle_version() -> str:
    with INFO_PLIST.open("rb") as handle:
        return plistlib.load(handle)["CFBundleShortVersionString"]


def main() -> int:
    problems: list[str] = []

    changelog = changelog_versions()
    site = site_versions()
    bundle = bundle_version()

    if not changelog:
        problems.append("CHANGELOG.md lists no released versions at all.")

    missing_from_changelog = [v for v in site if v not in changelog]
    missing_from_site = [v for v in changelog if v not in site]

    if missing_from_changelog:
        problems.append(
            "Released on the site but absent from CHANGELOG.md: "
            + ", ".join(missing_from_changelog)
        )
    if missing_from_site:
        problems.append(
            "In CHANGELOG.md but absent from site/src/pages/changelog.astro: "
            + ", ".join(missing_from_site)
        )

    # The bundle version is allowed to match the newest released entry only.
    # Bumping Info.plist is part of cutting a release, so a mismatch means
    # either the bump or the changelog entry was forgotten.
    if changelog and changelog[0] != bundle:
        problems.append(
            f"App/Info.plist reports {bundle}, but the newest CHANGELOG.md entry "
            f"is {changelog[0]}. Add the entry, or correct the bundle version."
        )

    if problems:
        print("Version consistency check failed:\n", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        print(
            "\nWhen you cut a release, all three need updating: CHANGELOG.md, "
            "site/src/pages/changelog.astro and App/Info.plist.",
            file=sys.stderr,
        )
        return 1

    print(f"OK: {len(changelog)} releases, newest {changelog[0]}, matching Info.plist.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
