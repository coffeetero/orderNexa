import type { Email } from './user-emails';

/**
 * Sends one email through Resend (https://resend.com). Without RESEND_API_KEY nothing is sent and
 * { sent: false } comes back, so local development works without a mail account.
 */
export async function sendEmail(email: Email): Promise<{ sent: boolean; error?: string }> {
  const key = process.env.RESEND_API_KEY;
  if (!key) return { sent: false, error: 'Email is not set up (RESEND_API_KEY)' };
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      from: email.from, to: [email.to], subject: email.subject, html: email.html, text: email.text,
      ...(email.replyTo ? { reply_to: email.replyTo } : {}),
    }),
  });
  if (res.ok) return { sent: true };
  const detail = await res.text().catch(() => '');
  return { sent: false, error: `Email provider refused the message (${res.status}) ${detail.slice(0, 200)}` };
}
