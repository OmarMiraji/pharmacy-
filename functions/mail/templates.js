function escapeHtml(value) {
  return String(value ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
}

function formatDate(value) {
  if (!value) return "";
  const date = value.toDate ? value.toDate() : new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return `${date.getDate()}/${date.getMonth() + 1}/${date.getFullYear()}`;
}

function roleLabel(role) {
  const key = String(role || "").toLowerCase();
  if (key === "admin") return "Shop admin";
  if (key === "pharmacist") return "Pharmacist";
  if (key === "cashier") return "Cashier";
  if (key === "storekeeper") return "Storekeeper";
  return "Staff";
}

function planLabel(plan) {
  const key = String(plan || "").toLowerCase();
  if (key === "monthly") return "Monthly";
  if (key === "quarterly") return "Quarterly";
  if (key === "biannual") return "6 months";
  if (key === "yearly") return "Yearly";
  if (key === "trial") return "Free trial";
  return plan || "Paid plan";
}

function layout({title, intro, rows, extraHtml}) {
  const details = (rows || [])
      .filter((row) => row && row.value)
      .map((row) => `
        <tr>
          <td style="padding:8px 0;color:#68807d;font-size:13px;width:160px;">${escapeHtml(row.label)}</td>
          <td style="padding:8px 0;color:#183b3b;font-size:13px;font-weight:700;">${escapeHtml(row.value)}</td>
        </tr>`)
      .join("");
  return `
  <div style="background:#f4f7f6;padding:24px 12px;font-family:Arial,sans-serif;">
    <div style="max-width:560px;margin:0 auto;background:#ffffff;border-radius:16px;overflow:hidden;border:1px solid #d7e7e4;">
      <div style="background:#0f766e;padding:22px 28px;">
        <div style="color:#e7c46c;font-size:12px;letter-spacing:1.4px;font-weight:700;">PHARMSPECIO</div>
        <div style="color:#ffffff;font-size:22px;font-weight:800;margin-top:6px;">${escapeHtml(title)}</div>
      </div>
      <div style="padding:28px;">
        <p style="margin:0 0 16px;color:#183b3b;font-size:15px;line-height:1.55;">${intro}</p>
        ${details ? `<table style="width:100%;border-collapse:collapse;margin:8px 0 18px;">${details}</table>` : ""}
        ${extraHtml || ""}
        <p style="margin:22px 0 0;color:#68807d;font-size:12px;line-height:1.5;">
          Open the PharmSpecio Windows app and sign in with this email. Keep this message private.
        </p>
      </div>
      <div style="padding:14px 28px;background:#f7fbfa;color:#68807d;font-size:11px;">
        PharmSpecio pharmacy software · Do not reply to this email.
      </div>
    </div>
  </div>`;
}

function welcomeAdmin({name, email, shopName, trialEndsAt, isTrial}) {
  const trialLine = isTrial
    ? `Your shop is on a <b>7-day free trial</b>${trialEndsAt ? `, until <b>${escapeHtml(formatDate(trialEndsAt))}</b>` : ""}. You can enter medicines, sales, and staff during the trial.`
    : "Your shop login is ready.";
  return {
    subject: `Welcome to PharmSpecio${shopName ? ` — ${shopName}` : ""}`,
    text: [
      `Hello ${name || "there"},`,
      "Welcome to PharmSpecio.",
      trialLine.replace(/<[^>]+>/g, ""),
      shopName ? `Shop: ${shopName}` : "",
      `Login email: ${email}`,
      "Role: Shop admin",
      "Open the PharmSpecio Windows app and sign in with this email and the password that was set for you.",
    ].filter(Boolean).join("\n"),
    html: layout({
      title: "Welcome to PharmSpecio",
      intro: `Hello ${escapeHtml(name || "there")},<br/><br/>Your shop admin login is ready. ${trialLine}`,
      rows: [
        {label: "Shop", value: shopName},
        {label: "Login email", value: email},
        {label: "Role", value: "Shop admin"},
        {label: isTrial ? "Trial" : "Access", value: isTrial ? `7-day trial${trialEndsAt ? ` · ends ${formatDate(trialEndsAt)}` : ""}` : "Active"},
      ],
    }),
  };
}

function welcomeStaff({name, email, shopName, role}) {
  return {
    subject: `Your PharmSpecio login${shopName ? ` — ${shopName}` : ""}`,
    text: [
      `Hello ${name || "there"},`,
      "A shop login has been created for you on PharmSpecio.",
      shopName ? `Shop: ${shopName}` : "",
      `Login email: ${email}`,
      `Role: ${roleLabel(role)}`,
      "Sign in on the PharmSpecio Windows app with this email and the password your shop admin gave you.",
    ].filter(Boolean).join("\n"),
    html: layout({
      title: "Your PharmSpecio login",
      intro: `Hello ${escapeHtml(name || "there")},<br/><br/>Your shop admin created a PharmSpecio login for you.`,
      rows: [
        {label: "Shop", value: shopName},
        {label: "Login email", value: email},
        {label: "Role", value: roleLabel(role)},
      ],
    }),
  };
}

function subscriptionActivated({name, email, shopName, plan, expiresAt}) {
  return {
    subject: `PharmSpecio account activated${shopName ? ` — ${shopName}` : ""}`,
    text: [
      `Hello ${name || "there"},`,
      "Your PharmSpecio subscription is now active. The shop is unlocked for full use.",
      shopName ? `Shop: ${shopName}` : "",
      `Plan: ${planLabel(plan)}`,
      expiresAt ? `Valid until: ${formatDate(expiresAt)}` : "",
      `Login email: ${email}`,
    ].filter(Boolean).join("\n"),
    html: layout({
      title: "Account activated",
      intro: `Hello ${escapeHtml(name || "there")},<br/><br/>Your PharmSpecio subscription is <b>active</b>. The shop is unlocked for full use.`,
      rows: [
        {label: "Shop", value: shopName},
        {label: "Plan", value: planLabel(plan)},
        {label: "Valid until", value: formatDate(expiresAt)},
        {label: "Login email", value: email},
      ],
    }),
  };
}

function trialEnding({name, email, shopName, trialEndsAt, daysLeft}) {
  const days = daysLeft === 1 ? "1 day" : `${daysLeft} days`;
  return {
    subject: `Trial ending soon${shopName ? ` — ${shopName}` : ""}`,
    text: [
      `Hello ${name || "there"},`,
      `Your PharmSpecio free trial has ${days} remaining.`,
      trialEndsAt ? `Trial ends: ${formatDate(trialEndsAt)}` : "",
      "Subscribe and activate your plan to keep entering sales and stock without interruption.",
    ].filter(Boolean).join("\n"),
    html: layout({
      title: "Trial ending soon",
      intro: `Hello ${escapeHtml(name || "there")},<br/><br/>Your free trial has <b>${escapeHtml(days)} remaining</b>. Subscribe and activate a plan to keep full access.`,
      rows: [
        {label: "Shop", value: shopName},
        {label: "Trial ends", value: formatDate(trialEndsAt)},
        {label: "Login email", value: email},
      ],
    }),
  };
}

module.exports = {
  welcomeAdmin,
  welcomeStaff,
  subscriptionActivated,
  trialEnding,
  formatDate,
  planLabel,
};
