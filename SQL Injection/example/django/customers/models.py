from django.db import models
from django.db.models.functions import Now


class Customer(models.Model):
    """Django.md의 모델. 테이블은 example/dbms/mysql/init 에서 생성한다(managed = False)."""

    id = models.BigAutoField(primary_key=True)
    last_name = models.CharField(max_length=100)
    # 문서 모델에 db_default를 더해 INSERT 시 DB 기본값(CURRENT_TIMESTAMP)을 사용한다.
    created_at = models.DateTimeField(db_default=Now())

    class Meta:
        db_table = "customers"
        managed = False

    def to_dict(self) -> dict:
        return {"id": self.id, "last_name": self.last_name, "created_at": self.created_at.isoformat()}
