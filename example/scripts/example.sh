#!/usr/bin/env bash
# 프레임워크 예제 빌드/테스트/실행
#
#   example.sh build        <fw|all>   호스트 도구로 의존성 설치 + 빌드
#   example.sh test         <fw|all>   호스트에서 통합 테스트 ({fw}_customer_test_db 사용)
#   example.sh run          <fw>       호스트에서 실행 ({fw}_customer_db 사용, Ctrl+C로 종료)
#   example.sh docker-build <fw|all>   runtime/test 이미지 빌드
#   example.sh docker-test  <fw|all>   컨테이너에서 통합 테스트 (DB_HOST=mysql)
#   example.sh docker-run   <fw|all>   컨테이너로 백그라운드 실행 (127.0.0.1:{port})
#   example.sh docker-stop  <fw|all>   실행 중인 예제 컨테이너 종료
#   example.sh smoke        <fw|all>   실행 중인 앱에 HTTP 스모크 테스트
#   example.sh list                    프레임워크/포트 목록
#
# 테스트 결과는 reports/test-results/ 에 로그와 summary.md 로 수집된다.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
source "$SCRIPTS_DIR/frameworks.sh"

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 64; }

cmd="${1:-}"; target="${2:-}"
[ -n "$cmd" ] || usage
if [ "$cmd" = "list" ]; then
    for fw in $FRAMEWORKS; do printf '%-12s port=%s db=%s_customer_db\n' "$fw" "$(fw_port "$fw")" "$(fw_prefix "$fw")"; done
    exit 0
fi
[ -n "$target" ] || usage

if [ "$target" = "all" ]; then
    [ "$cmd" = "run" ] && die "run 은 하나의 프레임워크만 지정할 수 있습니다 (docker-run all 사용 가능)." 64
    targets="$FRAMEWORKS"
else
    fw_meta "$target" >/dev/null || die "알 수 없는 프레임워크: $target (목록: $FRAMEWORKS)" 64
    targets="$target"
fi

# 프레임워크별 DB 접속 환경변수 설정. where=host|docker, purpose=run|test
set_fw_env() {
    local fw="$1" where="$2" purpose="$3" prefix upper password_var
    prefix="$(fw_prefix "$fw")"
    upper="$(echo "$prefix" | tr '[:lower:]' '[:upper:]')"
    password_var="${upper}_DB_PASSWORD"
    [ -n "${!password_var:-}" ] || die "$password_var 가 $MYSQL_ENV_FILE 에 없습니다." 2

    if [ "$where" = "docker" ]; then
        # 컨테이너 내부에서 localhost는 컨테이너 자신이다. 공통 네트워크의 서비스 이름을 사용한다.
        export DB_HOST=mysql DB_PORT=3306
    else
        export DB_HOST=127.0.0.1 DB_PORT="$MYSQL_PORT"
    fi
    if [ "$purpose" = "test" ]; then export DB_NAME="${prefix}_customer_test_db"; else export DB_NAME="${prefix}_customer_db"; fi
    export DB_USERNAME="${prefix}_app" DB_PASSWORD="${!password_var}"
    export DB_READER_USERNAME="${prefix}_reader" DB_READER_PASSWORD="${READER_DB_PASSWORD:-}"
    export APP_PORT="$(fw_port "$fw")"
}

record_result() {
    local fw="$1" mode="$2" code="$3" seconds="$4" status
    [ "$code" -eq 0 ] && status=PASS || status=FAIL
    mkdir -p "$RESULTS_DIR"
    [ -f "$RESULTS_DIR/summary.md" ] || printf '| 시각 | 프레임워크 | 모드 | 결과 | 종료 코드 | 소요(s) | 로그 |\n| --- | --- | --- | --- | --- | --- | --- |\n' > "$RESULTS_DIR/summary.md"
    printf '| %s | %s | %s | %s | %s | %s | %s-%s.log |\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$fw" "$mode" "$status" "$code" "$seconds" "$fw" "$mode" >> "$RESULTS_DIR/summary.md"
    log "$fw [$mode] $status (exit $code, ${seconds}s)"
}

