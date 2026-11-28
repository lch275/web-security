#!/usr/bin/env bash
# 프레임워크 등록 정보. 신규 프레임워크는 이 파일의 FRAMEWORKS, fw_meta, fw_host_* 에만 추가한다.
# (PowerShell은 frameworks.ps1 에 같은 정보를 등록한다)

FRAMEWORKS="spring-boot nestjs express fastapi django"

# fw_meta <fw> → "포트 DB접두어 검색파라미터"
fw_meta() {
    case "$1" in
        spring-boot) echo "8081 spring_boot lastName" ;;
        nestjs)      echo "8082 nestjs lastName" ;;
        express)     echo "8083 express lastName" ;;
        fastapi)     echo "8084 fastapi last_name" ;;
        django)      echo "8085 django last_name" ;;
        *) return 1 ;;
    esac
}

fw_port()   { set -- $(fw_meta "$1"); echo "$1"; }
fw_prefix() { set -- $(fw_meta "$1"); echo "$2"; }
fw_param()  { set -- $(fw_meta "$1"); echo "$3"; }

# --- 호스트 도구 탐색 ---------------------------------------------------------

# JDK 21 이상을 찾는다: JAVA_HOME → ~/.jdks → /usr/lib/jvm → PATH
find_java_home() {
    local candidate version
    for candidate in "${JAVA_HOME:-}" "$HOME"/.jdks/*21* "$HOME"/.jdks/*2[2-9]* /usr/lib/jvm/*21* /usr/lib/jvm/*2[2-9]* \
                     /Library/Java/JavaVirtualMachines/*/Contents/Home; do
        [ -n "$candidate" ] && [ -x "$candidate/bin/java" -o -x "$candidate/bin/java.exe" ] || continue
        version="$("$candidate/bin/java" -version 2>&1 | head -1 | sed -E 's/.*version "([0-9]+).*/\1/')"
        if [ "${version:-0}" -ge 21 ] 2>/dev/null; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

find_python() {
    local py
    for py in "${PYTHON:-}" python3 python; do
        [ -n "$py" ] && command -v "$py" >/dev/null 2>&1 && "$py" -c 'import sys; sys.exit(sys.version_info < (3, 12))' 2>/dev/null \
            && { echo "$py"; return 0; }
    done
    return 1
}

venv_python() {
    if [ -x "$1/.venv/bin/python" ]; then echo "$1/.venv/bin/python"; else echo "$1/.venv/Scripts/python.exe"; fi
}

ensure_venv() {
    local dir="$1" requirements="$2" py
    if [ ! -d "$dir/.venv" ]; then
        py="$(find_python)" || die "Python 3.12 이상을 찾을 수 없습니다 (PYTHON 환경변수로 지정 가능)." 127
        log "가상환경 생성: $dir/.venv ($py)"
        "$py" -m venv "$dir/.venv"
    fi
    "$(venv_python "$dir")" -m pip install --disable-pip-version-check -q -r "$dir/$requirements" -c "$dir/constraints.txt"
}

ensure_node_modules() {
    need npm
    if [ ! -d "$1/node_modules" ]; then
        (cd "$1" && npm ci --no-audit --no-fund)
    fi
}

with_java() {
    local java_home
    java_home="$(find_java_home)" || die "JDK 21 이상이 필요합니다. JAVA_HOME을 설정하거나 'example.sh docker-test spring-boot'를 사용하세요." 127
    JAVA_HOME="$java_home" PATH="$java_home/bin:$PATH" "$@"
}

# --- 호스트 빌드/테스트/실행 ----------------------------------------------------
# 각 함수는 프레임워크 디렉터리에서 실행된다.

fw_host_build() {
    case "$1" in
        spring-boot) with_java ./mvnw -B -q -DskipTests package ;;
        nestjs)      need npm; npm ci --no-audit --no-fund && npm run build ;;
        express)     need npm; npm ci --no-audit --no-fund && npm run build ;;
        fastapi)     ensure_venv . requirements-dev.txt && "$(venv_python .)" -m compileall -q app tests ;;
        django)      ensure_venv . requirements-dev.txt && "$(venv_python .)" manage.py check ;;
    esac
}

fw_host_test() {
    case "$1" in
        spring-boot) with_java ./mvnw -B test -Dtest.db.name="$DB_NAME" ;;
        nestjs)      ensure_node_modules . && npm test ;;
        express)     ensure_node_modules . && npm test ;;
        fastapi)     ensure_venv . requirements-dev.txt && "$(venv_python .)" -m pytest -p no:cacheprovider ;;
        django)      ensure_venv . requirements-dev.txt && "$(venv_python .)" manage.py test -v 2 ;;
    esac
}

fw_host_run() {
    case "$1" in
        spring-boot) [ -f target/spring-boot-sql-injection-example-1.0.0.jar ] || fw_host_build "$1"
                     with_java java -jar target/spring-boot-sql-injection-example-1.0.0.jar ;;
        nestjs)      [ -f dist/main.js ] || fw_host_build "$1"; exec node dist/main.js ;;
        express)     ensure_node_modules . && exec node src/server.js ;;
        fastapi)     ensure_venv . requirements.txt && exec "$(venv_python .)" -m app ;;
        django)      ensure_venv . requirements.txt && exec "$(venv_python .)" manage.py runserver "127.0.0.1:$APP_PORT" --noreload ;;
    esac
}
