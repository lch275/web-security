"""example/dbms/mysql 이 미리 만든 테스트 DB를 그대로 사용하는 테스트 러너.

애플리케이션 계정에는 CREATE/DROP 권한이 없으므로 Django가 test_* DB를 만들지 않도록 한다.
각 테스트는 django.test.TestCase 의 트랜잭션 롤백으로 서로 격리된다.
"""

from django.conf import settings
from django.test.runner import DiscoverRunner


class ExistingDatabaseTestRunner(DiscoverRunner):
    def setup_databases(self, **kwargs):
        name = settings.DATABASES["default"]["NAME"]
        if not name.endswith("_test_db"):
            raise RuntimeError(f"테스트는 *_test_db 에서만 실행합니다. 현재 DB_NAME={name}")
        return []

    def teardown_databases(self, old_config, **kwargs):
        pass
