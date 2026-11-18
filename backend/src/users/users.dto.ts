import { ApiPropertyOptional } from '@nestjs/swagger';
import { AccountVisibility, MessagePermission } from '@prisma/client';
import { Transform } from 'class-transformer';
import { IsBoolean, IsEnum, IsOptional, IsString, IsUrl, Matches, MaxLength, MinLength } from 'class-validator';

const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);
const lower = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim().toLowerCase() : value);

export const USERNAME_PATTERN = /^[a-z0-9_.]{3,30}$/;

export class UpdateProfileDto {
  @ApiPropertyOptional({ example: 'ada_l', description: 'Lower-case letters, digits, "_" and "."; 3–30 characters' })
  @IsOptional() @Transform(lower) @Matches(USERNAME_PATTERN, { message: 'username must be 3-30 characters: a-z, 0-9, _ or .' })
  username?: string;

  @ApiPropertyOptional({ maxLength: 50 })
  @IsOptional() @Transform(trim) @IsString() @MinLength(1) @MaxLength(50)
  displayName?: string;

  @ApiPropertyOptional({ maxLength: 160, nullable: true })
  @IsOptional() @Transform(trim) @IsString() @MaxLength(160)
  bio?: string | null;

  @ApiPropertyOptional({ maxLength: 60, nullable: true })
  @IsOptional() @Transform(trim) @IsString() @MaxLength(60)
  location?: string | null;

  @ApiPropertyOptional({ maxLength: 200, nullable: true })
  @IsOptional() @Transform(trim) @IsUrl({ protocols: ['http', 'https'], require_protocol: true }) @MaxLength(200)
  website?: string | null;

  @ApiPropertyOptional({ enum: AccountVisibility })
  @IsOptional() @IsEnum(AccountVisibility)
  visibility?: AccountVisibility;

  /**
   * Self-declared phone number used for contact matching (legacy behaviour). Ignored once the account
   * has a phone number verified through Firebase phone auth.
   */
  @ApiPropertyOptional({ example: '2348012345678' })
  @IsOptional() @Transform(({ value }: { value: unknown }) => (typeof value === 'string' ? value.replace(/\D/g, '') : value))
  @Matches(/^\d{7,15}$/, { message: 'phoneNumber must be 7-15 digits' })
  phoneNumber?: string;

  @ApiPropertyOptional({ description: 'READY media id (purpose AVATAR) or null to remove', nullable: true })
  @IsOptional() @IsString()
  avatarMediaId?: string | null;

  @ApiPropertyOptional({ description: 'READY media id (purpose COVER) or null to remove', nullable: true })
  @IsOptional() @IsString()
  coverMediaId?: string | null;
}

export class UpdateSettingsDto {
  @ApiPropertyOptional() @IsOptional() @IsBoolean()
  showActivityStatus?: boolean;

  @ApiPropertyOptional() @IsOptional() @IsBoolean()
  sendReadReceipts?: boolean;

  @ApiPropertyOptional({ enum: MessagePermission }) @IsOptional() @IsEnum(MessagePermission)
  allowMessagesFrom?: MessagePermission;

  @ApiPropertyOptional() @IsOptional() @IsBoolean()
  discoverable?: boolean;
}

export class UsernameQuery {
  @Transform(lower) @IsString() @MaxLength(30)
  username: string;
}
