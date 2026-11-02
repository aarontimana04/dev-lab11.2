#!/usr/bin/env bash
set -euo pipefail

SCAN_TYPE="${1:?Falta el tipo de escaneo}"
REPORT_FILE="${2:?Falta la ruta del reporte}"

: "${DEFECTDOJO_URL:?Variable requerida}"
: "${DEFECTDOJO_TOKEN:?Variable requerida}"
: "${DEFECTDOJO_PRODUCT_ID:?Variable requerida}"
: "${CI_COMMIT_REF_NAME:?Variable requerida}"

if [[ ! -s "$REPORT_FILE" ]]; then
  echo "Reporte inexistente o vacío: $REPORT_FILE"
  exit 1
fi

BASE_URL="${DEFECTDOJO_URL%/}"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
UPLOAD_FILE="$REPORT_FILE"

if [[ "$SCAN_TYPE" == "Trufflehog Scan" ]]; then
  jq -c 'select(has("SourceMetadata"))' "$REPORT_FILE" \
    > "$WORK_DIR/trufflehog.json"
  if [[ ! -s "$WORK_DIR/trufflehog.json" ]]; then
    echo "TruffleHog: no hay hallazgos importables"
    exit 1
  fi
  UPLOAD_FILE="$WORK_DIR/trufflehog.json"
fi

PRODUCT_NAME=$(curl --fail --silent --show-error \
  --connect-timeout 15 --max-time 60 \
  -H "Authorization: Token $DEFECTDOJO_TOKEN" \
  -H "ngrok-skip-browser-warning: true" \
  "$BASE_URL/api/v2/products/$DEFECTDOJO_PRODUCT_ID/" \
  | jq -er '.name')

HTTP_STATUS=$(curl --silent --show-error \
  --connect-timeout 15 --max-time 180 \
  -o "$WORK_DIR/response.json" -w '%{http_code}' \
  -X POST "$BASE_URL/api/v2/reimport-scan/" \
  -H "Authorization: Token $DEFECTDOJO_TOKEN" \
  -H "ngrok-skip-browser-warning: true" \
  -F "scan_type=$SCAN_TYPE" \
  -F "file=@$UPLOAD_FILE" \
  -F "product_name=$PRODUCT_NAME" \
  -F "engagement_name=CI - $CI_COMMIT_REF_NAME" \
  -F "test_title=$SCAN_TYPE" \
  -F "auto_create_context=true" \
  -F "active=true" \
  -F "verified=false" \
  -F "close_old_findings=true" \
  -F "close_old_findings_product_scope=false" \
  -F "version=$CI_PIPELINE_ID" \
  -F "build_id=$CI_PIPELINE_ID" \
  -F "commit_hash=$CI_COMMIT_SHORT_SHA" \
  -F "branch_tag=$CI_COMMIT_REF_NAME")

if [[ "$HTTP_STATUS" == "201" ]]; then
  echo "OK importado (HTTP 201) — $SCAN_TYPE"
else
  echo "Error al importar $SCAN_TYPE (HTTP $HTTP_STATUS)"
  cat "$WORK_DIR/response.json"
  exit 1
fi
