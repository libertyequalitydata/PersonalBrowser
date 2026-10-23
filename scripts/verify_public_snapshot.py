#!/usr/bin/env python3
"""Reproducible source, identity, credential, and privacy boundary checks."""
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ALLOWED_HISTORY = {
    "LICENSE": ["Copyright (c) 2026 Prifina Inc. and Liberty. Equality. Data. contributors"],
    "README.md": [
        "Personal Browser is an independent, local-first iPhone browser source snapshot periodically derived from the commercial [Browser by Prifina](https://browser.prifina.com/). It may not match the current commercial product. Snapshot `2026-10.1` is a separate application with its own bundle identifier, storage, artwork, and unsigned build defaults.",
        "- **Try the maintained end-user app:** [Browser product site](https://browser.prifina.com/) · [Join the Browser beta in TestFlight](https://testflight.apple.com/join/VZZPdDXA)",
        "- Browsing works without an account or hosted service: it does not require [Core by Prifina](https://core.prifina.com/), a [self-hosted Core](https://github.com/peecos/pios-core-self-hosted), or another [PIOS](https://github.com/peecos/pios)-compatible system.",
        "- **[Prifina](https://www.prifina.com/)** develops the continuously maintained commercial Browser app. The commercial app is useful for end-user testing; this repository remains a separately maintained source snapshot.",
        "- **Core** is the foundation and center of PIOS, providing its owner-controlled information, permissions, continuity and compatibility layer. PIOS is the wider operating system built around Core, and the Personal Ecosystem is the application and service environment enabled by PIOS. Core can be [self-hosted](https://github.com/peecos/pios-core-self-hosted), deployed by the owner in [AWS](https://github.com/peecos/pios-core-aws-template), or used through a compatible hosted service such as **[Core by Prifina](https://core.prifina.com/)**. No Core option is required or connected in this snapshot.",
        "- **[TestFlight](https://developer.apple.com/testflight/)** is Apple's beta-distribution service. The linked TestFlight build belongs to the commercial app, not to this source repository.",
        "The source is provided without warranty, hosted service, support SLA, or release cadence. Derivatives must not imply endorsement by Prifina, Liberty. Equality. Data., Apple, or supported websites. Product names and commercial identity are not licensed by the MIT source grant.",
    ],
    "Browser/Sources/Views/BrowserAboutView.swift": [
        "    static let commercialProductName = \"Browser by Prifina\"",
        "    static let commercialWebsiteURL = URL(string: \"https://browser.prifina.com/\")!",
        "    static let commercialBetaURL = URL(string: \"https://testflight.apple.com/join/VZZPdDXA\")!",
        "                Label(\"Open browser.prifina.com\", systemImage: \"arrow.up.right.square\")",
    ],
    "Browser/Tests/ChromeBarsModelTests.swift": [
        "        XCTAssertEqual(BrowserAboutPresentation.commercialProductName, \"Browser by Prifina\")",
        "        XCTAssertEqual(BrowserAboutPresentation.commercialWebsiteURL.host, \"browser.prifina.com\")",
    ],
    "SECURITY.md": ["For the public repository, use GitHub's **Report a vulnerability** action under the Security tab. It creates a private security advisory visible only to the reporter and repository maintainers. Do not post exploit details in a public issue. If GitHub private reporting is temporarily unavailable, email `hello@prifina.com` with the subject `Personal Browser security report` and include the minimum information needed to establish a private follow-up. No response-time or support SLA is promised. Do not include unrelated credentials, browsing data, or personal details in reports. This source snapshot has no hosted backend or managed Apple entitlement."],
    "CODE_OF_CONDUCT.md": ["Harassment, discrimination, threats, or disclosure of private information are not accepted. Maintainers may remove contributions or participation that violate these rules. Send private conduct reports to `hello@prifina.com` with the subject `Personal Browser conduct report`. Include only information relevant to the report and state whether the reporter's identity may be shared during review. Do not disclose conduct reports in public issues. This document creates no guaranteed moderation or response SLA."],
    "PUBLICATION_READINESS.md": ["- Owner authorization: MIT licensing, Prifina and Liberty. Equality. Data. attribution, and public repository publication explicitly approved."],
    ".github/ISSUE_TEMPLATE/config.yml": ["    url: https://browser.prifina.com/"],
    "SNAPSHOT.json": ['  "source_selected": "Browser by Prifina 0.1.0 (78)",'],
    "SOURCE_PROVENANCE.md": ["This local source snapshot was selected from Browser by Prifina version `0.1.0 (78)` on 2026-10-23. The source input was limited to app sources, tests, resources, supporting files, and project specification. The commercial Xcode project, signing/export records, website configuration, app data, and distribution history were excluded. No commercial Git history was available or reconstructed. Personal Browser starts from a clean source package. The previous commercial physical-device result establishes only why this input was chosen; it is not Personal Browser test evidence. The source and new artwork are offered under the repository MIT notice; commercial names and marks are not licensed as product identity."],
    "SANITIZATION_REPORT.md": ["The words **Prifina** and **Browser by Prifina** are retained only in classified lines for copyright, provenance, learning/testing references, public reporting contacts, or non-endorsement. No unclassified commercial domain, team ID, profile, support email, device ID, or storage namespace is allowed. Run `python3 scripts/verify_public_snapshot.py` to reproduce the source and Git-history checks."],
}
TEXT_SUFFIXES = {".swift", ".md", ".json", ".yml", ".yaml", ".plist", ".xcprivacy", ".svg", ".sh", ".py", ".txt"}
EXCLUDED_DIRS = {".git", "__pycache__", "PersonalBrowser.xcodeproj"}
issues = []
historical = []

