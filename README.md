# reusable-github-actions

Composite actions and one reusable workflow for supply-chain-aware CI on GitHub Actions.
Every downloaded tool is a pinned release whose SHA-256 is checked before it runs, and
every third-party action is pinned to a full commit SHA.

[![Test actions](https://github.com/JeanneBM/reusable-github-actions/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/JeanneBM/reusable-github-actions/actions/workflows/test.yml)

## Why pinned binaries and SHAs

In March 2026 the `aquasecurity/trivy-action` and `aquasecurity/setup-trivy` tags were
force-pushed to credential-stealing commits and a malicious Trivy release was published
([CVE-2026-33634](https://www.cve.org/CVERecord?id=CVE-2026-33634)). Workflows that
referenced mutable tags or installed "latest" during that window could run the attacker's code. These actions
therefore never resolve `latest`, never pipe a remote install script into a shell, and
refuse to install a version whose checksum is not supplied.

## Contents

| Path | Type | Purpose |
| --- | --- | --- |
| [`.github/workflows/security-baseline.yml`](.github/workflows/security-baseline.yml) | Reusable workflow | gitleaks over the Git history, Trivy vulnerability/secret/misconfiguration scan and a CycloneDX SBOM |
| [`security-scan`](security-scan/action.yml) | Composite action | Trivy scan of a path, repository or image, with optional SARIF upload |
| [`setup-trivy`](setup-trivy/action.yml) | Composite action | Verified Trivy install with a daily vulnerability-DB cache |
| [`setup-cosign`](setup-cosign/action.yml) | Composite action | Verified Cosign install |
| [`setup-terraform`](setup-terraform/action.yml) | Composite action | Terraform via `hashicorp/setup-terraform` with a provider cache |
| [`lib/versions.env`](lib/versions.env) | Pins | Tool versions and SHA-256 values used by the actions |
| [`lib/install-tool.sh`](lib/install-tool.sh) | Script | Download, verify and put a pinned tool on `PATH` |

## Security baseline workflow

Call it from another repository and pin the reference to a commit of this repository:

```yaml
name: Security
on:
  pull_request:
  push:
    branches: [main]
  schedule:
    - cron: '17 5 * * 1'

permissions:
  contents: read

jobs:
  baseline:
    permissions:
      contents: read
      # security-events: write   # only with upload-sarif: true
    uses: JeanneBM/reusable-github-actions/.github/workflows/security-baseline.yml@<commit-sha>
    with:
      severity: HIGH,CRITICAL
      fail-on-findings: true
```

| Input | Default | Meaning |
| --- | --- | --- |
| `severity` | `HIGH,CRITICAL` | Trivy severities that fail the scan |
| `fail-on-findings` | `true` | Set `false` to report without failing while you triage |
| `scan-history` | `true` | gitleaks scans all commits; `false` scans only checked-out files |
| `skip-dirs` | empty | Comma-separated directories for Trivy to skip |
| `upload-sarif` | `false` | Upload Trivy SARIF to the Security tab |

Reports (redacted gitleaks JSON, Trivy SARIF and `sbom.cdx.json`) are kept as workflow
artifacts for 14 days. Known false positives go in `.gitleaks.toml` or `.gitleaksignore`
and `.trivyignore` in the calling repository.

## Composite actions

```yaml
- uses: JeanneBM/reusable-github-actions/setup-trivy@<commit-sha>
- uses: JeanneBM/reusable-github-actions/security-scan@<commit-sha>
  with:
    path: .
    scanners: vuln,secret,misconfig
    upload-sarif: 'false'
```

`setup-trivy` and `setup-cosign` use the pins in `lib/versions.env`. To use another
release, pass both `version` and `sha256`; a version without a checksum, `latest` or a
mismatched checksum fails the step.

## Updating a pin

1. Take the SHA-256 from the release's checksums file (`trivy_<v>_checksums.txt`,
   `cosign_checksums.txt`, `gitleaks_<v>_checksums.txt`).
2. Update `lib/versions.env` and the matching `env` values in
   `security-baseline.yml`. The `pins-in-sync` test fails if they differ.
3. Action SHAs are updated by Dependabot (`.github/dependabot.yml`).

## Tests

[`test.yml`](.github/workflows/test.yml) consumes this repository on every pull request.

- The setup actions install the pinned versions and report them as outputs.
- Installs are refused for a version without a checksum, for `latest` and for a wrong checksum.
- `security-scan` fails on a generated root-user Dockerfile (DS-0002), writes valid SARIF
  and passes on a non-root Dockerfile.
- The reusable baseline runs against this repository.
