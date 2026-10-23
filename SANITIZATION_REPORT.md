# Sanitization inventory

## Principles

- Keep decisions, replacements, and verification visible.
- Allow historical attribution only in specific documentation and license files.
- Treat scan output as a gate, followed by human review.

| Source item | Decision and replacement | Verification |
| --- | --- | --- |
| Commercial project, bundle, team, profiles | New `PersonalBrowser` project, app/test IDs, unsigned default | `project.yml` and boundary scan |
| Commercial entitlement | Excluded; feature flags false | plist and boundary scan |
| Commercial icon and logo | Excluded; new vector/code-drawn mark | asset inventory |
| Application Support stores | `PersonalBrowser` namespace, separate app sandbox | source scan and device handoff |
| In-page bridge names | `personalbrowser` namespace | source scan |
| Fixed organization session and email/Role mapping | One Personal session; account inspection removed | source scan and tests |
| Commercial site link and PDF authorship | Site link removed; Personal Browser PDF author | source scan |
| Private install script and commercial docs | Excluded; generic guide | file inventory |
| Commercial release evidence | Retained only outside repository staging | file inventory |

The words **Prifina** and **Browser by Prifina** are retained only in classified lines for copyright, provenance, learning/testing references, public reporting contacts, or non-endorsement. No unclassified commercial domain, team ID, profile, support email, device ID, or storage namespace is allowed. Run `python3 scripts/verify_public_snapshot.py` to reproduce the source and Git-history checks.