def fail(path, line, message):
    issues.append(f"{path}:{line}: {message}")

patterns = {
    "owner or organization identity": re.compile(r"ValtoAI|Valto|Digiole", re.I),
    "commercial identity or storage": re.compile(r"BrowserByPrifina|browserByPrifina|browserbyprifina|(?:[A-Za-z0-9-]+\.)*prifina\.com\b|com\.prifina\b|group\.com\.prifina\b", re.I),
    "owner path": re.compile(r"/Users/[^/\s]+/"),
    "credential material": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\b(?:ghp_|github_pat_|sk-[A-Za-z0-9]{12})|\b(?:api[_-]?key|access[_-]?token|secret[_-]?key|password)\s*[:=]\s*['\"][^'\"]+['\"]", re.I),
    "device UDID": re.compile(r"\b[0-9a-fA-F]{40}\b|\b[0-9a-fA-F]{8}-[0-9a-fA-F]{16}\b"),
    "commercial release ID": re.compile(r"3F966NFD22|20261022|Makkaraperunat|App Store Connect|TestFlight|provisioning\.profile|\.p8\b", re.I),
}

for path in sorted(ROOT.rglob("*")):
    relative = path.relative_to(ROOT).as_posix()
    if any(part in EXCLUDED_DIRS for part in path.relative_to(ROOT).parts):
        continue
    if path.is_dir():
        if path.name in {"DerivedData", "build"}:
            fail(relative, 0, "generated build directory")
        continue
    if path.suffix in {".ipa", ".xcarchive", ".xcresult", ".mobileprovision", ".p8", ".p12", ".cer", ".key", ".entitlements", ".env", ".pem", ".zip"} or path.name.startswith(".env"):
        fail(relative, 0, "binary, key, profile, or build artifact")
    if path.suffix not in TEXT_SUFFIXES and relative not in {"LICENSE", ".gitignore", "Browser/Resources/Assets.xcassets/AppIcon.appiconset/personal-browser-app-icon.png"}:
        fail(relative, 0, "unreviewed file type")
    if path.suffix not in TEXT_SUFFIXES and relative not in {"LICENSE", ".gitignore"} or relative == "scripts/verify_public_snapshot.py":
        continue
    try:
        content = path.read_text()
    except UnicodeDecodeError:
        fail(relative, 0, "unexpected non-text source")
        continue
    for number, line in enumerate(content.splitlines(), 1):
        classified_reference = line in ALLOWED_HISTORY.get(relative, [])
        for label, pattern in patterns.items():
            if pattern.search(line):
                if label == "commercial release ID" and relative == ".gitignore" and line == "*.p8":
                    continue
                if classified_reference and label in {"commercial identity or storage", "commercial release ID"}:
                    continue
                fail(relative, number, label)
        if re.search(r"Prifina", line, re.I):
            if classified_reference:
                historical.append(f"{relative}:{number}")
            else:
                fail(relative, number, "unclassified commercial name")

project = (ROOT / "project.yml").read_text()
if "org.libertyequalitydata.personalbrowser" not in project or "CODE_SIGNING_ALLOWED: \"NO\"" not in project:
    fail("project.yml", 0, "expected independent unsigned app identity missing")
if "DEVELOPMENT_TEAM" in project or "CODE_SIGN_ENTITLEMENTS" in project or "PROVISIONING_PROFILE" in project:
    fail("project.yml", 0, "signing or entitlement material present")
if (ROOT / "Browser/Supporting/Browser.entitlements").exists():
    fail("Browser/Supporting/Browser.entitlements", 0, "managed entitlement file present")

info = plistlib.loads((ROOT / "Browser/Supporting/Info.plist").read_bytes())
for key in ("BrowserAddToHomeScreenEnabled", "BrowserPasskeyAuthorizationEnabled"):
    if info.get(key) is not False:
        fail("Browser/Supporting/Info.plist", 0, f"{key} must be false")
