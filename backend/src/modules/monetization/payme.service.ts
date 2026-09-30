import { timingSafeEqual } from 'node:crypto';

import { Injectable, Logger } from '@nestjs/common';
import { PaymeTransaction, Payment, PaymentProviderKey, PaymentStatus, Prisma } from '@prisma/client';

import { env } from '../../config/env';
import { PrismaService } from '../../infra/prisma.service';
import { PaymentsService } from './payments.service';

/** Transaction lifetime: Payme cancels created-but-unpaid transactions after 12 hours. */
export const PAYME_TIMEOUT_MS = 12 * 3600 * 1000;

/** JSON-RPC error codes from the Payme Merchant API. */
export const PaymeCode = {
  InvalidAmount: -31001,
  TransactionNotFound: -31003,
  CannotCancel: -31007,
  CannotPerform: -31008,
  OrderNotFound: -31050,
  OrderUnavailable: -31051,
  OrderBusy: -31099,
  InsufficientPrivilege: -32504,
  MethodNotFound: -32601,
  InvalidRequest: -32600,
} as const;

const MESSAGES: Record<number, { ru: string; uz: string; en: string }> = {
  [PaymeCode.InvalidAmount]: {
    ru: 'Неверная сумма',
    uz: 'Noto‘g‘ri summa',
    en: 'Incorrect amount',
  },
  [PaymeCode.TransactionNotFound]: {
    ru: 'Транзакция не найдена',
    uz: 'Tranzaksiya topilmadi',
    en: 'Transaction not found',
  },
  [PaymeCode.CannotCancel]: {
    ru: 'Невозможно отменить транзакцию',
    uz: 'Tranzaksiyani bekor qilib bo‘lmaydi',
    en: 'Unable to cancel transaction',
  },
  [PaymeCode.CannotPerform]: {
    ru: 'Невозможно выполнить операцию',
    uz: 'Amalni bajarib bo‘lmaydi',
    en: 'Unable to perform operation',
  },
  [PaymeCode.OrderNotFound]: { ru: 'Заказ не найден', uz: 'Buyurtma topilmadi', en: 'Order not found' },
  [PaymeCode.OrderUnavailable]: {
    ru: 'Заказ недоступен для оплаты',
    uz: 'Buyurtma to‘lov uchun mavjud emas',
    en: 'Order is not payable',
  },
  [PaymeCode.OrderBusy]: {
    ru: 'Заказ ожидает оплаты по другой транзакции',
    uz: 'Buyurtma boshqa tranzaksiya bo‘yicha to‘lanmoqda',
    en: 'Order awaits payment in another transaction',
  },
  [PaymeCode.InsufficientPrivilege]: {
    ru: 'Недостаточно привилегий для выполнения метода',
    uz: 'Metodni bajarish uchun huquq yetarli emas',
    en: 'Insufficient privileges',
  },
  [PaymeCode.MethodNotFound]: { ru: 'Метод не найден', uz: 'Metod topilmadi', en: 'Method not found' },
  [PaymeCode.InvalidRequest]: { ru: 'Неверный запрос', uz: 'Noto‘g‘ri so‘rov', en: 'Invalid request' },
};

class PaymeError extends Error {
  constructor(
    readonly code: number,
    readonly data?: string,
  ) {
    super(MESSAGES[code]?.en ?? 'Error');
  }
}

interface RpcRequest {
  id: unknown;
  method: string;
  params: Record<string, unknown>;
}

type Tx = Prisma.TransactionClient;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

/**
 * Payme Merchant API (JSON-RPC 2.0 over one HTTPS endpoint, Basic auth).
 * Every reply, including errors, is HTTP 200 with a JSON-RPC body.
 *
 * Money moves only through `PaymentsService.applyEvent` (idempotent per
 * event id), so a retried PerformTransaction after a crash cannot fulfill
 * twice: the event is deduplicated and the local state catches up.
 */
@Injectable()
export class PaymeService {
  private readonly logger = new Logger(PaymeService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly payments: PaymentsService,
  ) {}

  async handle(authorization: string | undefined, body: unknown): Promise<Record<string, unknown>> {
    const request = isRecord(body) ? body : {};
    const id = request.id ?? null;
    try {
      if (!this.authorized(authorization)) throw new PaymeError(PaymeCode.InsufficientPrivilege);
      if (typeof request.method !== 'string' || !isRecord(request.params)) {
        throw new PaymeError(PaymeCode.InvalidRequest);
      }
      const rpc: RpcRequest = { id, method: request.method, params: request.params };
      return { jsonrpc: '2.0', id, result: await this.dispatch(rpc) };
    } catch (error) {
      if (error instanceof PaymeError) {
        return {
          jsonrpc: '2.0',
          id,
          error: { code: error.code, message: MESSAGES[error.code], data: error.data ?? null },
        };
      }
      this.logger.error(error instanceof Error ? error.stack : String(error));
      // Payme retries on transport failures; report an internal error as "cannot perform".
      return {
        jsonrpc: '2.0',
        id,
        error: { code: PaymeCode.CannotPerform, message: MESSAGES[PaymeCode.CannotPerform], data: null },
      };
    }
  }

