#!/bin/bash
# provision.sh (컨테이너 내부에서 실행)
# 이미 초기화된 Volume에 init/ 스크립트를 다시 적용한다.
# init/ 의 모든 스크립트는 멱등적으로 작성되어 있으므로 기존 데이터는 유지된다.
# 호출: example/scripts/mysql.sh provision  (또는 mysql.ps1 provision)
set -eo pipefail

for f in /docker-entrypoint-initdb.d/*; do
    case "$f" in
        *.sql)
            echo "[provision] $f"
            MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql --protocol=socket -uroot < "$f"
            ;;
        *.sh)
            echo "[provision] $f"
            # shellcheck disable=SC1090
            . "$f"
            ;;
    esac
done
echo "[provision] 완료"
