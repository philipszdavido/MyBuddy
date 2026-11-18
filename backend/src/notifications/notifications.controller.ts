import { Body, Controller, Delete, Get, HttpCode, Module, Param, ParseUUIDPipe, Patch, Put, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { NotificationType } from '@prisma/client';
import { Transform, Type } from 'class-transformer';
import { ArrayMaxSize, IsArray, IsBoolean, IsEnum, IsIn, IsOptional, IsString, MaxLength, ValidateNested } from 'class-validator';
import { AuthContext, CurrentUser } from '../common/decorators/auth.decorators';
import { PageQuery } from '../common/pagination/cursor';
import { NotificationsService } from './notifications.service';

class InboxQuery extends PageQuery {
  @ApiPropertyOptional() @IsOptional() @Transform(({ value }) => value === 'true' || value === true) @IsBoolean()
  unread?: boolean;
}

class PreferenceDto {
  @ApiProperty({ enum: NotificationType }) @IsEnum(NotificationType) type: NotificationType;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() push?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() inApp?: boolean;
}

class PreferencesDto {
  @ApiProperty({ type: [PreferenceDto] })
  @IsArray() @ArrayMaxSize(20) @ValidateNested({ each: true }) @Type(() => PreferenceDto)
  preferences: PreferenceDto[];
}

class DeviceDto {
  @ApiProperty({ description: 'FCM registration token' }) @IsString() @MaxLength(4096) fcmToken: string;
  @ApiProperty({ enum: ['ios', 'android', 'web'] }) @IsIn(['ios', 'android', 'web']) platform: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(32) appVersion?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(16) locale?: string;
}

@ApiTags('notifications')
@ApiBearerAuth()
@Controller()
export class NotificationsController {
  constructor(private readonly notifications: NotificationsService) {}

  @Get('notifications')
  list(@CurrentUser() a: AuthContext, @Query() q: InboxQuery) {
    return this.notifications.list(a.userId, q.cursor, q.limit, q.unread ?? false);
  }

  @Get('notifications/unread-count')
  async unread(@CurrentUser() a: AuthContext) {
    return { unread: await this.notifications.unreadCount(a.userId) };
  }

  @Patch('notifications/read-all')
  readAll(@CurrentUser() a: AuthContext) {
    return this.notifications.markAllRead(a.userId);
  }

  @Patch('notifications/:id/read')
  @HttpCode(204)
  async read(@CurrentUser() a: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    await this.notifications.markRead(a.userId, id);
  }

  @Get('notifications/preferences')
  preferences(@CurrentUser() a: AuthContext) {
    return this.notifications.preferences(a.userId);
  }

  @Patch('notifications/preferences')
  setPreferences(@CurrentUser() a: AuthContext, @Body() dto: PreferencesDto) {
    return this.notifications.setPreferences(a.userId, dto.preferences);
  }

  @Put('devices/:installationId')
  @HttpCode(204)
  @ApiOperation({ summary: 'Register or refresh this installation’s push token (call on launch and on FCM token refresh)' })
  async register(@CurrentUser() a: AuthContext, @Param('installationId') installationId: string, @Body() dto: DeviceDto) {
    await this.notifications.registerDevice(a.userId, { installationId: installationId.slice(0, 64), ...dto });
  }

  @Delete('devices/:installationId')
  @HttpCode(204)
  @ApiOperation({ summary: 'Remove this installation’s push token (logout)' })
  async unregister(@CurrentUser() a: AuthContext, @Param('installationId') installationId: string) {
    await this.notifications.unregisterDevice(a.userId, installationId);
  }
}

@Module({ controllers: [NotificationsController], providers: [NotificationsService], exports: [NotificationsService] })
export class NotificationsModule {}