  private authorized(header: string | undefined): boolean {
    const key = env().PAYME_KEY;
    if (!key || !header?.startsWith('Basic ')) return false;
    const expected = Buffer.from(`Paycom:${key}`);
    const given = Buffer.from(Buffer.from(header.slice(6), 'base64').toString('utf8'));
    return given.length === expected.length && timingSafeEqual(given, expected);
  }

  private dispatch(rpc: RpcRequest): Promise<unknown> {
    switch (rpc.method) {
      case 'CheckPerformTransaction':
        return this.checkPerform(rpc.params);
      case 'CreateTransaction':
        return this.create(rpc.params);
      case 'PerformTransaction':
        return this.perform(rpc.params);
      case 'CancelTransaction':
        return this.cancel(rpc.params);
      case 'CheckTransaction':
        return this.check(rpc.params);
      case 'GetStatement':
        return this.statement(rpc.params);
      default:
        throw new PaymeError(PaymeCode.MethodNotFound, rpc.method);
    }
  }

  // ─────────────────────────────────────────────────────── methods

  private async checkPerform(params: Record<string, unknown>) {
    await this.payableOrder(this.prisma, params);
    return { allow: true };
  }

  private async create(params: Record<string, unknown>) {
    const id = this.transactionId(params);
    const time = Date.now();
    const outcome = await this.prisma.$transaction(
      async (tx) => {
        const payment = await this.payableOrder(tx, params, { lock: true });
        const existing = await tx.paymeTransaction.findUnique({ where: { id } });
        if (existing) {
          if (existing.state !== 1) throw new PaymeError(PaymeCode.CannotPerform);
          if (this.expired(existing, time)) {
            // Commit the expiry, then report it (throwing here would roll it back).
            await this.expire(tx, existing, time);
            return null;
          }
          return this.createResult(existing);
        }
        const others = await tx.paymeTransaction.findMany({ where: { paymentId: payment.id, state: 1 } });
        for (const other of others) {
          if (this.expired(other, time)) await this.expire(tx, other, time);
          else throw new PaymeError(PaymeCode.OrderBusy, 'order_id');
        }
        const created = await tx.paymeTransaction.create({
          data: {
            id,
            paymentId: payment.id,
            amountMinor: payment.amountMinor,
            state: 1,
            createTime: BigInt(time),
          },
        });
        return this.createResult(created);
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted },
    );
    if (!outcome) throw new PaymeError(PaymeCode.CannotPerform);
    return outcome;
  }

  private async perform(params: Record<string, unknown>) {
    const transaction = await this.transaction(params);
    if (transaction.state === 2) return this.performResult(transaction);
    if (transaction.state !== 1) throw new PaymeError(PaymeCode.CannotPerform);
    const now = Date.now();
    if (this.expired(transaction, now)) {
      await this.prisma.$transaction((tx) => this.expire(tx, transaction, now));
      throw new PaymeError(PaymeCode.CannotPerform);
    }
    // Fulfillment first (idempotent per event id); local state follows.
    await this.payments.applyEvent(
      PaymentProviderKey.PAYME,
      {
        eventId: `payme:${transaction.id}:perform`,
        paymentId: transaction.paymentId,
        type: 'succeeded',
        amountMinor: transaction.amountMinor,
      },
      'webhook',
    );
    await this.prisma.paymeTransaction.updateMany({
      where: { id: transaction.id, state: 1 },
      data: { state: 2, performTime: BigInt(now) },
    });
    return this.performResult(await this.transaction(params));
  }

  private async cancel(params: Record<string, unknown>) {
    const transaction = await this.transaction(params);
    if (transaction.state === -1 || transaction.state === -2) return this.cancelResult(transaction);
    if (transaction.state === 2) {
      // Goods/services were already delivered; refunds go through support.
      throw new PaymeError(PaymeCode.CannotCancel);
    }
    const reason = typeof params.reason === 'number' ? params.reason : null;
    await this.payments.applyEvent(
      PaymentProviderKey.PAYME,
      {
        eventId: `payme:${transaction.id}:cancel`,
        paymentId: transaction.paymentId,
        type: 'cancelled',
        failureCode: `payme_${reason ?? 'cancelled'}`,
      },
      'webhook',
    );
    await this.prisma.paymeTransaction.updateMany({
      where: { id: transaction.id, state: 1 },
      data: { state: -1, reason, cancelTime: BigInt(Date.now()) },
    });
    return this.cancelResult(await this.transaction(params));
  }

