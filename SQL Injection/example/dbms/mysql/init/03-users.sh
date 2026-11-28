#!/bin/bash
# 03-users.sh
# 프레임워크별 애플리케이션 계정과 SELECT 전용 계정을 생성한다.
#
#   {fw}_app    : {fw}_customer_db / {fw}_customer_test_db 의 customers 테이블에 대한 DML만 허용 (DDL 불가)
#   {fw}_reader : 같은 테이블에 대한 SELECT만 허용 (문서의 "조회 계정" 권한)
#
# - 비밀번호는 컨테이너 환경변수(.env)에서만 읽는다. 이 파일에는 인증정보가 없다.
# - MySQL 엔트리포인트가 최초 Volume 초기화 시 source 하거나, provision.sh 가 기존 Volume에 다시 실행한다.
#   source 되는 경우를 고려하여 exit 대신 return/실패 명령을 사용한다.
# - CREATE USER IF NOT EXISTS + ALTER USER 로 멱등성을 보장하고 비밀번호 변경도 반영한다.

example_users_main() {
    local frameworks="spring_boot nestjs express fastapi django"
    local sql="" fw var password

    # SQL 문자열에 안전하게 넣을 수 있는 문자만 허용한다(따옴표, 역슬래시, 공백 금지).
    example_validate_password() {
        case "$2" in
            "" ) echo "[03-users] $1 이(가) 비어 있습니다." >&2; return 1 ;;
            *[!A-Za-z0-9_.@%+=:,-]* ) echo "[03-users] $1 에 허용되지 않는 문자가 있습니다. (허용: 영문, 숫자, _.@%+=:,-)" >&2; return 1 ;;
        esac
        if [ "${#2}" -lt 12 ]; then
            echo "[03-users] $1 은(는) 12자 이상이어야 합니다." >&2
            return 1
        fi
    }

    example_validate_password READER_DB_PASSWORD "${READER_DB_PASSWORD:-}" || return 1

    for fw in $frameworks; do
        var="$(echo "$fw" | tr '[:lower:]' '[:upper:]')_DB_PASSWORD"
        password="${!var:-}"
        example_validate_password "$var" "$password" || return 1

        sql+="CREATE USER IF NOT EXISTS '${fw}_app'@'%' IDENTIFIED BY '${password}';
ALTER USER '${fw}_app'@'%' IDENTIFIED BY '${password}';
GRANT SELECT, INSERT, UPDATE, DELETE ON ${fw}_customer_db.customers TO '${fw}_app'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON ${fw}_customer_test_db.customers TO '${fw}_app'@'%';
CREATE USER IF NOT EXISTS '${fw}_reader'@'%' IDENTIFIED BY '${READER_DB_PASSWORD}';
ALTER USER '${fw}_reader'@'%' IDENTIFIED BY '${READER_DB_PASSWORD}';
GRANT SELECT ON ${fw}_customer_db.customers TO '${fw}_reader'@'%';
GRANT SELECT ON ${fw}_customer_test_db.customers TO '${fw}_reader'@'%';
"
    done

    # 비밀번호가 프로세스 인자에 노출되지 않도록 MYSQL_PWD와 표준입력을 사용한다.
    printf '%s' "$sql" | MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql --protocol=socket -uroot || return 1
    echo "[03-users] 계정 생성/갱신 완료: ${frameworks}"
}

example_users_main
