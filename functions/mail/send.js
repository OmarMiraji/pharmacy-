const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

function mailSettings() {
  const user = String(process.env.MAIL_SMTP_USER || "aboulonso85@gmail.com").trim();
  return {
    resendKey: String(process.env.RESEND_API_KEY || "").trim(),
    smtpHost: String(process.env.MAIL_SMTP_HOST || "smtp.gmail.com").trim(),
    smtpPort: Number(process.env.MAIL_SMTP_PORT || 587),
    smtpUser: user,
    smtpPass: String(process.env.MAIL_SMTP_PASS || "").replace(/\s+/g, ""),
    from: String(process.env.MAIL_FROM || `PharmSpecio <${user}>`).trim(),
  };
}

async function sendWithResend({from, to, subject, html, text}) {
  const key = mailSettings().resendKey;
  if (!key) return false;
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({from, to: [to], subject, html, text}),
  });
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Resend ${response.status}: ${body}`);
  }
  return true;
}

async function sendWithSmtp({from, to, subject, html, text}) {
  const settings = mailSettings();
  if (!settings.smtpHost || !settings.smtpUser || !settings.smtpPass) return false;
  const transporter = nodemailer.createTransport({
    host: settings.smtpHost,
    port: settings.smtpPort,
    secure: settings.smtpPort === 465,
    auth: {user: settings.smtpUser, pass: settings.smtpPass},
  });
  await transporter.sendMail({from, to, subject, html, text});
  return true;
}

async function sendEmail({to, subject, html, text, kind, meta}) {
  const email = String(to || "").trim().toLowerCase();
  if (!email || !email.includes("@")) {
    throw new Error("A valid email is required.");
  }
  const from = mailSettings().from;
  let sent = false;
  let provider = "none";
  let errorMessage = "";
  try {
    sent = await sendWithResend({from, to: email, subject, html, text});
    if (sent) provider = "resend";
    if (!sent) {
      sent = await sendWithSmtp({from, to: email, subject, html, text});
      if (sent) provider = "smtp";
    }
    if (!sent) {
      errorMessage = "Email provider is not configured (RESEND_API_KEY or MAIL_SMTP_*).";
    }
  } catch (error) {
    errorMessage = String(error && error.message ? error.message : error);
  }

  await admin.firestore().collection("email_log").add({
    to: email,
    subject,
    kind: kind || "notice",
    provider,
    sent,
    error: errorMessage,
    meta: meta || {},
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  if (!sent) {
    throw new Error(errorMessage || "Could not send email.");
  }
}

module.exports = {sendEmail, mailSettings};
