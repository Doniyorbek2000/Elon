import { Injectable } from '@nestjs/common';

import { AppError } from '../../common/errors';
import { PrismaService } from '../../infra/prisma.service';

export interface PlaceInput {
  regionId: string;
  districtId?: string | null;
  localityId?: string | null;
  lat?: number | null;
  lng?: number | null;
}

export interface ResolvedPlace {
  regionId: string;
  districtId: string | null;
  localityId: string | null;
  lat: number;
  lng: number;
}

/** Maximum distance from Uzbekistan's district centers for GPS resolution. */
const MAX_RESOLVE_KM = 150;

@Injectable()
export class LocationsService {
  private treeCache?: { at: number; value: unknown };

  constructor(private readonly prisma: PrismaService) {}

  /** Whole tree (~14 regions, ~200 districts): small, cacheable, bootstrapped by the app. */
  async tree() {
    if (this.treeCache && Date.now() - this.treeCache.at < 10 * 60_000) return this.treeCache.value;
    const regions = await this.prisma.region.findMany({
      orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
      include: {
        districts: {
          orderBy: { name: 'asc' },
          include: {
            localities: { orderBy: { name: 'asc' }, select: { id: true, name: true, lat: true, lng: true } },
          },
        },
      },
    });
    const value = regions.map((r) => ({
      id: r.id,
      name: r.name,
      lat: r.lat,
      lng: r.lng,
      districts: r.districts.map((d) => ({
        id: d.id,
        name: d.name,
        lat: d.lat,
        lng: d.lng,
        localities: d.localities,
      })),
    }));
    this.treeCache = { at: Date.now(), value };
    return value;
  }

  /** Nearest district to a coordinate using the PostGIS GiST index (KNN). */
  async resolve(lat: number, lng: number) {
    const rows = await this.prisma.$queryRaw<Array<{ id: string; region_id: string; km: number }>>`
      SELECT d."id", d."regionId" AS region_id,
             ST_Distance(d."geo", ST_SetSRID(ST_MakePoint(${lng}, ${lat}), 4326)::geography) / 1000 AS km
      FROM "District" d
      WHERE d."geo" IS NOT NULL
      ORDER BY d."geo" <-> ST_SetSRID(ST_MakePoint(${lng}, ${lat}), 4326)::geography
      LIMIT 1`;
    const nearest = rows[0];
    if (!nearest || nearest.km > MAX_RESOLVE_KM) throw AppError.notFound('District near this location');
    const district = await this.prisma.district.findUniqueOrThrow({
      where: { id: nearest.id },
      include: { region: true },
    });
    return {
      regionId: district.regionId,
      regionName: district.region.name,
      districtId: district.id,
      districtName: district.name,
      distanceKm: Math.round(nearest.km * 10) / 10,
    };
  }

  /**
   * Validates hierarchy consistency and resolves coordinates: explicit lat/lng
   * (approximate pin) > locality > district > region center.
   */
  async resolvePlace(input: PlaceInput): Promise<ResolvedPlace> {
    const region = await this.prisma.region.findUnique({ where: { id: input.regionId } });
    if (!region) throw AppError.validation('Unknown region', { field: 'regionId' });
    let lat = region.lat;
    let lng = region.lng;

    let districtId: string | null = null;
    if (input.districtId) {
      const district = await this.prisma.district.findUnique({ where: { id: input.districtId } });
      if (!district || district.regionId !== region.id) {
        throw AppError.validation('District does not belong to region', { field: 'districtId' });
      }
      districtId = district.id;
      if (district.lat != null && district.lng != null) {
        lat = district.lat;
        lng = district.lng;
      }
    }

    let localityId: string | null = null;
    if (input.localityId) {
      const locality = await this.prisma.locality.findUnique({ where: { id: input.localityId } });
      if (!locality || locality.districtId !== districtId) {
        throw AppError.validation('Locality does not belong to district', { field: 'localityId' });
      }
      localityId = locality.id;
      if (locality.lat != null && locality.lng != null) {
        lat = locality.lat;
        lng = locality.lng;
      }
    }

    if (input.lat != null && input.lng != null) {
      if (Math.abs(input.lat - lat) > 3 || Math.abs(input.lng - lng) > 3) {
        throw AppError.validation('Coordinates are far from the selected area', { field: 'lat' });
      }
      lat = input.lat;
      lng = input.lng;
    }
    return { regionId: region.id, districtId, localityId, lat, lng };
  }

  /** Center used as the origin for radius searches. */
  async origin(regionId?: string, districtId?: string): Promise<{ lat: number; lng: number } | undefined> {
    if (districtId) {
      const district = await this.prisma.district.findUnique({ where: { id: districtId } });
      if (district?.lat != null && district.lng != null) return { lat: district.lat, lng: district.lng };
    }
    if (regionId) {
      const region = await this.prisma.region.findUnique({ where: { id: regionId } });
      if (region) return { lat: region.lat, lng: region.lng };
    }
    return undefined;
  }
}
