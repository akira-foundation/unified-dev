#!/bin/zsh
# Sourced by package-app.sh. codesign reads its arguments in the encoding named by
# __CF_USER_TEXT_ENCODING, which is Mac Roman unless a UTF-8 one is exported, so an
# identity name with an accent in it reaches the keychain search as something else.

ud_codesign_utf8() {
  export __CF_USER_TEXT_ENCODING="0x$(printf '%X' "$(id -u)"):0x8000100:0x8000100"
}

ud_codesign_identities() {
  security find-identity -p codesigning 2>/dev/null
}

ud_codesign_identity_known() {
  local wanted=$1 listing=$2
  if [[ "$wanted" =~ '^[0-9A-Fa-f]{40}$' ]]; then
    print -r -- "$listing" | grep -qiF " ${wanted} "
  else
    print -r -- "$listing" | grep -qF "\"${wanted}\""
  fi
}

ud_codesign_bytes() {
  print -rn -- "$1" | od -An -tx1 | tr -s ' \n' ' ' | sed 's/^ //; s/ $//'
}

ud_codesign_identity_report() {
  local wanted=$1 listing=$2 line name
  print -r -- "No signing identity matches UD_CODESIGN_IDENTITY."
  print -r -- "  searched for: $wanted"
  print -r -- "         bytes: $(ud_codesign_bytes "$wanted")"
  print -r -- "The keychain holds:"
  while IFS= read -r line; do
    [[ "$line" == *'"'*'"'* ]] || continue
    name=${${line#*\"}%\"*}
    print -r -- "  $line"
    print -r -- "         bytes: $(ud_codesign_bytes "$name")"
  done <<<"$listing"
  print -r -- "A name outside ASCII is the usual cause. The SHA-1 fingerprint, the forty hex"
  print -r -- "characters at the start of the line, matches whatever the name is."
}
