import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Patch, Query, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import type { Request } from 'express';
import { AllowSuspended, AuthContext, CurrentUser, SensitiveAction } from '../common/decorators/auth.decorators';
import { UpdateProfileDto, UpdateSettingsDto, UsernameQuery } from './users.dto';
import { UsersService } from './users.service';

@ApiTags('users')
@ApiBearerAuth()
@Controller('users')
export class UsersController {
  constructor(private readonly users: UsersService) {}

  @Get('me')
  @AllowSuspended()
  @ApiOperation({ summary: 'Own profile, private fields and settings. Provisions the account on first call.' })
  me(@CurrentUser() auth: AuthContext) {
    return this.users.me(auth.userId);
  }

  @Patch('me')
  @ApiOperation({ summary: 'Edit own profile (username, display name, bio, avatar, privacy, …)' })
  updateMe(@CurrentUser() auth: AuthContext, @Body() dto: UpdateProfileDto) {
    return this.users.updateMe(auth.userId, dto);
  }

  @Patch('me/settings')
  updateSettings(@CurrentUser() auth: AuthContext, @Body() dto: UpdateSettingsDto) {
    return this.users.updateSettings(auth.userId, dto);
  }

  @Delete('me')
  @HttpCode(202)
  @AllowSuspended()
  @SensitiveAction()
  @ApiOperation({ summary: 'Delete the account and all its data. The client must re-authenticate first (fresh token).' })
  async deleteMe(@CurrentUser() auth: AuthContext, @Req() req: Request & { id?: string }) {
    await this.users.requestDeletion(auth, req.id ? String(req.id) : undefined);
    return { status: 'scheduled' };
  }

  @Get('username-available')
  usernameAvailable(@Query() q: UsernameQuery) {
    return this.users.usernameAvailable(q.username);
  }

  @Get('id/:id')
  byId(@CurrentUser() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.users.byId(auth.userId, id);
  }

  @Get(':username')
  byUsername(@CurrentUser() auth: AuthContext, @Param('username') username: string) {
    return this.users.byUsername(auth.userId, username);
  }
}
