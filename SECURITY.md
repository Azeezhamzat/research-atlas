# Security Policy

Research Atlas is local-first software that can index private papers, notes, quotations, research plans, and provider credentials. Treat privacy regressions, unintended network transmission, path traversal, database corruption, citation-provenance loss, and credential-access changes as security-sensitive.

## Reporting a vulnerability

Do not include API keys, private papers, database files, exports, screenshots containing personal paths, or unpublished research in a public issue.

When the GitHub repository is available, use its private security-advisory channel for vulnerability reports. Include the affected version, macOS version, a minimal reproduction using synthetic data, expected and observed behaviour, and the security impact. If private reporting has not yet been enabled, contact the repository owner outside a public issue before sharing sensitive details.

## Supported version

Until a multi-version support policy is published, security fixes target the newest Research Atlas release. Older builds may not receive fixes.

## Credential boundary

Hosted-provider credentials are stored in an application-only macOS Keychain item. Ordinary launch and settings browsing must not read the secret. Secret reads are limited to an explicitly approved request or a user-initiated connection test; credentials must never enter the SQLite database, logs, exports, screenshots, fixtures, or repository.
