/**
 * Paid-visibility badges shown on cards. They are separate from quality
 * signals (ratings, verification) and never influence them.
 */
export type Badge = 'vip' | 'top' | 'featured' | 'urgent';

const ORDER: Badge[] = ['vip', 'top', 'featured', 'urgent'];

/** Cheap fallback from the ranking cache when activations were not loaded. */
export function badgesFromTier(tier: number, until: Date | null, now = new Date()): Badge[] {
  if (!until || until <= now || tier <= 0) return [];
  return tier >= 2 ? ['vip'] : ['top'];
}

export function sortBadges(badges: Iterable<Badge>): Badge[] {
  const set = new Set(badges);
  return ORDER.filter((b) => set.has(b));
}

export interface BadgeOptions {
  /** Badges from active PromotionActivation rows (preferred). */
  badges?: Badge[];
}

export function presentBadges(row: { boostTier: number; boostUntil: Date | null }, options: BadgeOptions) {
  const badges = options.badges ?? badgesFromTier(row.boostTier, row.boostUntil);
  return { promotion: badges[0] ?? null, badges, sponsored: badges.length > 0 };
}
