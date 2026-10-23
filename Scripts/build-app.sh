#!/bin/zsh
set -euo pipefail

SCRIPT_DIRECTORY="${0:A:h}"
PROJECT_DIRECTORY="${SCRIPT_DIRECTORY:h}"
SCRATCH_DIRECTORY="/private/tmp/research-atlas-build"
CACHE_DIRECTORY="/private/tmp/research-atlas-cache"
CONFIG_DIRECTORY="/private/tmp/research-atlas-config"
SECURITY_DIRECTORY="/private/tmp/research-atlas-security"
CLANG_CACHE_DIRECTORY="/private/tmp/research-atlas-clang-cache"
SWIFT_CACHE_DIRECTORY="/private/tmp/research-atlas-swift-cache"
APP_DIRECTORY="${PROJECT_DIRECTORY}/Build/Research Atlas.app"

"${SCRIPT_DIRECTORY}/check-keychain-policy.sh"

if [[ -d "/Applications/Xcode.app" ]]; then
  SDK_DIRECTORY="$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --show-sdk-path)"
elif [[ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" ]]; then
  # The installed macOS 26.5 SDK and Swift compiler are mismatched on the current host.
  SDK_DIRECTORY="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
else
  SDK_DIRECTORY="$(xcrun --show-sdk-path)"
fi

mkdir -p "${APP_DIRECTORY}/Contents/MacOS"
mkdir -p "${APP_DIRECTORY}/Contents/Resources/Tutorial"
mkdir -p "${APP_DIRECTORY}/Contents/Resources/Runtime"
rm -f \
  "${APP_DIRECTORY}/Contents/Resources/Tutorial/zotero-linkage.png" \
  "${APP_DIRECTORY}/Contents/Resources/Tutorial/learning-center-hero.png" \
  "${APP_DIRECTORY}/Contents/Resources/Tutorial/local-folder-library.png" \
  "${APP_DIRECTORY}/Contents/Resources/Tutorial/evidence-provenance.png" \
  "${APP_DIRECTORY}/Contents/Resources/Tutorial/question-coverage-audit.png"

CLANG_MODULE_CACHE_PATH="${CLANG_CACHE_DIRECTORY}" \
SWIFT_MODULECACHE_PATH="${SWIFT_CACHE_DIRECTORY}" \
SDKROOT="${SDK_DIRECTORY}" \
swift build \
  --disable-sandbox \
  --configuration release \
  --product ResearchAtlas \
  --package-path "${PROJECT_DIRECTORY}" \
  --scratch-path "${SCRATCH_DIRECTORY}" \
  --cache-path "${CACHE_DIRECTORY}" \
  --config-path "${CONFIG_DIRECTORY}" \
  --security-path "${SECURITY_DIRECTORY}"

BIN_DIRECTORY="$(
  CLANG_MODULE_CACHE_PATH="${CLANG_CACHE_DIRECTORY}" \
  SWIFT_MODULECACHE_PATH="${SWIFT_CACHE_DIRECTORY}" \
  SDKROOT="${SDK_DIRECTORY}" \
  swift build \
    --disable-sandbox \
    --configuration release \
    --product ResearchAtlas \
    --package-path "${PROJECT_DIRECTORY}" \
    --scratch-path "${SCRATCH_DIRECTORY}" \
    --cache-path "${CACHE_DIRECTORY}" \
    --config-path "${CONFIG_DIRECTORY}" \
    --security-path "${SECURITY_DIRECTORY}" \
    --show-bin-path
)"
cp "${BIN_DIRECTORY}/ResearchAtlas" "${APP_DIRECTORY}/Contents/MacOS/ResearchAtlas"
if strings "${APP_DIRECTORY}/Contents/MacOS/ResearchAtlas" | rg -q '/Users/[[:alnum:]_.-]+/'; then
  echo "The release executable contains an absolute macOS home path; remove development-only #filePath usage before packaging." >&2
  exit 1
fi
cp "${PROJECT_DIRECTORY}/Support/Info.plist" "${APP_DIRECTORY}/Contents/Info.plist"
cp "${PROJECT_DIRECTORY}/Support/Tutorial/learning-center-hero-public.png" "${APP_DIRECTORY}/Contents/Resources/Tutorial/learning-center-hero-public.png"
cp "${PROJECT_DIRECTORY}/Support/Tutorial/local-folder-library-public.png" "${APP_DIRECTORY}/Contents/Resources/Tutorial/local-folder-library-public.png"
cp "${PROJECT_DIRECTORY}/Support/Tutorial/question-coverage-audit-public.png" "${APP_DIRECTORY}/Contents/Resources/Tutorial/question-coverage-audit-public.png"
cp "${PROJECT_DIRECTORY}/USER_GUIDE.md" "${APP_DIRECTORY}/Contents/Resources/USER_GUIDE.md"
cp "${PROJECT_DIRECTORY}/THIRD_PARTY_NOTICES.md" "${APP_DIRECTORY}/Contents/Resources/THIRD_PARTY_NOTICES.md"

# Ship the small inference runtime inside Research Atlas so using the default local model does
# not require launching Ollama or LM Studio. Model weights remain in Ollama's normal local store
# and are neither copied into the app nor uploaded anywhere.
OLLAMA_SOURCE=""
LLAMA_SERVER_SOURCE=""
for CANDIDATE in \
  "/opt/homebrew/bin/ollama" \
  "/usr/local/bin/ollama" \
  "/Applications/Ollama.app/Contents/Resources/ollama"
do
  if [[ -x "${CANDIDATE}" ]]; then
    RESOLVED_OLLAMA_SOURCE="${CANDIDATE:A}"
    SIBLING_LLAMA_SERVER="${RESOLVED_OLLAMA_SOURCE:h}/llama-server"
    if [[ -x "${SIBLING_LLAMA_SERVER}" ]]; then
      if [[ "${RESOLVED_OLLAMA_SOURCE}" == *"/.Trash/"* ]]; then
        echo "Warning: the Ollama installation resolved inside the Trash. This is acceptable only for a local recovery build; reinstall Ollama before producing a distributable binary." >&2
      fi
      OLLAMA_SOURCE="${RESOLVED_OLLAMA_SOURCE}"
      LLAMA_SERVER_SOURCE="${SIBLING_LLAMA_SERVER}"
      break
    fi
  fi
done
if [[ -z "${OLLAMA_SOURCE}" || -z "${LLAMA_SERVER_SOURCE}" ]]; then
  echo "A complete Ollama runtime (ollama plus llama-server) was not found; cannot build the managed local AI engine." >&2
  exit 1
fi
OLLAMA_DESTINATION="${APP_DIRECTORY}/Contents/Resources/Runtime/ollama"
LLAMA_SERVER_DESTINATION="${APP_DIRECTORY}/Contents/Resources/Runtime/llama-server"
cp -L "${OLLAMA_SOURCE}" "${OLLAMA_DESTINATION}"
cp -L "${LLAMA_SERVER_SOURCE}" "${LLAMA_SERVER_DESTINATION}"
chmod 755 "${OLLAMA_DESTINATION}" "${LLAMA_SERVER_DESTINATION}"
codesign --force --sign - "${OLLAMA_DESTINATION}" >/dev/null
codesign --force --sign - "${LLAMA_SERVER_DESTINATION}" >/dev/null
# Ad-hoc signatures normally default to a content hash as their designated requirement. That
# changes on every local build and makes macOS Keychain treat an updated Research Atlas binary as
# a different application. Embed a stable, narrowly scoped identifier requirement so development
# updates retain access to credentials explicitly saved for this bundle.
codesign --force --sign - \
  --requirements '=designated => identifier "app.researchatlas.desktop"' \
  "${APP_DIRECTORY}" >/dev/null
echo "Built ${APP_DIRECTORY}"
