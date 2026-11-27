// 요청값 검증. 검증을 통과한 값도 SQL에는 항상 바인딩한다.

export const MAX_LAST_NAME_LENGTH = 100;
export const MAX_IDS = 100;

export class ValidationError extends Error {
  constructor(message) {
    super(message);
    this.name = 'ValidationError';
  }
}

// Express.md: 단일 문자열인지 확인한 뒤 길이와 공백을 검사한다(배열/객체/누락 거부).
export function requireLastName(value, field = 'lastName') {
  if (typeof value !== 'string' || !value.trim() || [...value].length > MAX_LAST_NAME_LENGTH) {
    throw new ValidationError(`${field}: 성을 1자 이상 100자 이하로 입력해야 합니다.`);
  }
  return value;
}

export function requireKeyword(value) {
  if (typeof value !== 'string' || value.length === 0 || [...value].length > MAX_LAST_NAME_LENGTH) {
    throw new ValidationError('keyword: 검색어를 1자 이상 100자 이하로 입력해야 합니다.');
  }
  return value;
}

// ids=1,2,3 형식. 빈 문자열은 빈 목록으로 처리한다.
export function parseIds(value) {
  if (typeof value !== 'string') {
    throw new ValidationError('ids: 쉼표로 구분한 ID 목록을 하나의 파라미터로 전달해야 합니다.');
  }
  if (value.trim() === '') {
    return [];
  }
  const ids = value.split(',').map((part) => part.trim());
  if (ids.length > MAX_IDS || ids.some((id) => !/^[1-9][0-9]{0,17}$/.test(id))) {
    throw new ValidationError(`ids: 1 이상의 정수 ID를 최대 ${MAX_IDS}개까지 전달할 수 있습니다.`);
  }
  return [...new Set(ids)];
}

export function parseId(value) {
  if (typeof value !== 'string' || !/^[1-9][0-9]{0,17}$/.test(value)) {
    throw new ValidationError('id: 1 이상의 정수여야 합니다.');
  }
  return value;
}

export function parseIntInRange(value, field, { min, max, fallback }) {
  if (value === undefined) {
    return fallback;
  }
  if (typeof value !== 'string' || !/^[0-9]{1,9}$/.test(value)) {
    throw new ValidationError(`${field}: 정수여야 합니다.`);
  }
  const parsed = Number(value);
  if (parsed < min || parsed > max) {
    throw new ValidationError(`${field}: ${min} 이상 ${max} 이하여야 합니다.`);
  }
  return parsed;
}

export function requireLastNameList(value) {
  if (!Array.isArray(value) || value.length === 0 || value.length > MAX_IDS) {
    throw new ValidationError(`lastNames: 1개 이상 ${MAX_IDS}개 이하의 배열이어야 합니다.`);
  }
  return value.map((item, index) => requireLastName(item, `lastNames[${index}]`).trim());
}
