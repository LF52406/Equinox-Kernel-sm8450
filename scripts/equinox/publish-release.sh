#!/usr/bin/env bash
set -euo pipefail

REPO="${EQUINOX_GITHUB_REPO:-LF52406/Equinox-Kernel-sm8450}"
TARGET="${EQUINOX_RELEASE_TARGET:-equinox}"
TAG="${1:-}"

if [[ -z "$TAG" ]]; then
  echo "Usage: $0 <tag>"
  echo "Examples:"
  echo "  $0 5.10.269-test1"
  echo "  $0 5.10.269-r2"
  echo "  $0 5.10.270"
  exit 2
fi

if [[ "$TAG" =~ ^([0-9]+\.[0-9]+\.[0-9]+)-test([0-9]+)$ ]]; then
  VERSION="${BASH_REMATCH[1]}"
  TEST_NO="${BASH_REMATCH[2]}"
  if [[ "$TEST_NO" == "1" ]]; then
    TITLE="Equinox Kernel ${VERSION} - Test Build"
  else
    TITLE="Equinox Kernel ${VERSION} - Test Build ${TEST_NO}"
  fi
  PRERELEASE=(--prerelease)
elif [[ "$TAG" =~ ^([0-9]+\.[0-9]+\.[0-9]+)-r([0-9]+)$ ]]; then
  VERSION="${BASH_REMATCH[1]}"
  REVISION="${BASH_REMATCH[2]}"
  TITLE="Equinox Kernel ${VERSION} - Revision ${REVISION}"
  PRERELEASE=()
elif [[ "$TAG" =~ ^([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
  VERSION="${BASH_REMATCH[1]}"
  TITLE="Equinox Kernel ${VERSION}"
  PRERELEASE=()
else
  echo "Unsupported tag format: $TAG" >&2
  echo "Expected: 5.10.269-test1, 5.10.269-r2 or 5.10.270" >&2
  exit 2
fi

ROOT="$(git rev-parse --show-toplevel)"
ZIP="${EQUINOX_ZIP:-$HOME/dist/equinox-production/Equinox-${VERSION}-mondrian.zip}"
NOTES="${EQUINOX_RELEASE_NOTES:-$ROOT/scripts/equinox/release-notes/${TAG}.md}"
SHA_FILE="${ZIP}.sha256"

for tool in gh unzip sha256sum git; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing required tool: $tool" >&2
    exit 1
  }
done

[[ -f "$ZIP" ]] || {
  echo "Production ZIP not found: $ZIP" >&2
  exit 1
}

[[ -f "$NOTES" ]] || {
  echo "Release notes not found: $NOTES" >&2
  exit 1
}

echo "[1/6] Verifying ZIP integrity"
unzip -tq "$ZIP" >/dev/null

META="$(unzip -p "$ZIP" version)"
grep -Fxq "Kernel: ${VERSION}-Equinox" <<<"$META" || {
  echo "Kernel version inside ZIP does not match ${VERSION}-Equinox" >&2
  exit 1
}
grep -Fxq "Device: POCO F5 Pro / Redmi K60" <<<"$META" || {
  echo "Unexpected device metadata in ZIP" >&2
  exit 1
}
grep -Fxq "Codename: mondrian" <<<"$META" || {
  echo "Unexpected codename metadata in ZIP" >&2
  exit 1
}

SOURCE_COMMIT="$(sed -n 's/^Source commit: //p' <<<"$META" | head -n1)"
if [[ -n "$SOURCE_COMMIT" ]] && git cat-file -e "${SOURCE_COMMIT}^{commit}" 2>/dev/null; then
  git merge-base --is-ancestor "$SOURCE_COMMIT" HEAD || {
    echo "ZIP source commit ${SOURCE_COMMIT} is not an ancestor of the current checkout" >&2
    exit 1
  }
fi

echo "[2/6] Calculating SHA256"
SHA256="$(sha256sum "$ZIP" | awk '{print $1}')"
printf '%s  %s\n' "$SHA256" "$(basename "$ZIP")" > "$SHA_FILE"

echo "[3/6] Checking GitHub authentication"
gh auth status >/dev/null

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "Release already exists: $TAG" >&2
  exit 1
fi

TMP_NOTES="$(mktemp)"
trap 'rm -f "$TMP_NOTES"' EXIT
cat "$NOTES" > "$TMP_NOTES"
printf '\n## Download\n\n**%s**\n\nSHA256: `%s`\n\n> Download the flashable Equinox ZIP from **Assets**. GitHub-generated source archives are not flashable kernel packages.\n' \
  "$(basename "$ZIP")" "$SHA256" >> "$TMP_NOTES"

echo "[4/6] Creating GitHub Release"
gh release create "$TAG" \
  "$ZIP" \
  "$SHA_FILE" \
  --repo "$REPO" \
  --target "$TARGET" \
  --title "$TITLE" \
  --notes-file "$TMP_NOTES" \
  "${PRERELEASE[@]}"

echo "[5/6] Verifying uploaded release"
gh release view "$TAG" --repo "$REPO" --json tagName,name,isPrerelease,url

echo "[6/6] Done"
echo "Release : $TITLE"
echo "Tag     : $TAG"
echo "ZIP     : $ZIP"
echo "SHA256  : $SHA256"
