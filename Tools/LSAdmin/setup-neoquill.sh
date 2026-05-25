#!/usr/bin/env bash
# NeoQuill Lemon Squeezy Setup (Sync + Configure)
#
# LS erlaubt kein POST /v1/products oder /v1/variants — Products + Variants
# müssen im UI angelegt werden. Dieses Script:
#
#   1. liest existierende Products + Variants aus dem Store
#   2. matcht Variants gegen erwartete Namen
#   3. schreibt state.json mit allen IDs
#   4. baut Webhooks + Discounts (kommt in slice 3)
#
# Token kommt aus 1Password (op://Automation/lemonsqueezy-api-neon-dev/credential).
#
# Usage:
#   ./setup-neoquill.sh                # vollständiger Sync
#   ./setup-neoquill.sh --check        # zeigt nur was fehlt, schreibt nichts

set -euo pipefail
cd "$(dirname "$0")"

CHECK_ONLY=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) CHECK_ONLY=1; shift ;;
    --help|-h)
      sed -n '1,/^set -euo/p' "$0" | grep '^#'
      exit 0
      ;;
    *) echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
done

OP_ITEM="op://Automation/lemonsqueezy-api-neon-dev/credential"
LS_TOKEN=$(op read "$OP_ITEM" 2>/dev/null || true)
if [ -z "$LS_TOKEN" ]; then
  echo "✗ Kein LS-Token im 1Password-Eintrag '$OP_ITEM'" >&2
  exit 1
fi

API="https://api.lemonsqueezy.com/v1"
STORE_ID="386920"
STATE_FILE="state.json"
PRODUCT_NAME="NeoQuill"

# Erwartete Variant-Namen + License-Aktivierungen (zur Plausibilitätsprüfung).
EXPECTED_VARIANTS='[
  { "match": "Lifetime", "expected_price": 8900, "activations": 1 },
  { "match": "Major Upgrade", "expected_price": 3900, "activations": 1 },
  { "match": "5 seats", "expected_price": 34900, "activations": 5 },
  { "match": "10 seats", "expected_price": 59900, "activations": 10 }
]'

command -v jq >/dev/null 2>&1 || { echo "✗ jq fehlt" >&2; exit 1; }

ls_call() {
  local method="$1" path="$2" body="${3:-}"
  local args=(-sS --globoff -w "\nHTTP_STATUS:%{http_code}"
    -H "Accept: application/vnd.api+json"
    -H "Content-Type: application/vnd.api+json"
    -H "Authorization: Bearer $LS_TOKEN"
    -X "$method")
  if [ -n "$body" ]; then args+=(-d "$body"); fi
  curl "${args[@]}" "$API$path"
}
ls_status() { echo "$1" | grep -oE "HTTP_STATUS:[0-9]+" | cut -d: -f2; }
ls_body()   { echo "$1" | sed '/HTTP_STATUS/d'; }

# ---------- 1) Account + Store ----------
echo "==> Account"
RESP=$(ls_call GET "/users/me"); [ "$(ls_status "$RESP")" = "200" ] || { echo "✗ /users/me fehlgeschlagen" >&2; exit 1; }
echo "   ✓ $(ls_body "$RESP" | jq -r '.data.attributes.name') <$(ls_body "$RESP" | jq -r '.data.attributes.email')>"

echo "==> Store $STORE_ID"
RESP=$(ls_call GET "/stores/$STORE_ID"); [ "$(ls_status "$RESP")" = "200" ] || { echo "✗ Store nicht erreichbar" >&2; exit 1; }
echo "   ✓ $(ls_body "$RESP" | jq -r '.data.attributes.name') (plan=$(ls_body "$RESP" | jq -r '.data.attributes.plan'))"

# ---------- 2) Product finden ----------
echo "==> Product '$PRODUCT_NAME'"
RESP=$(ls_call GET "/products?filter[store_id]=$STORE_ID&page[size]=100")
if [ "$(ls_status "$RESP")" != "200" ]; then
  echo "✗ GET /products fehlgeschlagen" >&2
  ls_body "$RESP" | jq . >&2
  exit 1
fi
PRODUCT_ID=$(ls_body "$RESP" | jq -r --arg n "$PRODUCT_NAME" \
  '.data[] | select(.attributes.name == $n) | .id' | head -1)

if [ -z "$PRODUCT_ID" ] || [ "$PRODUCT_ID" = "null" ]; then
  cat >&2 <<MISSING

✗ Product '$PRODUCT_NAME' existiert nicht im Store.