image() { echo "web-security-example/$1:$2"; }

docker_build() {
    local fw="$1"
    docker build -q --target test -t "$(image "$fw" test)" "$EXAMPLE_DIR/$fw" >/dev/null &&
    docker build -q --target runtime -t "$(image "$fw" runtime)" "$EXAMPLE_DIR/$fw" >/dev/null &&
    log "$fw 이미지 빌드 완료: $(image "$fw" runtime), $(image "$fw" test)"
}

# 비밀번호는 명령행 인자에 넣지 않고 환경변수 이름만 전달한다(-e NAME).
docker_env_args=(-e DB_HOST -e DB_PORT -e DB_NAME -e DB_USERNAME -e DB_PASSWORD -e DB_READER_USERNAME -e DB_READER_PASSWORD -e APP_PORT)

run_one() {
    local fw="$1" dir="$EXAMPLE_DIR/$1" started code
    case "$cmd" in
        build)
            log "$fw 빌드"
            (cd "$dir" && fw_host_build "$fw")
            ;;
        test)
            wait_mysql 60
            set_fw_env "$fw" host test
            mkdir -p "$RESULTS_DIR"; started=$SECONDS
            log "$fw 테스트 (host, DB_NAME=$DB_NAME)"
            (cd "$dir" && fw_host_test "$fw") 2>&1 | tee "$RESULTS_DIR/$fw-host.log"
            code=${PIPESTATUS[0]}
            record_result "$fw" host "$code" $((SECONDS - started))
            return "$code"
            ;;
        run)
            wait_mysql 60
            set_fw_env "$fw" host run
            log "$fw 실행: http://127.0.0.1:$APP_PORT (DB_NAME=$DB_NAME)"
            (cd "$dir" && fw_host_run "$fw")
            ;;
        docker-build)
            need docker
            docker_build "$fw"
            ;;
        docker-test)
            need docker; wait_mysql 60
            docker_build "$fw" || return $?
            set_fw_env "$fw" docker test
            mkdir -p "$RESULTS_DIR"; started=$SECONDS
            log "$fw 테스트 (docker, network=$DOCKER_NETWORK, DB_HOST=$DB_HOST)"
            docker run --rm --name "web-security-example-$fw-test" --network "$DOCKER_NETWORK" "${docker_env_args[@]}" \
                "$(image "$fw" test)" 2>&1 | tee "$RESULTS_DIR/$fw-docker.log"
            code=${PIPESTATUS[0]}
            record_result "$fw" docker "$code" $((SECONDS - started))
            return "$code"
            ;;
        docker-run)
            need docker; wait_mysql 60
            docker_build "$fw" || return $?
            set_fw_env "$fw" docker run
            docker rm -f "web-security-example-$fw" >/dev/null 2>&1
            docker run -d --name "web-security-example-$fw" --network "$DOCKER_NETWORK" "${docker_env_args[@]}" \
                -e DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1 \
                -p "127.0.0.1:$APP_PORT:$APP_PORT" "$(image "$fw" runtime)" >/dev/null || return $?
            log "$fw 컨테이너 실행: http://127.0.0.1:$APP_PORT (종료: example.sh docker-stop $fw)"
            ;;
        docker-stop)
            need docker
            docker stop -t 15 "web-security-example-$fw" >/dev/null 2>&1 && docker rm "web-security-example-$fw" >/dev/null \
                && log "$fw 컨테이너 종료" || log "$fw 컨테이너가 실행 중이 아닙니다."
            ;;
        smoke)
            "$SCRIPTS_DIR/smoke.sh" "$fw"
            ;;
        *)
            usage
            ;;
    esac
}

case "$cmd" in
    test|run|docker-test|docker-run) load_mysql_env ;;
esac

failed=""
for fw in $targets; do
    run_one "$fw" || failed="$failed $fw"
done

if [ -n "$failed" ]; then
    die "실패:$failed" 1
fi
