import { Transform, Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Length,
  Matches,
  Max,
  Min,
} from 'class-validator';

export const SORT_KEYS = ['name', 'recent'] as const;
export type SortKey = (typeof SORT_KEYS)[number];

const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);

// NestJS.md의 검색 DTO. 중복 파라미터(배열)는 @IsString에서 거부된다.
export class CustomerSearchDto {
  @IsString()
  @Length(1, 100)
  @Matches(/\S/)
  lastName!: string;

  @IsOptional()
  @IsIn(SORT_KEYS)
  sort: SortKey = 'name';
}

export class CustomerSortDto {
  @IsIn(SORT_KEYS)
  sort!: SortKey;
}

export class CustomerContainsDto {
  @IsString()
  @Length(1, 100)
  keyword!: string;
}

// ids=1,2,3 형식. 빈 문자열은 빈 목록이다.
export class CustomerIdsDto {
  @IsString()
  @Matches(/^$|^[1-9][0-9]{0,17}(,[1-9][0-9]{0,17}){0,99}$/, {
    message: 'ids는 쉼표로 구분한 1 이상의 정수를 최대 100개까지 전달할 수 있습니다.',
  })
  ids!: string;
}

export class CustomerListDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit: number = 20;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(100_000)
  offset: number = 0;
}

export class CustomerBodyDto {
  @Transform(trim)
  @IsString()
  @Length(1, 100)
  lastName!: string;
}

export class CustomerBatchDto {
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(100)
  @Transform(({ value }) => (Array.isArray(value) ? value.map((v) => (typeof v === 'string' ? v.trim() : v)) : value))
  @IsString({ each: true })
  @Length(1, 100, { each: true })
  lastNames!: string[];
}
