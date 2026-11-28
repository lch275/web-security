"""요청값 검증. 검증을 통과한 값만 ORM 또는 바인딩 파라미터로 전달한다."""

from django import forms
from django.core.exceptions import ValidationError

# Django.md: name은 ('last_name', 'id'), recent는 ('-created_at', '-id')로 매핑한다.
ORDERINGS = {
    "name": ("last_name", "id"),
    "recent": ("-created_at", "-id"),
}
SORT_CHOICES = [(key, key) for key in ORDERINGS]
MAX_IDS = 100


class CustomerSearchForm(forms.Form):
    last_name = forms.CharField(max_length=100)  # 기본 동작으로 앞뒤 공백을 제거한다.
    sort = forms.ChoiceField(choices=SORT_CHOICES, required=False)

    def clean_sort(self):
        return self.cleaned_data["sort"] or "name"


class CustomerSortForm(forms.Form):
    sort = forms.ChoiceField(choices=SORT_CHOICES)


class CustomerContainsForm(forms.Form):
    keyword = forms.CharField(max_length=100, strip=False)


class CustomerIdsForm(forms.Form):
    ids = forms.CharField(required=False, strip=True, max_length=2000)

    def clean_ids(self):
        raw = self.cleaned_data["ids"]
        if raw == "":
            return []
        parts = raw.split(",")
        if len(parts) > MAX_IDS or not all(p.isascii() and p.isdigit() and not p.startswith("0") and len(p) <= 18 for p in parts):
            raise ValidationError(f"1 이상의 정수 ID를 최대 {MAX_IDS}개까지 전달할 수 있습니다.")
        return sorted({int(p) for p in parts})

    def clean(self):
        # ids 파라미터 자체가 없으면 거부한다(빈 문자열은 빈 목록으로 허용).
        if "ids" not in self.data:
            self.add_error("ids", "ids 파라미터가 필요합니다.")
        return super().clean()


class CustomerListForm(forms.Form):
    limit = forms.IntegerField(min_value=1, max_value=100, required=False)
    offset = forms.IntegerField(min_value=0, max_value=100_000, required=False)


class CustomerForm(forms.Form):
    last_name = forms.CharField(max_length=100)


def clean_batch(data) -> tuple[list[str] | None, str | None]:
    """JSON 본문의 last_names 배열을 검증한다. 각 원소는 CustomerForm 규칙을 따른다."""
    last_names = data.get("last_names") if isinstance(data, dict) else None
    if not isinstance(last_names, list) or not 1 <= len(last_names) <= MAX_IDS:
        return None, f"last_names는 1개 이상 {MAX_IDS}개 이하의 배열이어야 합니다."
    cleaned = []
    for index, value in enumerate(last_names):
        form = CustomerForm({"last_name": value} if isinstance(value, str) else {})
        if not form.is_valid():
            return None, f"last_names[{index}]: 1자 이상 100자 이하의 문자열이어야 합니다."
        cleaned.append(form.cleaned_data["last_name"])
    return cleaned, None