LS erlaubt das Anlegen von Products NICHT via API. Bitte im UI machen:
   1. https://app.lemonsqueezy.com/products/new
   2. Name: NeoQuill
   3. Status: Draft
   4. Save
   5. Dann Variants im Product-Editor anlegen (siehe README oder Niko-Chat)
   6. Dieses Script erneut starten.

MISSING
  exit 1
fi
echo "   ✓ id=$PRODUCT_ID"

# ---------- 3) Variants einlesen ----------
echo "==> Variants"
RESP=$(ls_call GET "/variants?filter[product_id]=$PRODUCT_ID&page[size]=100")
if [ "$(ls_status "$RESP")" != "200" ]; then
  echo "✗ GET /variants fehlgeschlagen" >&2
  ls_body "$RESP" | jq . >&2
  exit 1
fi
VARIANTS_RAW=$(ls_body "$RESP")
VARIANT_COUNT=$(echo "$VARIANTS_RAW" | jq '.data | length')
echo "   gefunden: $VARIANT_COUNT"

# Per erwartetem Pattern matchen
MATCHED_VARIANTS='[]'
MISSING_VARIANTS='[]'
while IFS= read -r expected; do
  match=$(echo "$expected" | jq -r '.match')
  price=$(echo "$expected" | jq -r '.expected_price')
  activations=$(echo "$expected" | jq -r '.activations')

  found=$(echo "$VARIANTS_RAW" | jq --arg m "$match" '[
    .data[]
    | select(.attributes.name | test($m; "i"))
  ] | .[0]')

  if [ "$found" = "null" ] || [ -z "$found" ]; then
    MISSING_VARIANTS=$(echo "$MISSING_VARIANTS" | jq --argjson e "$expected" '. + [$e]')
    echo "   ⚠ fehlt: $match (Preis $price ct, $activations Aktivierungen)"
    continue
  fi

  vid=$(echo "$found" | jq -r '.id')
  vname=$(echo "$found" | jq -r '.attributes.name')
  vprice=$(echo "$found" | jq -r '.attributes.price')
  vlic=$(echo "$found" | jq -r '.attributes.has_license_keys')
  vlicact=$(echo "$found" | jq -r '.attributes.license_activation_limit')
  vstatus=$(echo "$found" | jq -r '.attributes.status')

  warn=""
  [ "$vprice" = "$price" ] || warn="$warn price=${vprice}(want $price)"
  [ "$vlic" = "true" ] || warn="$warn licenseKeys=off"
  if [ "$vlic" = "true" ] && [ "$vlicact" != "$activations" ]; then
    warn="$warn activations=${vlicact}(want $activations)"
  fi
  if [ -n "$warn" ]; then
    echo "   ⚠ $vname (id=$vid, $vstatus):$warn"
  else
    echo "   ✓ $vname (id=$vid, $vstatus, $vprice ct, $vlicact act)"
  fi

  MATCHED_VARIANTS=$(echo "$MATCHED_VARIANTS" | jq \
    --argjson e "$expected" \
    --arg id "$vid" \
    --arg name "$vname" \
    --arg price "$vprice" \
    --arg lic "$vlic" \
    --arg licact "$vlicact" \
    --arg status "$vstatus" \
    '. + [{
      slot: $e.match,
      id: $id,
      name: $name,
      price_cents: ($price | tonumber),
      has_license_keys: ($lic == "true"),
      activation_limit: ($licact | tonumber? // null),
      status: $status
    }]')
done < <(echo "$EXPECTED_VARIANTS" | jq -c '.[]')

# ---------- 4) State speichern ----------
if [ "$CHECK_ONLY" = "1" ]; then
  echo ""
  echo "(check-only — state.json nicht geändert)"
  exit 0
fi

jq -n \
  --arg sid "$STORE_ID" \
  --arg pid "$PRODUCT_ID" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson matched "$MATCHED_VARIANTS" \
  --argjson missing "$MISSING_VARIANTS" \
  '{
    store_id: $sid,
    product: { id: $pid, name: "NeoQuill" },
    variants: $matched,
    missing_variants: $missing,
    last_synced_at: $ts
  }' > "$STATE_FILE"

echo ""
MISSING_COUNT=$(echo "$MISSING_VARIANTS" | jq 'length')
if [ "$MISSING_COUNT" -gt 0 ]; then
  echo "⚠ $MISSING_COUNT Variant(s) fehlen noch. State trotzdem geschrieben."
  exit 2
fi
echo "✓ Slice 1 fertig: Product + alle 4 Variants in state.json"
echo "  Nächste Slices: Webhooks (slice 3), Discounts (slice 3)"
