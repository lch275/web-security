"""실행: python -m app  (APP_HOST, APP_PORT 환경변수 사용)"""

import logging
import os

import uvicorn

from .main import create_app


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s - %(message)s")
    uvicorn.run(
        create_app(),
        host=os.environ.get("APP_HOST", "127.0.0.1"),
        port=int(os.environ.get("APP_PORT", "8084")),
        # uvicorn 접근 로그는 쿼리 문자열을 포함하므로 끄고, 앱 미들웨어 로그를 사용한다.
        access_log=False,
        timeout_graceful_shutdown=10,
    )


if __name__ == "__main__":
    main()
