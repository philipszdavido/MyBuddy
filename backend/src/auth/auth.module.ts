import { Global, Module } from '@nestjs/common';
import { FirebaseAuthGuard } from './auth.guard';
import { FirebaseTokenVerifier, TokenVerifier } from './token-verifier';
import { UserProvisioningService } from './user-provisioning.service';

@Global()
@Module({
  providers: [
    { provide: TokenVerifier, useClass: FirebaseTokenVerifier },
    UserProvisioningService,
    FirebaseAuthGuard,
  ],
  exports: [TokenVerifier, UserProvisioningService, FirebaseAuthGuard],
})
export class AuthModule {}
