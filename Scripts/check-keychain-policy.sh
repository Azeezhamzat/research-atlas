#!/bin/zsh
set -euo pipefail

SCRIPT_DIRECTORY="${0:A:h}"
PROJECT_DIRECTORY="${SCRIPT_DIRECTORY:h}"
APP_MODEL="${PROJECT_DIRECTORY}/AppSources/ResearchAtlasApp/AppModel.swift"
KEYCHAIN_STORE="${PROJECT_DIRECTORY}/AppSources/ResearchAtlasApp/KeychainSecretStore.swift"
BUILD_SCRIPT="${PROJECT_DIRECTORY}/Scripts/build-app.sh"

fail() {
  print -u2 "Keychain policy check failed: $1"
  exit 1
}

read_count="$(rg -c 'KeychainSecretStore\.read\(' "${APP_MODEL}")"
[[ "${read_count}" == "1" ]] || fail "expected one guarded credential helper read, found ${read_count}"

rg -q 'aiCredentialStored = KeychainSecretStore\.rememberedPresence\(' "${APP_MODEL}" || \
  fail "workspace reload must use the non-Keychain presence marker"
rg -q 'func refreshAICredentialState\(for provider: AIProviderKind\).*' "${APP_MODEL}" || \
  fail "provider credential-state refresh is missing"
rg -q 'private func credentialForRequest\(provider: AIProviderKind\)' "${APP_MODEL}" || \
  fail "the guarded credential helper is missing"
rg -q 'guard provider\.requiresCredential else \{ return "" \}' "${APP_MODEL}" || \
  fail "credential-free local providers must not query Keychain"
rg -q 'func testAIProviderConnection\(\)' "${APP_MODEL}" || \
  fail "the explicit provider connection-test path is missing"
helper_call_count="$(rg -c 'let credential = try credentialForRequest\(provider:' "${APP_MODEL}")"
[[ "${helper_call_count}" == "2" ]] || fail "credential helper must be called only by approved send and explicit connection test, found ${helper_call_count} calls"
rg -q 'let credential = try credentialForRequest\(provider: configuration\.provider\)' "${APP_MODEL}" || \
  fail "the explicit connection test must use the guarded credential helper"
rg -q 'let credential = try credentialForRequest\(provider: preview\.provider\)' "${APP_MODEL}" || \
  fail "the approved transmission path must use the guarded credential helper"
credential_read_line="$(rg -n 'let credential = try credentialForRequest\(provider: preview\.provider\)' "${APP_MODEL}" | cut -d: -f1)"
request_begin_line="$(rg -n 'didBeginExternalRequest = true' "${APP_MODEL}" | cut -d: -f1)"
[[ -n "${request_begin_line}" && "${credential_read_line}" -lt "${request_begin_line}" ]] || \
  fail "transmission counts must not begin before the credential is available"
rg -q 'if !didBeginExternalRequest' "${APP_MODEL}" || \
  fail "pre-network failures must reset transmitted counts to zero"

if rg -q 'migrateLegacy' "${PROJECT_DIRECTORY}/AppSources/ResearchAtlasApp"; then
  fail "automatic legacy migration must not run during launch or settings browsing"
fi

rg -q 'app\.researchatlas\.desktop\.ai-provider\.v3' "${KEYCHAIN_STORE}" || \
  fail "credentials must use the fresh versioned service that cannot collide with retired items"
rg -q 'kSecUseAuthenticationContext' "${KEYCHAIN_STORE}" || \
  fail "credential operations must supply a non-interactive authentication context"
rg -q 'interactionNotAllowed = true' "${KEYCHAIN_STORE}" || \
  fail "the authentication context must explicitly refuse macOS dialogs"
rg -q 'SecAccessCreate\(' "${KEYCHAIN_STORE}" || \
  fail "new credentials must use an explicit application-only Keychain access object"
rg -q 'identifier "app\.researchatlas\.desktop"' "${BUILD_SCRIPT}" || \
  fail "the local app must retain a stable designated requirement across rebuilds"

if rg -q 'kSecUseDataProtectionKeychain' "${KEYCHAIN_STORE}"; then
  fail "ad-hoc builds cannot claim the provisioned data-protection Keychain entitlement"
fi

if rg -q 'legacyAccount|configured-api-key' "${KEYCHAIN_STORE}"; then
  fail "legacy login-Keychain credentials must never be queried because they can display a password prompt"
fi

if rg -q 'KeychainSecretStore\.contains\(|kSecReturnAttributes as String: true|kSecUseAuthenticationUI' "${APP_MODEL}" "${KEYCHAIN_STORE}"; then
  fail "launch and settings paths must not probe Keychain, even for metadata"
fi

print "Keychain policy check passed: launch and settings browsing never contact Keychain; new items use an explicit application-only ACL under a stable app requirement; secret access is approved-send/explicit-test/save/remove only."
