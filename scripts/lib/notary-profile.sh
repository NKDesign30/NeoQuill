#!/usr/bin/env bash
# Shared notary profile resolver for NeoQuill release scripts.

neoquill_resolve_notary_profile() {
  if [ -n "${NEOQUILL_NOTARY_PROFILE:-}" ]; then
    printf '%s\n' "$NEOQUILL_NOTARY_PROFILE"
    return 0
  fi

  if ! command -v xcrun >/dev/null 2>&1; then
    return 1
  fi

  local candidate
  for candidate in neoquill-notary NeoQuill neoquill; do
    if xcrun notarytool history --keychain-profile "$candidate" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

neoquill_notary_profile_help() {
  printf '%s\n' "Setze NEOQUILL_NOTARY_PROFILE oder speichere ein Keychain-Profil 'neoquill-notary' mit xcrun notarytool store-credentials."
}
