import { Injectable, Logger } from '@nestjs/common';

import { AppError } from '../../common/errors';
import { PrismaService } from '../../infra/prisma.service';

export type ListingMetric = 'views' | 'favorites' | 'contacts' | 'chats' | 'shares';

const DAY = 86400_000;

function utcDay(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

/**
 * Seller analytics from real, aggregated counters only (no viewer
 * identities are stored). Nothing is estimated or extrapolated.
 */
@Injectable()
export class AnalyticsService {
  private readonly logger = new Logger(AnalyticsService.name);

  constructor(private readonly prisma: PrismaService) {}

  /** Best effort: analytics must never break the user action being counted. */
  async bump(listingId: string, metric: ListingMetric, now = new Date()): Promise<void> {
    const day = utcDay(now);
    await this.prisma.listingDailyStat
      .upsert({
        where: { listingId_day: { listingId, day } },
        create: { listingId, day, [metric]: 1 },
        update: { [metric]: { increment: 1 } },
      })
      .catch((error: Error) => this.logger.warn(`stat ${metric} failed: ${error.message}`));
  }

  private async series(listingId: string, from: Date, to: Date) {
    const rows = await this.prisma.listingDailyStat.findMany({
      where: { listingId, day: { gte: utcDay(from), lte: utcDay(to) } },
      orderBy: { day: 'asc' },
    });
    const totals = { views: 0, favorites: 0, contacts: 0, chats: 0, shares: 0 };
    for (const r of rows) {
      totals.views += r.views;
      totals.favorites += r.favorites;
      totals.contacts += r.contacts;
      totals.chats += r.chats;
      totals.shares += r.shares;
    }
    return {
      totals,
      daily: rows.map((r) => ({
        day: r.day.toISOString().slice(0, 10),
        views: r.views,
        favorites: r.favorites,
        contacts: r.contacts,
        chats: r.chats,
        shares: r.shares,
      })),
    };
  }

  /** Daily series for up to 90 days, optionally a custom range. */
  async listingStats(userId: string, listingId: string, range: { days?: number; from?: Date; to?: Date }) {
    const listing = await this.prisma.listing.findFirst({
      where: { id: listingId, sellerId: userId, deletedAt: null },
      select: { id: true, viewCount: true, favoriteCount: true, publishedAt: true },
    });
    if (!listing) throw AppError.notFound('Listing');
    const advanced = true;
    const now = new Date();
    let from: Date;
    let to = now;
    if (advanced && range.from) {
      from = range.from;
      to = range.to && range.to < now ? range.to : now;
    } else {
      const days = advanced ? Math.min(range.days ?? 30, 90) : 7;
      from = new Date(now.getTime() - (days - 1) * DAY);
    }
    if (from > to || to.getTime() - from.getTime() > 90 * DAY) throw AppError.validation('Invalid range');
    const { totals, daily } = await this.series(listingId, from, to);
    return {
      level: advanced ? 'advanced' : 'basic',
      from: utcDay(from).toISOString().slice(0, 10),
      to: utcDay(to).toISOString().slice(0, 10),
      totals,
      daily: advanced ? daily : [],
      lifetime: { views: listing.viewCount, favorites: listing.favoriteCount },
    };
  }
}
