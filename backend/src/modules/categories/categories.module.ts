import { Controller, Get, Global, Header, Module, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { CategoryKind } from '@prisma/client';
import { IsIn, IsOptional } from 'class-validator';

import { Public } from '../../common/auth.decorators';
import { dbEnum } from '../../common/text';
import { CategoriesService } from './categories.service';

class TreeQuery {
  @IsOptional()
  @IsIn(['marketplace', 'jobs', 'services'])
  kind?: string;
}

@ApiTags('categories')
@Public()
@Controller('categories')
class CategoriesController {
  constructor(private readonly categories: CategoriesService) {}

  /** Category tree with server-driven form schemas. */
  @Get()
  @Header('Cache-Control', 'public, max-age=300')
  tree(@Query() query: TreeQuery) {
    return this.categories.tree(query.kind ? (dbEnum(query.kind) as CategoryKind) : undefined);
  }
}

@Global()
@Module({
  controllers: [CategoriesController],
  providers: [CategoriesService],
  exports: [CategoriesService],
})
export class CategoriesModule {}
