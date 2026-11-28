#!/usr/bin/env bash
# 공통 함수. 다른 스크립트에서 source 한다.
# 모든 경로는 이 파일의 위치를 기준으로 계산하므로 현재 작업 디렉터리와 무관하게 동작한다.

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"
MYSQL_DIR="$EXAMPLE_DIR/dbms/mysql"
RESULTS_DIR="$EXAMPLE_DIR/reports/test-results"
MYSQL_ENV_FILE="$MYSQL_DIR/.env"
MYSQL_CONTAINER="web-security-example-mysql"
DOCKER_NETWORK="web-security-example"

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { local code="${2:-1}"; printf '[ERROR] %s (exit %s)\n' "$1" "$code" >&2; exit "$code"; }
need() { command -v "$1" >/dev/null 2>&1 || die "'$1' 명령을 찾을 수 없습니다. 설치 후 다시 실행하세요." 127; }

# dbms/mysql/.env 를 KEY=VALUE 형식으로만 읽는다(셸 코드로 실행하지 않음).
load_mysql_env() {
    [ -f "$MYSQL_ENV_FILE" ] || die "$MYSQL_ENV_FILE 이 없습니다. '.env.example'을 복사해 '.env'를 만드세요." 2
    local line key value
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        case "$line" in ''|'#'*) continue ;; esac
        key="${line%%=*}"
        value="${line#*=}"
        [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] || continue
        # 이미 설정된 환경변수가 우선한다.
        if [ -z "${!key+x}" ]; then
            export "$key=$value"
        fi
    done < "$MYSQL_ENV_FILE"
    export MYSQL_PORT="${MYSQL_PORT:-3306}"
}

compose() {
    docker compose --project-directory "$MYSQL_DIR" -f "$MYSQL_DIR/compose.yaml" --env-file "$MYSQL_ENV_FILE" "$@"
}

mysql_health() {
    docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$MYSQL_CONTAINER" 2>/dev/null || echo "missing"
}

# 실행 중인 MySQL 컨테이너가 healthy 상태가 될 때까지 기다린다.
wait_mysql() {
    local timeout="${1:-180}" waited=0 status
    while :; do
        status="$(mysql_health)"
        case "$status" in
            healthy) log "MySQL ready (${waited}s)"; return 0 ;;
            missing) die "MySQL 컨테이너($MYSQL_CONTAINER)가 없습니다. 'mysql.sh up'을 먼저 실행하세요." 3 ;;
            unhealthy) die "MySQL health check 실패. 'docker logs $MYSQL_CONTAINER'로 원인을 확인하세요." 4 ;;
        esac
        [ "$waited" -ge "$timeout" ] && die "MySQL이 ${timeout}초 안에 준비되지 않았습니다 (status=$status)." 5
        sleep 2
        waited=$((waited + 2))
    done
}