  private async check(params: Record<string, unknown>) {
    const t = await this.transaction(params);
    return {
      create_time: Number(t.createTime),
      perform_time: Number(t.performTime ?? 0),
      cancel_time: Number(t.cancelTime ?? 0),
      transaction: t.id,
      state: t.state,
      reason: t.reason,
    };
  }

  private async statement(params: Record<string, unknown>) {
    const from = Number(params.from);
    const to = Number(params.to);
    if (!Number.isFinite(from) || !Number.isFinite(to)) throw new PaymeError(PaymeCode.InvalidRequest);
    const rows = await this.prisma.paymeTransaction.findMany({
      where: { createTime: { gte: BigInt(Math.trunc(from)), lte: BigInt(Math.trunc(to)) } },
      orderBy: { createTime: 'asc' },
      take: 1000,
    });
    return {
      transactions: rows.map((t) => ({
        id: t.id,
        time: Number(t.createTime),
        amount: Number(t.amountMinor),
        account: { order_id: t.paymentId },
        create_time: Number(t.createTime),
        perform_time: Number(t.performTime ?? 0),
        cancel_time: Number(t.cancelTime ?? 0),
        transaction: t.id,
        state: t.state,
        reason: t.reason,
      })),
    };
  }

  // ─────────────────────────────────────────────────────── helpers

  private transactionId(params: Record<string, unknown>): string {
    const id = params.id;
    if (typeof id !== 'string' || id.length === 0 || id.length > 64) {
      throw new PaymeError(PaymeCode.InvalidRequest);
    }
    return id;
  }

  private async transaction(params: Record<string, unknown>): Promise<PaymeTransaction> {
    const found = await this.prisma.paymeTransaction.findUnique({
      where: { id: this.transactionId(params) },
    });
    if (!found) throw new PaymeError(PaymeCode.TransactionNotFound);
    return found;
  }

  /** Validates account and amount; returns the (optionally row-locked) payment. */
  private async payableOrder(
    db: PrismaService | Tx,
    params: Record<string, unknown>,
    options: { lock?: boolean } = {},
  ): Promise<Payment> {
    const account = isRecord(params.account) ? params.account : {};
    const orderId = account.order_id;
    if (typeof orderId !== 'string' || !/^[0-9a-f-]{36}$/i.test(orderId)) {
      throw new PaymeError(PaymeCode.OrderNotFound, 'order_id');
    }
    if (options.lock) await db.$queryRaw`SELECT 1 FROM "Payment" WHERE "id" = ${orderId}::uuid FOR UPDATE`;
    const payment = await db.payment.findUnique({ where: { id: orderId } });
    if (!payment || payment.provider !== PaymentProviderKey.PAYME) {
      throw new PaymeError(PaymeCode.OrderNotFound, 'order_id');
    }
    const amount = params.amount;
    if (
      typeof amount !== 'number' ||
      !Number.isSafeInteger(amount) ||
      BigInt(amount) !== payment.amountMinor
    ) {
      throw new PaymeError(PaymeCode.InvalidAmount, 'amount');
    }
    if (payment.status !== PaymentStatus.CREATED && payment.status !== PaymentStatus.PENDING) {
      throw new PaymeError(PaymeCode.OrderUnavailable, 'order_id');
    }
    return payment;
  }

  private expired(t: PaymeTransaction, now: number): boolean {
    return now - Number(t.createTime) > PAYME_TIMEOUT_MS;
  }

  /**
   * reason 4 = "transaction timed out" in the Payme reason list. Only the
   * Payme transaction ends; the order stays payable through a new one.
   */
  private async expire(tx: Tx, t: PaymeTransaction, now: number): Promise<void> {
    await tx.paymeTransaction.update({
      where: { id: t.id },
      data: { state: -1, reason: 4, cancelTime: BigInt(now) },
    });
  }

  private createResult(t: PaymeTransaction) {
    return { create_time: Number(t.createTime), transaction: t.id, state: t.state };
  }

  private performResult(t: PaymeTransaction) {
    return { transaction: t.id, perform_time: Number(t.performTime ?? 0), state: t.state };
  }

  private cancelResult(t: PaymeTransaction) {
    return { transaction: t.id, cancel_time: Number(t.cancelTime ?? 0), state: t.state };
  }
}
