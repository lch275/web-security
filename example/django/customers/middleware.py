import logging
import time

from django.db import DatabaseError, InterfaceError, OperationalError
from django.http import JsonResponse

logger = logging.getLogger("customers.request")

# 연결 실패/장애로 분류하는 MySQL 오류 번호
UNAVAILABLE_ERRNOS = {1040, 1045, 1129, 2002, 2003, 2005, 2006, 2013, 2055, 3024}


class RequestLogMiddleware:
    """요청 로그에는 쿼리 문자열과 본문을 남기지 않는다."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        started = time.perf_counter()
        response = self.get_response(request)
        logger.info("%s %s %s %.1fms", request.method, request.path, response.status_code,
                    (time.perf_counter() - started) * 1000)
        return response


class DatabaseErrorMiddleware:
    """DB 오류를 상세 정보 없이 503/500 응답으로 변환한다."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        return self.get_response(request)

    def process_exception(self, request, exception):
        if not isinstance(exception, DatabaseError):
            return None
        errno = exception.args[0] if exception.args and isinstance(exception.args[0], int) else None
        if isinstance(exception, InterfaceError) or (isinstance(exception, OperationalError) and errno in UNAVAILABLE_ERRNOS):
            logger.error("database unavailable: errno=%s", errno)
            return JsonResponse({"errors": {"__all__": [{"message": "데이터베이스를 사용할 수 없습니다."}]}}, status=503)
        logger.error("database error: %s errno=%s", type(exception).__name__, errno)
        return JsonResponse({"errors": {"__all__": [{"message": "요청을 처리하지 못했습니다."}]}}, status=500)
