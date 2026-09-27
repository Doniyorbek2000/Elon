import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';

import { PrismaService } from '../../infra/prisma.service';

/** Runtime switches. Everything commercial starts OFF (free growth phase). */
export const FLAG_KEYS = [
  'monetization',
  'listingTop',
  'listingVip',
  'listingBump',
  'featuredListings',
  'premiumJobs',
  'featuredServices',
  'businessAccounts',
  'businessPlans',
  'ads',
  'coupons',
  'promotionCredits',
] as const;
export type FlagKey = (typeof FLAG_KEYS)[number];

export interface RankingSettings {
  /** Paid items shown in the labeled block on the first page. */
  promotedSlots: number;
  featuredSlots: number;
  bumpCooldownHours: number;
}

export interface NoticeSettings {
  promotionExpiringHours: number;
  subscriptionExpiringDays: number;
  subscriptionGraceDays: number;
}

/**
 * Allowed payment providers per platform. Digital products bought inside the
 * mobile apps default to the stores' billing (see docs/monetization.md).
 */
export interface CheckoutRoutes {
  ios: string[];
  android: string[];
  web: string[];
}

export const SETTING_DEFAULTS = {
  ranking: { promotedSlots: 3, featuredSlots: 6, bumpCooldownHours: 24 } satisfies RankingSettings,
  notices: {
    promotionExpiringHours: 24,
    subscriptionExpiringDays: 3,
    subscriptionGraceDays: 0,
  } satisfies NoticeSettings,
  checkoutRoutes: { ios: ['APPLE'], android: ['GOOGLE'], web: ['PAYME', 'CLICK'] } satisfies CheckoutRoutes,
};
export type SettingKey = keyof typeof SETTING_DEFAULTS;

const TTL_MS = 15_000;

/**
 * Feature flags and settings live in the database so the team can switch
 * features and tune rules without a deploy or an app release. Values are
 * cached briefly per process; admin writes invalidate the local cache.
 */
@Injectable()
export class MonetizationConfig {
  private cache?: { at: number; flags: Map<string, boolean>; settings: Map<string, unknown> };

  constructor(private readonly prisma: PrismaService) {}

  private async load() {
    if (this.cache && Date.now() - this.cache.at < TTL_MS) return this.cache;
    const [flags, settings] = await Promise.all([
      this.prisma.featureFlag.findMany(),
      this.prisma.appSetting.findMany(),
    ]);
    this.cache = {
      at: Date.now(),
      flags: new Map(flags.map((f) => [f.key, f.enabled])),
      settings: new Map(settings.map((s) => [s.key, s.value])),
    };
    return this.cache;
  }

  invalidate(): void {
    this.cache = undefined;
  }

  /** A product flag is on only when the master `monetization` switch is on too. */
  async enabled(key: FlagKey): Promise<boolean> {
    const { flags } = await this.load();
    if (key !== 'monetization' && key !== 'businessAccounts' && !flags.get('monetization')) return false;
    return flags.get(key) ?? false;
  }

  async flags(): Promise<Record<FlagKey, boolean>> {
    const entries = await Promise.all(FLAG_KEYS.map(async (key) => [key, await this.enabled(key)] as const));
    return Object.fromEntries(entries) as Record<FlagKey, boolean>;
  }

  async setting<K extends SettingKey>(key: K): Promise<(typeof SETTING_DEFAULTS)[K]> {
    const { settings } = await this.load();
    const stored = settings.get(key);
    const defaults = SETTING_DEFAULTS[key];
    return stored && typeof stored === 'object' ? { ...defaults, ...stored } : defaults;
  }

  async setFlag(key: FlagKey, enabled: boolean, actorId: string, description?: string) {
    await this.prisma.featureFlag.upsert({
      where: { key },
      create: { key, enabled, description, updatedById: actorId },
      update: { enabled, description, updatedById: actorId },
    });
    this.invalidate();
  }

  async setSetting(key: SettingKey, value: Prisma.InputJsonValue, actorId: string) {
    await this.prisma.appSetting.upsert({
      where: { key },
      create: { key, value, updatedById: actorId },
      update: { value, updatedById: actorId },
    });
    this.invalidate();
  }
}
