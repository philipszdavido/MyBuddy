import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Job } from 'bullmq';
import { createTransport, Transporter } from 'nodemailer';
import type { Env } from '../config/env';
import { EmailJob, Q } from '../queues/queues';

const TEMPLATES: Record<EmailJob['template'], { subject: string; text: string }> = {
  'account-deleted': {
    subject: 'Your MyBuddy account has been deleted',
    text: 'Your MyBuddy account and its data have been deleted, as you requested.\n\nIf you did not request this, contact support.',
  },
  'report-received': {
    subject: 'We received your report',
    text: 'Thanks for helping keep MyBuddy safe. Our team will review your report.',
  },
};

/**
 * Transactional email over SMTP (any provider: SES, Postmark, Mailgun…), configured with SMTP_URL and
 * EMAIL_FROM. Auth emails (verification, password reset) are sent by Firebase Auth, not here. When SMTP is
 * not configured the job completes as "skipped" so environments without email still work.
 */
@Processor(Q.email, { concurrency: 5 })
export class EmailProcessor extends WorkerHost {
  private readonly logger = new Logger(EmailProcessor.name);
  private readonly transport?: Transporter;
  private readonly from: string;

  constructor(config: ConfigService<Env, true>) {
    super();
    const url = config.get('SMTP_URL', { infer: true });
    this.from = config.get('EMAIL_FROM', { infer: true }) ?? 'MyBuddy <no-reply@mybuddy.app>';
    if (url) this.transport = createTransport(url);
  }

  async process(job: Job<EmailJob>): Promise<{ status: 'sent' | 'skipped' }> {
    if (!this.transport) {
      this.logger.warn(`email ${job.data.template} not sent: SMTP_URL is not configured`);
      return { status: 'skipped' };
    }
    const t = TEMPLATES[job.data.template];
    await this.transport.sendMail({ from: this.from, to: job.data.to, subject: t.subject, text: t.text });
    return { status: 'sent' };
  }
}
