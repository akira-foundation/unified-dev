#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../../.."
source Tools/release/codesign-identity.sh

work="$(mktemp -d "${TMPDIR:-/tmp}/unifieddev-codesign-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cp /bin/echo "$work/probe"

name='Developer ID Application: Zoë Gonçalves (ZZZZZZZZZZ)'
failed=0
fail() { print -ru2 -- "NO  $1"; failed=1; }

answer="$(env __CF_USER_TEXT_ENCODING=0x1F5:0x0:0x0 codesign --force --sign "$name" "$work/probe" 2>&1 || true)"
[[ "$answer" == *"Zo√´ Gon√ßalves"* ]] || fail "codesign under Mac Roman no longer mangles the name, so this test proves nothing: $answer"

answer="$(ud_codesign_utf8 && codesign --force --sign "$name" "$work/probe" 2>&1 || true)"
[[ "$answer" == "$name: no identity found"* ]] || fail "the name reached codesign changed: $answer"

listing='  1) 0123456789ABCDEF0123456789ABCDEF01234567 "Developer ID Application: Zoë Gonçalves (ZZZZZZZZZZ)"
     1 valid identities found'
ud_codesign_identity_known "$name" "$listing" || fail "the name was not found in a listing that holds it"
ud_codesign_identity_known 0123456789abcdef0123456789abcdef01234567 "$listing" || fail "the fingerprint was not found"
ud_codesign_identity_known 'Developer ID Application: Zoe Goncalves (ZZZZZZZZZZ)' "$listing" && fail "a name without the accents matched"
ud_codesign_identity_known 'Developer ID Application: Zoë Gonçalves' "$listing" || fail "part of the name, which codesign accepts, was refused"
ud_codesign_identity_known 'Apple Development' "$listing" && fail "a name the keychain does not hold matched"
ud_codesign_identity_known 'valid identities' "$listing" && fail "a word from the listing's footer matched as a name"
ud_codesign_identity_known '0123456789ABCDEF' "$listing" && fail "part of a fingerprint matched as a name"

first_sign="$(grep -n 'codesign "\${SIGN_ARGS' Tools/release/package-app.sh | head -1 | cut -d: -f1)"
utf8="$(grep -n '^ud_codesign_utf8$' Tools/release/package-app.sh | head -1 | cut -d: -f1)"
[[ -n "$utf8" && -n "$first_sign" && "$utf8" -lt "$first_sign" ]] || fail "package-app.sh signs before it asks for UTF-8"
ud_codesign_identity_known 1111111111111111111111111111111111111111 "$listing" && fail "an unknown fingerprint matched"

report="$(ud_codesign_identity_report 'Developer ID Application: Zo√´ Gon√ßalves (ZZZZZZZZZZ)' "$listing")"
[[ "$report" == *"searched for: Developer ID Application: Zo√´ Gon√ßalves (ZZZZZZZZZZ)"* ]] || fail "the report does not name what was searched for"
[[ "$report" == *"e2 88 9a c2 b4"* ]] || fail "the report does not show the searched bytes"
[[ "$report" == *"\"$name\""* ]] || fail "the report does not show what the keychain holds"
[[ "$report" == *"c3 ab"* ]] || fail "the report does not show the keychain's bytes"

(( failed == 0 )) && print -r -- "codesign identity checks passed"
exit $failed
