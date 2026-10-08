import { Controller, Get, Query } from '@nestjs/common';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsString, Max, Min } from 'class-validator';
import { Auth } from '../auth/auth.guard';
import { CatalogService } from './catalog.service';

export class SearchProductsQuery {
  @IsString()
  q!: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page = 1;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(20)
  size = 20;
}

@Controller('products')
@Auth('USER')
export class CatalogController {
  constructor(private readonly catalog: CatalogService) {}

  @Get('search')
  search(@Query() query: SearchProductsQuery) {
    return this.catalog.search(query.q, query.page, query.size);
  }
}
