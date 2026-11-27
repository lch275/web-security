import json
import logging

from django.db import connection
from django.http import HttpResponse, JsonResponse
from django.views.decorators.http import require_GET, require_http_methods, require_POST

from . import queries
from .forms import (
    CustomerContainsForm,
    CustomerForm,
    CustomerIdsForm,
    CustomerListForm,
    CustomerSearchForm,
    CustomerSortForm,
    clean_batch,
)
from .models import Customer

logger = logging.getLogger(__name__)


def _form_errors(form) -> JsonResponse:
    return JsonResponse({"errors": form.errors.get_json_data()}, status=400)


def _error(message: str, status: int) -> JsonResponse:
    return JsonResponse({"errors": {"__all__": [{"message": message}]}}, status=status)


def _json_body(request):
    try:
        return json.loads(request.body or b"null")
    except (ValueError, UnicodeDecodeError):
        return None


def _last_name_data(body) -> dict:
    """JSON 값이 문자열일 때만 폼에 전달한다. 배열/객체는 CharField에서 문자열로 변환되지 않도록 거부한다."""
    value = body.get("last_name") if isinstance(body, dict) else None
    return {"last_name": value} if isinstance(value, str) else {}


def _parse_id(raw: str) -> int | None:
    return int(raw) if raw.isascii() and raw.isdigit() and not raw.startswith("0") and len(raw) <= 18 else None


@require_GET
def health(request):
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
            cursor.fetchone()
        return JsonResponse({"status": "UP"})
    except Exception as exc:  # noqa: BLE001 - 상태 점검은 모든 DB 오류를 DOWN으로 보고한다.
        logger.warning("health check failed: %s", type(exc).__name__)
        return JsonResponse({"status": "DOWN"}, status=503)


@require_GET
def search_customers(request):
    """Django.md의 검색 뷰. 정렬 키는 ChoiceField로 검증한 뒤 매핑한 필드만 order_by에 전달한다."""
    form = CustomerSearchForm(request.GET)
    if not form.is_valid():
        return _form_errors(form)
    ids = queries.search_ids(form.cleaned_data["last_name"], form.cleaned_data["sort"])
    return JsonResponse(ids, safe=False)


@require_GET
def contains(request):
    form = CustomerContainsForm(request.GET)
    if not form.is_valid():
        return _form_errors(form)
    return JsonResponse(queries.contains_ids(form.cleaned_data["keyword"]), safe=False)


@require_GET
def sorted_customers(request):
    form = CustomerSortForm(request.GET)
    if not form.is_valid():
        return _form_errors(form)
    return JsonResponse(queries.sorted_ids(form.cleaned_data["sort"]), safe=False)


@require_GET
def by_ids(request):
    form = CustomerIdsForm(request.GET)
    if not form.is_valid():
        return _form_errors(form)
    return JsonResponse(queries.ids_in(form.cleaned_data["ids"]), safe=False)


@require_http_methods(["GET", "POST"])
def collection(request):
    if request.method == "GET":
        form = CustomerListForm(request.GET)
        if not form.is_valid():
            return _form_errors(form)
        limit = form.cleaned_data["limit"] or 20
        offset = form.cleaned_data["offset"] or 0
        customers = Customer.objects.order_by("id")[offset : offset + limit]
        return JsonResponse([c.to_dict() for c in customers], safe=False)

    form = CustomerForm(_last_name_data(_json_body(request)))
    if not form.is_valid():
        return _form_errors(form)
    return JsonResponse(queries.create(form.cleaned_data["last_name"]).to_dict(), status=201)


@require_POST
def batch(request):
    last_names, error = clean_batch(_json_body(request))
    if error:
        return _error(error, 400)
    return JsonResponse([c.to_dict() for c in queries.create_all(last_names)], safe=False, status=201)


@require_http_methods(["GET", "PUT", "DELETE"])
def detail(request, customer_id: str):
    pk = _parse_id(customer_id)
    if pk is None:
        return _error("id는 1 이상의 정수여야 합니다.", 400)

    if request.method == "GET":
        customer = Customer.objects.filter(pk=pk).first()
        return JsonResponse(customer.to_dict()) if customer else _error("고객을 찾을 수 없습니다.", 404)

    if request.method == "PUT":
        form = CustomerForm(_last_name_data(_json_body(request)))
        if not form.is_valid():
            return _form_errors(form)
        if Customer.objects.filter(pk=pk).update(last_name=form.cleaned_data["last_name"]) == 0:
            return _error("고객을 찾을 수 없습니다.", 404)
        return JsonResponse(Customer.objects.get(pk=pk).to_dict())

    deleted, _ = Customer.objects.filter(pk=pk).delete()
    return HttpResponse(status=204) if deleted else _error("고객을 찾을 수 없습니다.", 404)
