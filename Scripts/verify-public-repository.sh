#!/bin/zsh
set -euo pipefail

SCRIPT_DIRECTORY="${0:A:h}"
PROJECT_DIRECTORY="${SCRIPT_DIRECTORY:h}"
cd "${PROJECT_DIRECTORY}"

fail() {
  print -u2 "Public repository check failed: $1"
  exit 1
}

required_files=(
  "LICENSE"
  "NOTICE"
  "README.md"
  "INSTALL.md"
  "UNIVERSAL_USER_GUIDE.md"
  "SECURITY.md"
  "CONTRIBUTING.md"
  "THIRD_PARTY_NOTICES.md"
  "RELEASE_CHECKLIST.md"
  "Support/Tutorial/learning-center-hero-public.png"
  "Support/Tutorial/local-folder-library-public.png"
  "Support/Tutorial/question-coverage-audit-public.png"
  "Support/Tutorial/universal-home-public.png"
  "Support/Tutorial/universal-integrations-public.png"
  "Support/Tutorial/universal-learning-center-public.png"
  "Support/Tutorial/universal-reading-desk-public.png"
  "Desktop/package.json"
  "Desktop/package-lock.json"
  "Desktop/src/main.js"
  "Desktop/src/preload.cjs"
)
for file in "${required_files[@]}"; do
  [[ -f "${file}" ]] || fail "required release file is missing: ${file}"
done

private_examples=(
  "Backups/private.sqlite3"
  "Exports/private/research-atlas.json"
  "sources/private-reference.md"
  "Benchmarks/research-atlas-performance-local.json"
  "Build/Research Atlas.app/Contents/MacOS/ResearchAtlas"
  "private-model.gguf"
  ".env"
  "Support/Tutorial/learning-center-hero.png"
  "Support/Tutorial/local-folder-library.png"
  "Support/Tutorial/evidence-provenance.png"
  "Support/Tutorial/question-coverage-audit.png"
  "Desktop/node_modules/electron/index.js"
  "Desktop/out/Research Atlas-darwin-arm64/Research Atlas.app/Contents/MacOS/research-atlas"
)
for file in "${private_examples[@]}"; do
  git check-ignore --quiet --no-index -- "${file}" || fail "ignore policy does not cover ${file}"
done

for file in Support/Tutorial/*-public.png; do
  git check-ignore --quiet --no-index -- "${file}" && fail "public tutorial asset is ignored: ${file}"
done

for private_path in Backups Exports sources Build .build Desktop/node_modules Desktop/out; do
  tracked="$(git ls-files -- "${private_path}/**")"
  [[ -z "${tracked}" ]] || fail "private/generated path is tracked: ${private_path}"
done

candidate_files=("${(@0)$(git ls-files --cached --others --exclude-standard -z)}")
text_files=()
for file in "${candidate_files[@]}"; do
  [[ -f "${file}" ]] || continue
  size="$(stat -f %z -- "${file}")"
  (( size <= 50 * 1024 * 1024 )) || fail "file exceeds 50 MiB: ${file}"
  case "${file:l}" in
    *.png|*.jpg|*.jpeg|*.gif|*.pdf|*.zip|*.sqlite3|*.db) ;;
    *) text_files+=("${file}") ;;
  esac
done

if (( ${#text_files[@]} > 0 )); then
  secret_pattern='sk-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
  secret_files="$(rg -l --no-messages -- "${secret_pattern}" "${text_files[@]}" || true)"
  [[ -z "${secret_files}" ]] || fail "possible credential material found in: ${(j:, :)${(f)secret_files}}"

  home_path_pattern='/Users/[[:alnum:]_.-]+/'
  path_files="$(rg -l --no-messages -- "${home_path_pattern}" "${text_files[@]}" || true)"
  [[ -z "${path_files}" ]] || fail "absolute macOS home path found in: ${(j:, :)${(f)path_files}}"
fi

"${SCRIPT_DIRECTORY}/check-keychain-policy.sh"
plutil -lint Support/Info.plist >/dev/null
print "Public repository check passed: private data is ignored, release assets are present, and no common secret or personal-path pattern was found."
