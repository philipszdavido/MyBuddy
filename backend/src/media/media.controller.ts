import { Body, Controller, Delete, Get, HttpCode, Module, Param, ParseUUIDPipe, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiProperty, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { MediaPurpose } from '@prisma/client';
import { IsEnum, IsInt, IsString, IsUUID, Max, MaxLength, Min } from 'class-validator';
import { AuthContext, CurrentUser } from '../common/decorators/auth.decorators';
import { MediaService } from './media.service';

class UploadUrlDto {
  @ApiProperty({ enum: MediaPurpose }) @IsEnum(MediaPurpose)
  purpose: MediaPurpose;

  @ApiProperty({ example: 'image/jpeg', description: 'image/jpeg, image/png, image/webp, video/mp4, video/quicktime' })
  @IsString() @MaxLength(100)
  mimeType: string;

  @ApiProperty({ description: 'Exact byte length of the file that will be uploaded' })
  @IsInt() @Min(1) @Max(1024 * 1024 * 1024)
  sizeBytes: number;
}

class CompleteDto {
  @ApiProperty() @IsUUID()
  mediaId: string;
}

@ApiTags('media')
@ApiBearerAuth()
@Controller('media')
export class MediaController {
  constructor(private readonly media: MediaService) {}

  @Post('upload-url')
  @Throttle({ default: { limit: 60, ttl: 60_000 } })
  @ApiOperation({ summary: 'Get a presigned R2 PUT URL for a new media item' })
  uploadUrl(@CurrentUser() a: AuthContext, @Body() dto: UploadUrlDto) {
    return this.media.createUpload(a.userId, dto.purpose, dto.mimeType, dto.sizeBytes);
  }

  @Post('complete')
  @ApiOperation({ summary: 'Confirm the upload; the server verifies it and starts processing' })
  complete(@CurrentUser() a: AuthContext, @Body() dto: CompleteDto) {
    return this.media.complete(a.userId, dto.mediaId);
  }

  @Get(':id')
  @ApiOperation({ summary: 'Processing status and URLs of one of your media items' })
  get(@CurrentUser() a: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.media.get(a.userId, id);
  }

  @Delete(':id')
  @HttpCode(204)
  async remove(@CurrentUser() a: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    await this.media.remove(a.userId, id);
  }
}

@Module({ controllers: [MediaController], providers: [MediaService], exports: [MediaService] })
export class MediaModule {}
