/**
 * Invite / password-reset / access emails and their sender. Pure (no I/O) so it can be unit-tested; the API routes
 * send the result through lib/email/send.ts. Who the email comes from is decided in the database
 * (fnd_email_sender_get): staff hear from OrderNexa, customers from their bakery.
 */
export interface Sender { sender_name: string | null; sender_address: string | null; reply_to: string | null }
export interface Email { from: string; to: string; replyTo?: string; subject: string; html: string; text: string }

/** The OrderNexa address used when a tenancy has no verified address of its own. */
export const defaultFromAddress = () => process.env.ORDERNEXA_EMAIL_FROM || 'invites@ordernexa.com';

const quoteName = (n: string) => `"${n.replace(/["\\\r\n]/g, '')}"`;
export function fromHeader(s: Sender, fallbackAddress: string): string {
  return `${quoteName(s.sender_name || 'OrderNexa')} <${s.sender_address || fallbackAddress}>`;
}

const esc = (v: string) => v.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function layout(heading: string, paragraphs: string[], button: { label: string; href: string }, footer: string): string {
  return `<div style="font-family:Arial,Helvetica,sans-serif;max-width:520px;margin:0 auto;color:#222;line-height:1.5">
<h2 style="font-size:20px;margin:24px 0 12px">${esc(heading)}</h2>
${paragraphs.map((p) => `<p style="margin:0 0 12px">${esc(p)}</p>`).join('\n')}
<p style="margin:20px 0"><a href="${esc(button.href)}" style="background:#1f2937;color:#fff;text-decoration:none;padding:10px 18px;border-radius:6px;display:inline-block">${esc(button.label)}</a></p>
<p style="margin:0 0 12px;font-size:12px;color:#666">If the button does not work, copy this address into your browser:<br>${esc(button.href)}</p>
<p style="margin:24px 0 0;font-size:12px;color:#888">${esc(footer)}</p></div>`;
}

interface Who { to: string; userName: string | null; tenantName: string; sender: Sender; fallbackAddress: string }

function build(w: Who, subject: string, heading: string, paragraphs: string[], button: { label: string; href: string }, footer: string): Email {
  const greeting = `Hello${w.userName && !w.userName.includes('@') ? ` ${w.userName}` : ''},`;
  const body = [greeting, ...paragraphs];
  return {
    from: fromHeader(w.sender, w.fallbackAddress),
    to: w.to,
    ...(w.sender.reply_to ? { replyTo: w.sender.reply_to } : {}),
    subject,
    html: layout(heading, body, button, footer),
    text: `${body.join('\n\n')}\n\n${button.label}: ${button.href}\n\n${footer}`,
  };
}

/** First invite (or a resend before the person ever signed in): the link lets them choose a password. */
export function inviteEmail(w: Who, link: string): Email {
  return build(w, `You're invited to ${w.tenantName} on OrderNexa`, `Welcome to ${w.tenantName}`,
    [`${w.tenantName} has set up an OrderNexa account for you. Choose a password to get started.`],
    { label: 'Choose your password', href: link },
    'This link works once and expires in 24 hours. If it has expired, ask for a new invite.');
}

/** The person already has a login (e.g. at another company): no password change, just where to sign in. */
export function accessEmail(w: Who, signInUrl: string): Email {
  return build(w, `You now have access to ${w.tenantName} on OrderNexa`, `Access to ${w.tenantName}`,
    [`You can now sign in to ${w.tenantName} with your existing OrderNexa email and password.`],
    { label: 'Sign in', href: signInUrl },
    'Forgot your password? Use "Forgot password" on the sign-in page.');
}

export function resetEmail(w: Who, link: string): Email {
  return build(w, 'Reset your OrderNexa password', 'Reset your password',
    ['We received a request to reset your password. If it was not you, you can ignore this email.'],
    { label: 'Choose a new password', href: link },
    'This link works once and expires in 24 hours.');
}

/** The address the request came in on, subdomain included (request.url can lose it behind Next's dev server and proxies). */
export function requestOrigin(request: Request): string {
  const url = new URL(request.url);
  const host = request.headers.get('x-forwarded-host') || request.headers.get('host') || url.host;
  const proto = (request.headers.get('x-forwarded-proto') || url.protocol.replace(':', '')).split(',')[0].trim();
  return `${proto}://${host}`;
}

/** Our own landing page for a token from auth.admin.generateLink: the token is used only when the person submits. */
export function acceptLink(origin: string, tokenHash: string, type: 'invite' | 'recovery'): string {
  return `${origin}/auth/accept?type=${type}&token_hash=${encodeURIComponent(tokenHash)}`;
}
