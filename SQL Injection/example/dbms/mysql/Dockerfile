# MySQL 8.4 + 예제 서버 설정
# Windows/macOS의 바인드 마운트는 파일을 world-writable(0777)로 노출하는 경우가 있고,
# MySQL은 world-writable 설정 파일을 무시한다. 그래서 설정 파일만 0644 권한으로 이미지에 포함한다.
FROM mysql:8.4.13

COPY --chmod=0644 conf/my.cnf /etc/mysql/conf.d/example.cnf
