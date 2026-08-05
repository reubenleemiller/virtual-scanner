const RATE_LIMIT_WINDOW_MS = 10 * 60 * 1000;
const RATE_LIMIT_MAX = 5;
const rateLimits = new Map();

const escapeHtml = (value) =>
  String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");

const isEmail = (value) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);

function setCors(req, res) {
  const allowedOrigin = process.env.CONTACT_ALLOWED_ORIGIN || "*";
  const origin = req.headers.origin;
  res.setHeader("Access-Control-Allow-Origin", allowedOrigin === "*" ? "*" : origin === allowedOrigin ? origin : allowedOrigin);
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "content-type");
}

function checkRateLimit(req) {
  const ip =
    req.headers["x-forwarded-for"]?.split(",")[0]?.trim() ||
    req.headers["x-real-ip"] ||
    "unknown";
  const now = Date.now();
  const bucket = rateLimits.get(ip) || { count: 0, resetAt: now + RATE_LIMIT_WINDOW_MS };

  if (bucket.resetAt <= now) {
    bucket.count = 0;
    bucket.resetAt = now + RATE_LIMIT_WINDOW_MS;
  }

  bucket.count += 1;
  rateLimits.set(ip, bucket);
  return bucket.count <= RATE_LIMIT_MAX;
}

function confirmationTemplate({ name, subject, message }) {
  const safeName = escapeHtml(name);
  const safeSubject = escapeHtml(subject);
  const safeMessage = escapeHtml(message).replaceAll("\n", "<br />");

  return `<!doctype html>
<html>
  <body style="margin:0;background:#f4f9fc;font-family:Inter,Segoe UI,Arial,sans-serif;color:#122033;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f4f9fc;padding:32px 16px;">
      <tr>
        <td align="center">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:640px;background:#ffffff;border:1px solid #d9e8f0;border-radius:12px;overflow:hidden;">
            <tr>
              <td style="background:linear-gradient(135deg,#0e9dd9,#2bd4a7);padding:28px 32px;color:#ffffff;">
                <h1 style="margin:0;font-size:24px;line-height:1.25;">Thanks for reaching out, ${safeName}</h1>
                <p style="margin:8px 0 0;font-size:15px;opacity:.95;">Your Virtual Scanner message was received.</p>
              </td>
            </tr>
            <tr>
              <td style="padding:28px 32px;">
                <p style="margin:0 0 18px;line-height:1.6;">I will review your message and follow up when I can.</p>
                <div style="border:1px solid #d9e8f0;border-radius:10px;padding:18px;background:#f8fcff;">
                  <p style="margin:0 0 10px;font-size:12px;letter-spacing:.12em;text-transform:uppercase;color:#0e9dd9;font-weight:700;">Subject</p>
                  <p style="margin:0 0 18px;font-weight:700;">${safeSubject}</p>
                  <p style="margin:0 0 10px;font-size:12px;letter-spacing:.12em;text-transform:uppercase;color:#0e9dd9;font-weight:700;">Message</p>
                  <p style="margin:0;line-height:1.6;color:#526277;">${safeMessage}</p>
                </div>
                <p style="margin:22px 0 0;font-size:13px;color:#526277;">This confirmation was sent automatically by the Virtual Scanner contact form.</p>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`;
}

function ownerTemplate({ name, email, subject, message }) {
  return `<h2>New Virtual Scanner contact message</h2>
<p><strong>Name:</strong> ${escapeHtml(name)}</p>
<p><strong>Email:</strong> ${escapeHtml(email)}</p>
<p><strong>Subject:</strong> ${escapeHtml(subject)}</p>
<p><strong>Message:</strong></p>
<p>${escapeHtml(message).replaceAll("\n", "<br />")}</p>`;
}

async function sendResendEmail(payload) {
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      authorization: `Bearer ${process.env.RESEND_API_KEY}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const details = await response.text();
    throw new Error(`Resend error ${response.status}: ${details}`);
  }

  return response.json();
}

export default async function handler(req, res) {
  setCors(req, res);

  if (req.method === "OPTIONS") return res.status(204).end();
  if (req.method !== "POST") return res.status(405).json({ error: "Method not allowed." });

  try {
    if (!process.env.RESEND_API_KEY || !process.env.CONTACT_TO_EMAIL || !process.env.RESEND_FROM_EMAIL) {
      return res.status(500).json({ error: "Contact service is not configured yet." });
    }

    if (!checkRateLimit(req)) {
      return res.status(429).json({ error: "Too many messages. Please wait a few minutes and try again." });
    }

    const body = typeof req.body === "string" ? JSON.parse(req.body || "{}") : req.body || {};
    const name = String(body.name || "").trim();
    const email = String(body.email || "").trim();
    const subject = String(body.subject || "").trim();
    const message = String(body.message || "").trim();
    const website = String(body.website || "").trim();

    if (website) return res.status(200).json({ ok: true });
    if (name.length < 2 || name.length > 120) return res.status(400).json({ error: "Please enter your name." });
    if (!isEmail(email) || email.length > 254) return res.status(400).json({ error: "Please enter a valid email address." });
    if (subject.length < 3 || subject.length > 160) return res.status(400).json({ error: "Please enter a subject." });
    if (message.length < 10 || message.length > 5000) return res.status(400).json({ error: "Please enter a message between 10 and 5000 characters." });

    await sendResendEmail({
      from: process.env.RESEND_FROM_EMAIL,
      to: [process.env.CONTACT_TO_EMAIL],
      reply_to: email,
      subject: `Virtual Scanner contact: ${subject}`,
      html: ownerTemplate({ name, email, subject, message }),
    });

    await sendResendEmail({
      from: process.env.RESEND_FROM_EMAIL,
      to: [email],
      subject: "Thanks for contacting Virtual Scanner",
      html: confirmationTemplate({ name, subject, message }),
    });

    return res.status(200).json({ ok: true });
  } catch (error) {
    console.error(error);
    return res.status(500).json({ error: "Message could not be sent. Please try again later." });
  }
}
