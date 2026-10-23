# Contributing to Research Atlas

Research Atlas handles sensitive scholarly material. Contributions must preserve local-first behaviour, exact provenance, explicit verification states, and user control.

By intentionally submitting a contribution for inclusion in Research Atlas, you agree that it is licensed under the project's [Apache License 2.0](LICENSE), as described by section 5 of that licence. Do not submit material you do not have the right to contribute.

## Before opening a change

1. Use only synthetic papers, notes, paths, identifiers, and screenshots in tests and documentation.
2. Never commit databases, backups, exports, source-project mirrors, model weights, credentials, or benchmark reports from a personal machine.
3. Keep core research workflows useful without AI. Any model path must retain exact source selection, an inspectable request preview, freshness validation, per-request approval, citation validation, saved provenance, and human review.
4. Do not write to a selected PDF folder or Obsidian vault.
5. Run:

   ```sh
   Scripts/verify-public-repository.sh
   swift run ResearchAtlasChecks
   ```

6. Describe user-visible changes and update the relevant guide, architecture, safety, integration, testing, or data-model documentation.

## Screenshots

Tutorial screenshots must show only the Research Atlas window. Use an isolated demonstration workspace, remove personal paths and unpublished research, and save public assets in `Support/Tutorial` with a `-public` suffix.

## Security reports

Follow `SECURITY.md`. Do not disclose a credential, private corpus, or exploitable vulnerability in a public issue.
