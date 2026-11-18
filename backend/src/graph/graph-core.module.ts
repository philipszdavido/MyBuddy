import { Global, Module } from '@nestjs/common';
import { RelationshipService } from './relationship.service';

/** Privacy primitives shared by every module (no controllers, no dependencies beyond Prisma). */
@Global()
@Module({ providers: [RelationshipService], exports: [RelationshipService] })
export class GraphCoreModule {}
