import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';

import { env } from '../../config/env';
import { AuthController } from './auth.controller';
import { AuthGuard } from './auth.guard';
import { AuthService } from './auth.service';
import { DevOtpSender, DisabledOtpSender, EskizOtpSender, OTP_SENDER } from './otp-sender';
import { OtpService } from './otp.service';
import { TokenService } from './token.service';

@Module({
  imports: [JwtModule.register({})],
  controllers: [AuthController],
  providers: [
    AuthService,
    OtpService,
    TokenService,
    AuthGuard,
    {
      provide: OTP_SENDER,
      useFactory: () => {
        switch (env().OTP_PROVIDER) {
          case 'eskiz':
            return new EskizOtpSender();
          case 'dev':
            return new DevOtpSender();
          case 'none':
            return new DisabledOtpSender();
        }
      },
    },
  ],
  exports: [TokenService, AuthGuard, AuthService],
})
export class AuthModule {}
