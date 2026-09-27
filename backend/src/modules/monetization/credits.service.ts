import { HttpStatus, Injectable } from '@nestjs/common';
import { CreditEntryType, Prisma } from '@prisma/client';

import { AppError } from '../../common/errors';
import { apiEnum } from '../../common/text';
import { PrismaService } from '../../infra/prisma.service';

type Tx = Prisma.TransactionClient;

interface EntryRefs {
  subscriptionId?: string;
  purchaseId?: string;
  activationId?: string;
  adminId?: string;
}

/**
 * Promotion credits as an append-only ledger. `CreditAccount.balance` is a
 * cache of the ledger sum, changed only together with a ledger entry while the
 * account row is locked (FOR UPDATE), so concurrent spends cannot overdraw.
 * Grants are consumed FIFO by expiry; unused grants expire into EXPIRE rows.
 */
@Injectable()
export class CreditsService {
  constructor(private readonly prisma: PrismaService) {}

  private async lock(tx: Tx, userId: string): Promise<number> {
    await tx.creditAccount.upsert({ where: { userId }, create: { userId }, update: {} });
    const rows = await tx.$queryRaw<Array<{ balance: number }>>`
      SELECT "balance" FROM "CreditAccount" WHERE "userId" = ${userId}::uuid FOR UPDATE`;
    return rows[0]?.balance ?? 0;
  }

  async grant(
    tx: Tx,
    userId: string,
    amount: number,
    reason: string,
    refs: EntryRefs & { expiresAt?: Date; type?: CreditEntryType } = {},
  ): Promise<void> {
    if (!Number.isInteger(amount) || amount <= 0) throw AppError.validation('Credit amount must be positive');
    await this.lock(tx, userId);
    const { expiresAt, type = CreditEntryType.GRANT, ...ids } = refs;
    await tx.creditLedgerEntry.create({
      data: { userId, type, amount, remaining: amount, expiresAt, reason, ...ids },
    });
    await tx.creditAccount.update({ where: { userId }, data: { balance: { increment: amount } } });
  }

  /** Spends credits FIFO; throws INSUFFICIENT_CREDITS without side effects. */
  async consume(
    tx: Tx,
    userId: string,
    amount: number,
    reason: string,
    refs: EntryRefs = {},
    type: CreditEntryType = CreditEntryType.CONSUME,
  ): Promise<void> {
    if (!Number.isInteger(amount) || amount <= 0) throw AppError.validation('Credit amount must be positive');
    const balance = await this.lock(tx, userId);
    if (balance < amount) {
      throw new AppError('INSUFFICIENT_CREDITS', 'Not enough promotion credits', HttpStatus.CONFLICT, {
        balance,
      });
    }
    const now = new Date();
    const sources = await tx.creditLedgerEntry.findMany({
      where: { userId, remaining: { gt: 0 }, OR: [{ expiresAt: null }, { expiresAt: { gt: now } }] },
      orderBy: [{ expiresAt: { sort: 'asc', nulls: 'last' } }, { createdAt: 'asc' }],
    });
    let left = amount;
    for (const source of sources) {
      if (left === 0) break;
      const take = Math.min(left, source.remaining);
      await tx.creditLedgerEntry.update({
        where: { id: source.id },
        data: { remaining: source.remaining - take },
      });
      left -= take;
    }
    if (left > 0) {
      // Balance cache and live grants disagree (expired but not yet swept): refuse safely.
      throw new AppError('INSUFFICIENT_CREDITS', 'Not enough promotion credits', HttpStatus.CONFLICT, {
        balance,
      });
    }
    await tx.creditLedgerEntry.create({
      data: { userId, type, amount: -amount, reason, ...refs },
    });
    await tx.creditAccount.update({ where: { userId }, data: { balance: { decrement: amount } } });
  }

  /** Admin correction with mandatory reason (audited by the caller). */
  async adjust(userId: string, amount: number, reason: string, adminId: string): Promise<void> {
    if (!reason.trim()) throw AppError.validation('Reason is required');
    await this.prisma.$transaction(async (tx) => {
      if (amount > 0) {
        await this.grant(tx, userId, amount, reason, { adminId, type: CreditEntryType.ADJUST });
      } else if (amount < 0) {
        await this.consume(tx, userId, -amount, reason, { adminId }, CreditEntryType.ADJUST);
      }
    });
  }

  /** Removes the unused part of grants tied to a subscription (refund/revocation). */
  async revokeSubscriptionGrants(
    tx: Tx,
    userId: string,
    subscriptionId: string,
    reason: string,
  ): Promise<void> {
    await this.lock(tx, userId);
    const grants = await tx.creditLedgerEntry.findMany({
      where: { userId, subscriptionId, remaining: { gt: 0 } },
    });
    for (const grant of grants) await this.expireEntry(tx, grant.id, grant.userId, grant.remaining, reason);
  }

  private async expireEntry(tx: Tx, entryId: string, userId: string, remaining: number, reason: string) {
    const { count } = await tx.creditLedgerEntry.updateMany({
      where: { id: entryId, remaining },
      data: { remaining: 0 },
    });
    if (!count) return;
    await tx.creditLedgerEntry.create({
      data: { userId, type: CreditEntryType.EXPIRE, amount: -remaining, reason },
    });
    await tx.creditAccount.update({ where: { userId }, data: { balance: { decrement: remaining } } });
  }

  /** Worker: expire unused grants past their expiry. Idempotent. */
  async sweepExpired(now = new Date()): Promise<number> {
    const due = await this.prisma.creditLedgerEntry.findMany({
      where: { remaining: { gt: 0 }, expiresAt: { lte: now } },
      take: 500,
    });
    for (const entry of due) {
      await this.prisma.$transaction(async (tx) => {
        await this.lock(tx, entry.userId);
        const fresh = await tx.creditLedgerEntry.findUnique({ where: { id: entry.id } });
        if (fresh && fresh.remaining > 0)
          await this.expireEntry(tx, fresh.id, fresh.userId, fresh.remaining, 'Credits expired');
      });
    }
    return due.length;
  }

  async summary(userId: string) {
    const [account, entries] = await Promise.all([
      this.prisma.creditAccount.findUnique({ where: { userId } }),
      this.prisma.creditLedgerEntry.findMany({ where: { userId }, orderBy: { createdAt: 'desc' }, take: 50 }),
    ]);
    return {
      balance: account?.balance ?? 0,
      entries: entries.map((e) => ({
        id: e.id,
        type: apiEnum(e.type),
        amount: e.amount,
        reason: e.reason,
        expiresAt: e.expiresAt,
        createdAt: e.createdAt,
      })),
    };
  }
}
