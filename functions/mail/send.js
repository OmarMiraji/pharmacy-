const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const {writeAlert} = require("../security/store");

// Gmail sender saved by the super admin in the app (mail_settings/smtp, super-admin-only rules);
// environment variables still win when set.
async function mailSettings() {
  let stored = {};
  try {
    const snap = await admin.firestore().collection("mail_settings").doc("smtp").get();
    if (snap.exists) stored = snap.data() || {};
  } catch (error) {
    console.warn("Could not read mail_settings/smtp", error.message);
  }
  const user = String(process.env.MAIL_SMTP_USER || stored.user || "").trim();
  return {
    resendKey: String(process.env.RESEND_API_KEY || "").trim(),
    smtpHost: String(process.env.MAIL_SMTP_HOST || "smtp.gmail.com").trim(),
    smtpPort: Number(process.env.MAIL_SMTP_PORT || 587),
    smtpUser: user,
    smtpPass: String(process.env.MAIL_SMTP_PASS || stored.pass || "").replace(/\s+/g, ""),
    from: String(process.env.MAIL_FROM || `PharmSpecio <${user}>`).trim(),
  };
}

async function sendWithResend({settings, from, to, subject, html, text}) {
  const key = settings.resendKey;
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

async function sendWithSmtp({settings, from, to, subject, html, text}) {
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
  const settings = await mailSettings();
  const from = settings.from;
  let sent = false;
  let provider = "none";
  let errorMessage = "";
  try {
    sent = await sendWithResend({settings, from, to: email, subject, html, text});
    if (sent) provider = "resend";
    if (!sent) {
      sent = await sendWithSmtp({settings, from, to: email, subject, html, text});
      if (sent) provider = "smtp";
    }
    if (!sent) {
      errorMessage = "Email is not set up. Super admin: save the Gmail sender under Email settings.";
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
    if (kind !== "security_alert") {
      try {
        await writeAlert({
          type: "email_failed",
          severity: "warning",
          title: "Emails are not being sent",
          message: `A ${kind || "notice"} email to ${email} failed: ${errorMessage}`.slice(0, 400),
          dedupeKey: `email_failed_${new Date().toISOString().slice(0, 10)}`,
        });
      } catch (error) {
        console.warn("Could not record email alert", error.message);
      }
    }
    throw new Error(errorMessage || "Could not send email.");
  }
}

module.exports = {sendEmail, mailSettings};
