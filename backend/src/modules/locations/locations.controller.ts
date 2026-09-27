import { Controller, Get, Header, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsLatitude, IsLongitude } from 'class-validator';

import { Public } from '../../common/auth.decorators';
import { LocationsService } from './locations.service';

class ResolveQuery {
  @Type(() => Number)
  @IsLatitude()
  lat!: number;

  @Type(() => Number)
  @IsLongitude()
  lng!: number;
}

@ApiTags('locations')
@Public()
@Controller('locations')
export class LocationsController {
  constructor(private readonly locations: LocationsService) {}

  @Get('tree')
  @Header('Cache-Control', 'public, max-age=3600')
  tree() {
    return this.locations.tree();
  }

  /** Approximate GPS → district. Coordinates are not stored. */
  @Get('resolve')
  resolve(@Query() query: ResolveQuery) {
    return this.locations.resolve(query.lat, query.lng);
  }
}
