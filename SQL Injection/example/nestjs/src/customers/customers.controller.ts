import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Injectable,
  NotFoundException,
  Param,
  PipeTransform,
  Post,
  Put,
  Query,
} from '@nestjs/common';

import { CustomersRepository, type Customer } from './customers.repository';
import {
  CustomerBatchDto,
  CustomerBodyDto,
  CustomerContainsDto,
  CustomerIdsDto,
  CustomerListDto,
  CustomerSearchDto,
  CustomerSortDto,
} from './dto/customer-queries.dto';

@Injectable()
export class ParseIdPipe implements PipeTransform<string, string> {
  transform(value: string): string {
    if (!/^[1-9][0-9]{0,17}$/.test(value)) {
      throw new BadRequestException('id는 1 이상의 정수여야 합니다.');
    }
    return value;
  }
}

// 검증은 main.ts / test에서 등록한 전역 ValidationPipe가 DTO 기준으로 수행한다.
@Controller('customers')
export class CustomersController {
  constructor(private readonly customers: CustomersRepository) {}

  @Get('search')
  search(@Query() query: CustomerSearchDto): Promise<string[]> {
    return this.customers.searchByLastName(query.lastName, query.sort);
  }

  @Get('contains')
  contains(@Query() query: CustomerContainsDto): Promise<string[]> {
    return this.customers.searchByLastNameContains(query.keyword);
  }

  @Get('sorted')
  sorted(@Query() query: CustomerSortDto): Promise<string[]> {
    return this.customers.findAllIdsSorted(query.sort);
  }

  @Get('by-ids')
  byIds(@Query() query: CustomerIdsDto): Promise<string[]> {
    const ids = query.ids === '' ? [] : [...new Set(query.ids.split(','))];
    return this.customers.findIds(ids);
  }

  @Get()
  list(@Query() query: CustomerListDto): Promise<Customer[]> {
    return this.customers.list(query.limit, query.offset);
  }

  @Post('batch')
  createAll(@Body() body: CustomerBatchDto): Promise<Customer[]> {
    return this.customers.createAll(body.lastNames);
  }

  @Post()
  create(@Body() body: CustomerBodyDto): Promise<Customer> {
    return this.customers.create(body.lastName);
  }

  @Get(':id')
  async findOne(@Param('id', ParseIdPipe) id: string): Promise<Customer> {
    return (await this.customers.findById(id)) ?? notFound();
  }

  @Put(':id')
  async update(@Param('id', ParseIdPipe) id: string, @Body() body: CustomerBodyDto): Promise<Customer> {
    return (await this.customers.update(id, body.lastName)) ?? notFound();
  }

  @Delete(':id')
  @HttpCode(204)
  async remove(@Param('id', ParseIdPipe) id: string): Promise<void> {
    if (!(await this.customers.remove(id))) {
      notFound();
    }
  }
}

function notFound(): never {
  throw new NotFoundException('고객을 찾을 수 없습니다.');
}
