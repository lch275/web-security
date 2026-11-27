#!/usr/bin/env bash
# 공통 MySQL 컨테이너 관리
#   mysql.sh up         컨테이너 시작 후 healthy 대기
#   mysql.sh wait       healthy 대기 (기본 180초, MYSQL_WAIT_SECONDS로 변경)
#   mysql.sh status     상태 출력
#   mysql.sh provision  기존 Volume에 init/ 스크립트(스키마/사용자) 재적용 - 데이터 유지
#   mysql.sh down       컨테이너 종료 - Volume(데이터) 유지
#   mysql.sh reset --yes  컨테이너와 Volume 삭제 후 재생성 (데이터 삭제)
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

need docker
cmd="${1:-}"
[ -n "$cmd" ] || die "사용법: $0 {up|wait|status|provision|down|reset --yes}" 64
load_mysql_env

case "$cmd" in
    up)
        log "MySQL 시작 (127.0.0.1:${MYSQL_PORT})"
        compose up -d --build
        wait_mysql "${MYSQL_WAIT_SECONDS:-180}"
        ;;
    wait)
        wait_mysql "${MYSQL_WAIT_SECONDS:-180}"
        ;;
    status)
        compose ps
        echo "health: $(mysql_health)"
        ;;
    provision)
        wait_mysql 60
        log "init/ 스크립트를 기존 Volume에 다시 적용합니다."
        # Git Bash(MSYS)가 컨테이너 경로를 Windows 경로로 바꾸지 않도록 한다.
        MSYS_NO_PATHCONV=1 docker exec "$MYSQL_CONTAINER" bash /opt/example/provision.sh
        ;;
    down)
        log "MySQL 종료 (Volume 유지)"
        compose down
        ;;
    reset)
        [ "${2:-}" = "--yes" ] || die "데이터가 모두 삭제됩니다. 계속하려면 'mysql.sh reset --yes'로 실행하세요." 64
        log "MySQL 컨테이너와 Volume(web-security-example-mysql-data)을 삭제하고 다시 초기화합니다."
        compose down --volumes
        compose up -d --build
        wait_mysql "${MYSQL_WAIT_SECONDS:-180}"
        ;;
    *)
        die "알 수 없는 명령: $cmd (up|wait|status|provision|down|reset --yes)" 64
        ;;
esac
