import { Global, Injectable, Logger, Module } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService, Tx } from '../prisma/prisma.service';

export interface AuditEntry {
  actorId?: string | null;
  action: string;
  targetType?: string;
  targetId?: string;
  requestId?: string;
  ip?: string;
  metadata?: Prisma.InputJsonValue;
}

/** Append-only audit trail for sensitive actions. Pass `tx` to record it atomically with the action. */
@Injectable()
export class AuditService {
  private readonly logger = new Logger('Audit');

  constructor(private readonly prisma: PrismaService) {}

  async record(entry: AuditEntry, tx?: Tx): Promise<void> {
    const client = tx ?? this.prisma;
    await client.auditLog.create({ data: { ...entry, actorId: entry.actorId ?? null } });
    this.logger.log({ audit: entry.action, actorId: entry.actorId, targetType: entry.targetType, targetId: entry.targetId });
  }
}

@Global()
@Module({ providers: [AuditService], exports: [AuditService] })
export class AuditModule {}