if info.get("CFBundleDisplayName") != "Personal Browser":
    fail("Browser/Supporting/Info.plist", 0, "wrong display name")
for key in ("NSPhotoLibraryUsageDescription", "NSLocationAlwaysUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription", "NSHomeKitUsageDescription", "NSBluetoothAlwaysUsageDescription", "NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"):
    if key in info:
        fail("Browser/Supporting/Info.plist", 0, f"prohibited privacy key: {key}")
privacy = plistlib.loads((ROOT / "Browser/Resources/PrivacyInfo.xcprivacy").read_bytes())
if privacy.get("NSPrivacyTracking") is not False or privacy.get("NSPrivacyCollectedDataTypes") != []:
    fail("Browser/Resources/PrivacyInfo.xcprivacy", 0, "privacy declaration changed")
if "NSPrivacyTrackingDomains" not in privacy or privacy["NSPrivacyTrackingDomains"] != []:
    fail("Browser/Resources/PrivacyInfo.xcprivacy", 0, "tracking domains present")
api_types = privacy.get("NSPrivacyAccessedAPITypes", [])
if api_types != [{"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults", "NSPrivacyAccessedAPITypeReasons": ["CA92.1"]}]:
    fail("Browser/Resources/PrivacyInfo.xcprivacy", 0, "unexpected accessed API declaration")

required = ["LICENSE", "README.md", "SNAPSHOT_MODEL.md", "SNAPSHOT.json", "PRIVACY.md", "SECURITY.md", "CONTRIBUTING.md", "CODE_OF_CONDUCT.md", "THIRD_PARTY_NOTICES.md", "CHANGELOG.md", "AGENTS.md", ".gitignore", "SOURCE_PROVENANCE.md", "SANITIZATION_REPORT.md", "PUBLICATION_READINESS.md", "docs/BUILD_AND_SIGNING.md", "docs/DEFAULT_BROWSER_ENTITLEMENT.md", "docs/ARCHITECTURE.md", "docs/FEATURES_AND_LIMITATIONS.md", "docs/MAINTAINER_GUIDE.md", "docs/AGENT_START_PROMPT.md", "docs/RELEASE_NOTES_2026-10.1.md", "docs/images/new-tab.svg", "docs/images/tabs.svg", "docs/images/library.svg", ".github/ISSUE_TEMPLATE/bug_report.md", ".github/ISSUE_TEMPLATE/feature_request.md", ".github/ISSUE_TEMPLATE/config.yml", ".github/PULL_REQUEST_TEMPLATE.md", ".github/workflows/public-boundary.yml"]
for relative in required:
    if not (ROOT / relative).is_file():
        fail(relative, 0, "required public package file missing")
try:
    json.loads((ROOT / "SNAPSHOT.json").read_text())
except (ValueError, OSError) as error:
    fail("SNAPSHOT.json", 0, str(error))

git_dir = ROOT / ".git"
if git_dir.exists():
    try:
        commits = subprocess.check_output(["git", "rev-list", "--all"], cwd=ROOT, text=True).splitlines()
        history_pattern = r"-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|github_pat_|ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{12,}|3F966NFD22|Makkaraperunat|/Users/[^/[:space:]]+|[0-9a-fA-F]{8}-[0-9a-fA-F]{16}"
        artifact_pattern = re.compile(r"\.(p8|p12|pem|key|mobileprovision|cer|ipa|xcarchive|xcresult|env|zip)$|(^|/)\.env($|\.)|(^|/)DerivedData/|(^|/)build/", re.I)
        for commit in commits:
            paths = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", commit], cwd=ROOT, text=True).splitlines()
            for relative in paths:
                if artifact_pattern.search(relative):
                    fail(relative, 0, f"disallowed artifact exists in Git history at {commit[:12]}")
            result = subprocess.run(
                ["git", "grep", "-I", "-n", "-E", "-e", history_pattern, commit, "--", ".", ":(exclude)scripts/verify_public_snapshot.py"],
                cwd=ROOT,
                text=True,
                capture_output=True,
            )
            if result.returncode not in (0, 1):
                fail(".git", 0, f"Git-history content scan failed at {commit[:12]}: {result.stderr.strip()}")
            elif result.stdout.strip():
                fail(".git", 0, f"sensitive content exists in Git history at {commit[:12]}: {result.stdout.strip()}")
    except (OSError, subprocess.CalledProcessError) as error:
        fail(".git", 0, f"Git-history scan failed: {error}")

print(f"Scanned source package; {len(historical)} classified historical name uses; {len(issues)} issues")
for item in historical:
    print(f"  historical: {item}")
for item in issues:
    print(f"  FAIL: {item}")
sys.exit(1 if issues else 0)
