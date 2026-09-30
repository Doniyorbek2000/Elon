import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';

import { PrismaService } from '../../infra/prisma.service';

@Injectable()
export class AdminService {
  constructor(private readonly prisma: PrismaService) {}

  /** Every admin mutation is recorded with actor, entity and payload. */
  async audit(actorId: string, action: string, entity: string, entityId: string | null, data?: unknown) {
    await this.prisma.adminAuditLog.create({
      data: {
        actorId,
        action,
        entity,
        entityId,
        data:
          data === undefined
            ? undefined
            : (JSON.parse(
                JSON.stringify(data, (_k, v: unknown) => (typeof v === 'bigint' ? v.toString() : v)),
              ) as Prisma.InputJsonValue),
      },
    });
  }
}
