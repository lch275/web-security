# Django에서 MySQL을 사용할 때의 SQL Injection 방어

## MySQL 예제 환경

[Java와 Spring 예제](Spring.md#mysql-예제-환경)와 같은 MySQL 8.4의 `customer_db.customers` 테이블을 사용한다. Django 5.2와 `mysqlclient`를 설치하고, `DATABASES['default']`의 `ENGINE`을 `django.db.backends.mysql`, `NAME`을 `customer_db`로 설정한다. 계정 정보는 환경 변수에서 읽는다. [Django MySQL 설정](https://docs.djangoproject.com/en/5.2/ref/databases/#mysql-notes)

## 요청값 검증과 ORM 조회

`forms.CharField`로 `last_name`의 필수 여부와 길이를 검사한다. 기본 동작에 따라 앞뒤 공백을 제거한다. `QuerySet.filter()`에는 검증을 거친 값을 전달한다. 예제의 모델은 이미 생성된 `customers` 테이블에 연결하며 `managed = False`로 테이블 관리를 Django 마이그레이션에서 제외한다. [Django 폼 필드](https://docs.djangoproject.com/en/5.2/ref/forms/fields/#charfield) · [Django QuerySet](https://docs.djangoproject.com/en/5.2/ref/models/querysets/)

```python
# models.py
from django.db import models


class Customer(models.Model):
    id = models.BigAutoField(primary_key=True)
    last_name = models.CharField(max_length=100)
    created_at = models.DateTimeField()

    class Meta:
        db_table = "customers"
        managed = False
```

```python
# views.py
from django import forms
from django.http import JsonResponse
from django.views.decorators.http import require_GET

from .models import Customer


class CustomerSearchForm(forms.Form):
    last_name = forms.CharField(max_length=100)


@require_GET
def search_customers(request):
    form = CustomerSearchForm(request.GET)
    if not form.is_valid():
        return JsonResponse({"errors": form.errors.get_json_data()}, status=400)

    ids = Customer.objects.filter(
        last_name=form.cleaned_data["last_name"],
    ).values_list("id", flat=True)
    return JsonResponse(list(ids), safe=False)
```

`urls.py`에 `path("customers/search", search_customers)`를 등록한다. `/customers/search?last_name=O%27Connor`에서 작은따옴표는 성의 일부로 처리된다. 세미콜론이나 주석 표기가 포함되어도 ORM이 전체를 검색값으로 전달하므로 조회 조건은 그대로 적용된다. [Django의 SQL Injection 방어](https://docs.djangoproject.com/en/5.2/topics/security/#sql-injection-protection)

## 직접 작성한 SQL의 값 바인딩

직접 작성한 SQL에서는 `cursor.execute(sql, params)`의 두 번째 인자로 값을 전달한다. 자리표시자 `%s`는 따옴표 없이 작성한다. `Customer.objects.raw()`에도 `params`를 전달할 수 있으며, 모델 인스턴스를 만들기 위해 쿼리에 기본 키를 포함한다. [Django 직접 SQL 실행](https://docs.djangoproject.com/en/5.2/topics/db/sql/)

```python
from django.db import connection

with connection.cursor() as cursor:
    cursor.execute(
        "SELECT id FROM customers WHERE last_name = %s",
        [last_name],
    )
    ids = [row[0] for row in cursor.fetchall()]
```

## 동적 정렬과 검색 조건

- `name`은 `('last_name', 'id')`, `recent`는 `('-created_at', '-id')`로 매핑한다. 폼의 `ChoiceField` 등으로 정렬 키를 검증한 뒤 매핑한 필드만 `order_by(*fields)`에 전달한다.
- `IN` 조회에는 `filter(id__in=ids)`를 사용한다. `ids`에 전달할 값의 타입과 목록 길이를 요청 단계에서 검증한다.
- 부분 검색에는 `filter(last_name__contains=search_text)`를 사용한다. Django는 이 룩업에서 SQL `LIKE` 와일드카드를 이스케이프한다. 대소문자 비교는 MySQL 컬럼의 콜레이션에 따른다. [Django `LIKE` 와일드카드 처리](https://docs.djangoproject.com/en/5.2/topics/db/queries/#escaping-percent-signs-and-underscores-in-like-statements)

## 운영과 검증

- 조회 계정에는 필요한 테이블이나 뷰의 `SELECT` 권한만 부여하고, 스키마 변경에는 별도 계정을 사용한다. [MySQL `GRANT`](https://dev.mysql.com/doc/refman/8.4/en/grant.html)
- MySQL 통합 테스트에서 `O'Connor`는 해당 고객만 반환하고, 일치하지 않는 주석 표기 포함 문자열은 빈 결과를 반환하는지 확인한다. 누락, 빈 값, 길이 초과는 HTTP 400을 반환하는지 확인한다. 직접 작성한 SQL을 사용한다면 같은 입력으로 ORM 조회와 결과를 비교한다. 허용된 정렬 키의 순서와 `contains`의 `%`, `_` 처리도 검증한다.
