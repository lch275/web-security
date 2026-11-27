#!/usr/bin/env bash
# 실행 중인 예제 앱에 대한 HTTP 스모크 테스트 (데모 DB의 시드 데이터 기준)
#   smoke.sh <fw> [base-url]   기본 base-url: http://127.0.0.1:{port}
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
source "$SCRIPTS_DIR/frameworks.sh"
need curl

fw="${1:-}"
fw_meta "$fw" >/dev/null 2>&1 || die "사용법: $0 <fw> [base-url]  (fw: $FRAMEWORKS)" 64
base="${2:-http://127.0.0.1:$(fw_port "$fw")}"
param="$(fw_param "$fw")"
invalid_status=400; [ "$fw" = "fastapi" ] && invalid_status=422
failures=0

check() {
    local name="$1" expected_status="$2" expected_body="$3"; shift 3
    local out status body
    out="$(curl -s -m 10 -w '\n%{http_code}' "$@")" || { echo "FAIL $name (연결 실패)"; failures=$((failures + 1)); return; }
    status="${out##*$'\n'}"; body="${out%$'\n'*}"
    if [ "$status" = "$expected_status" ] && [[ "$body" =~ $expected_body ]]; then
        echo "PASS $name -> $status $body"
    else
        echo "FAIL $name -> $status $body (expected $expected_status /$expected_body/)"
        failures=$((failures + 1))
    fi
}

echo "== $fw smoke test: $base"
check "health"              200 '"status": ?"UP"'  "$base/health"
check "search O'Connor"     200 '^\["?[0-9]+"?\]$' -G "$base/customers/search" --data-urlencode "$param=O'Connor"
check "search injection"    200 '^\[\]$'           -G "$base/customers/search" --data-urlencode "$param=' OR '1'='1"
check "search drop payload" 200 '^\[\]$'           -G "$base/customers/search" --data-urlencode "$param=x'; DROP TABLE customers; --"
check "contains %"          200 '^\["?[0-9]+"?\]$' -G "$base/customers/contains" --data-urlencode "keyword=%"
check "sorted invalid"      "$invalid_status" '.'  "$base/customers/sorted?sort=id"
check "search missing"      "$invalid_status" '.'  "$base/customers/search"
check "table intact"        200 '^\[.+\]$'         "$base/customers/sorted?sort=name"

[ "$failures" -eq 0 ] || die "$fw smoke test 실패 ${failures}건" 1
echo "== $fw smoke test PASS"
