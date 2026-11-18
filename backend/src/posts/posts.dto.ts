import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { PostAudience } from '@prisma/client';
import { ArrayMaxSize, IsArray, IsBoolean, IsEnum, IsIn, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';

export const MAX_POST_LENGTH = 2000; // matches the iOS client's FeedViewModel.maxPostLength
export const MAX_POST_MEDIA = 10;

export class CreatePostDto {
  @ApiPropertyOptional({ description: 'Client-generated id; retrying with the same id returns the same post.' })
  @IsOptional() @IsString() @MaxLength(64)
  clientId?: string;

  @ApiPropertyOptional({ maxLength: MAX_POST_LENGTH })
  @IsOptional() @IsString() @MaxLength(MAX_POST_LENGTH)
  text?: string;

  @ApiPropertyOptional({ type: [String], description: 'Media ids from POST /media/upload-url (purpose POST), in display order' })
  @IsOptional() @IsArray() @ArrayMaxSize(MAX_POST_MEDIA) @IsUUID('4', { each: true })
  mediaIds?: string[];

  @ApiPropertyOptional({ enum: PostAudience, default: PostAudience.CONTACTS })
  @IsOptional() @IsEnum(PostAudience)
  audience?: PostAudience;

  @ApiPropertyOptional({ description: 'Save as a draft instead of publishing' })
  @IsOptional() @IsBoolean()
  draft?: boolean;

  @ApiPropertyOptional({ description: 'Quote another (public) post' })
  @IsOptional() @IsUUID()
  quoteOfId?: string;
}

export class UpdatePostDto {
  @ApiPropertyOptional({ maxLength: MAX_POST_LENGTH, nullable: true })
  @IsOptional() @IsString() @MaxLength(MAX_POST_LENGTH)
  text?: string | null;

  @ApiPropertyOptional({ enum: PostAudience })
  @IsOptional() @IsEnum(PostAudience)
  audience?: PostAudience;
}

export class ShareDto {
  @ApiProperty({ enum: ['share_sheet', 'copy_link', 'message'] })
  @IsIn(['share_sheet', 'copy_link', 'message'])
  channel: 'share_sheet' | 'copy_link' | 'message';
}
