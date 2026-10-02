const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

admin.initializeApp();

function callerIsSuper(caller, token) {
  const role = String((caller && caller.role) || "").trim().toLowerCase();
  return role === "super_admin" || (token && token.role === "super_admin");
}

async function loadCaller(uid) {
  const snap = await admin.firestore().collection("users").doc(uid).get();
  if (!snap.exists) {
    throw new HttpsError("permission-denied", "Your profile was not found.");
  }
  const caller = snap.data() || {};
  if (caller.isActive === false) {
    throw new HttpsError("permission-denied", "This login is disabled.");
  }
  return caller;
}

exports.setUserPassword = onCall({region: "us-central1"}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  const uid = String((request.data && request.data.uid) || "").trim();
  const password = String((request.data && request.data.password) || "");
  if (!uid) {
    throw new HttpsError("invalid-argument", "User is required.");
  }
  if (password.length < 6) {
    throw new HttpsError("invalid-argument", "Password must be at least 6 characters.");
  }
  if (uid === request.auth.uid) {
    throw new HttpsError("failed-precondition", "Change your own password from Settings.");
  }

  const caller = await loadCaller(request.auth.uid);
  const callerRole = String(caller.role || "").trim().toLowerCase();
  const isSuper = callerIsSuper(caller, request.auth.token);

  const targetSnap = await admin.firestore().collection("users").doc(uid).get();
  if (!targetSnap.exists) {
    throw new HttpsError("not-found", "That login profile was not found.");
  }
  const target = targetSnap.data() || {};
  const targetRole = String(target.role || "").trim().toLowerCase();
  if (targetRole === "super_admin") {
    throw new HttpsError("permission-denied", "You cannot set that password here.");
  }

  if (!isSuper) {
    if (callerRole !== "admin") {
      throw new HttpsError(
          "permission-denied",
          "Only the shop admin can set another login password.",
      );
    }
    const shop = String(caller.pharmacyId || "").trim();
    const targetShop = String(target.pharmacyId || "").trim();
    if (!shop || shop !== targetShop) {
      throw new HttpsError("permission-denied", "That staff login is not in your pharmacy.");
    }
    if (targetRole === "admin") {
      throw new HttpsError("permission-denied", "Ask the system administrator to change a shop admin password.");
    }
  }

  await admin.auth().updateUser(uid, {password});
  return {ok: true};
});

exports.createAuthUser = onCall({region: "us-central1"}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  const email = String((request.data && request.data.email) || "").trim().toLowerCase();
  const password = String((request.data && request.data.password) || "");
  const intendedRole = String((request.data && request.data.role) || "cashier").trim().toLowerCase();
  if (!email) {
    throw new HttpsError("invalid-argument", "Email is required.");
  }
  if (password.length < 6) {
    throw new HttpsError("invalid-argument", "Password must be at least 6 characters.");
  }

  const caller = await loadCaller(request.auth.uid);
  const callerRole = String(caller.role || "").trim().toLowerCase();
  const isSuper = callerIsSuper(caller, request.auth.token);

  if (intendedRole === "super_admin" && !isSuper) {
    throw new HttpsError("permission-denied", "You cannot create that login.");
  }
  if (intendedRole === "admin" && !isSuper) {
    throw new HttpsError("permission-denied", "Only the system administrator can create a shop admin login.");
  }
  if (!isSuper) {
    if (callerRole !== "admin") {
      throw new HttpsError("permission-denied", "Only the shop admin can create staff logins.");
    }
    if (!["pharmacist", "cashier", "storekeeper"].includes(intendedRole)) {
      throw new HttpsError("permission-denied", "Shop staff roles are pharmacist, cashier, or storekeeper.");
    }
  }

  try {
    const user = await admin.auth().createUser({
      email,
      password,
      emailVerified: true,
      disabled: false,
    });
    return {uid: user.uid};
  } catch (error) {
    if (error && error.code === "auth/email-already-exists") {
      throw new HttpsError(
          "already-exists",
          "That email already has a login. Use a different email.",
      );
    }
    if (error && error.code === "auth/invalid-email") {
      throw new HttpsError("invalid-argument", "Enter a valid email address.");
    }
    if (error && error.code === "auth/weak-password") {
      throw new HttpsError("invalid-argument", "Password must be at least 6 characters.");
    }
  throw new HttpsError("internal", "Could not create that login. Try again.");
  }
});

exports.recycleAuthUser = onCall({region: "us-central1"}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  const email = String((request.data && request.data.email) || "").trim().toLowerCase();
  const password = String((request.data && request.data.password) || "");
  if (!email || password.length < 6) {
    throw new HttpsError("invalid-argument", "Email and password are required.");
  }
  const caller = await loadCaller(request.auth.uid);
  const callerRole = String(caller.role || "").trim().toLowerCase();
  const isSuper = callerIsSuper(caller, request.auth.token);
  if (!isSuper && callerRole !== "admin") {
    throw new HttpsError("permission-denied", "You cannot restore that login.");
  }
  try {
    const existing = await admin.auth().getUserByEmail(email);
    await admin.auth().updateUser(existing.uid, {password, disabled: false, emailVerified: true});
    return {uid: existing.uid, restored: true};
  } catch (error) {
    if (error && error.code === "auth/user-not-found") {
      const created = await admin.auth().createUser({
        email,
        password,
        emailVerified: true,
        disabled: false,
      });
      return {uid: created.uid, restored: false};
    }
    throw new HttpsError("internal", "Could not restore that login.");
  }
});

exports.deleteAuthUser = onCall({region: "us-central1"}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  const uid = String((request.data && request.data.uid) || "").trim();
  if (!uid) {
    throw new HttpsError("invalid-argument", "User is required.");
  }
  if (uid === request.auth.uid) {
    throw new HttpsError("failed-precondition", "You cannot delete your own login here.");
  }
  const caller = await loadCaller(request.auth.uid);
  const callerRole = String(caller.role || "").trim().toLowerCase();
  const isSuper = callerIsSuper(caller, request.auth.token);
  if (!isSuper && callerRole !== "admin") {
    throw new HttpsError("permission-denied", "You cannot delete that login.");
  }
  try {
    await admin.auth().deleteUser(uid);
  } catch (error) {
    if (!error || error.code !== "auth/user-not-found") {
      throw new HttpsError("internal", "Could not delete that Firebase login.");
    }
  }
  return {ok: true};
});

const {onDocumentDeleted} = require("firebase-functions/v2/firestore");
exports.onUserProfileDeleted = onDocumentDeleted(
    {document: "users/{userId}", region: "us-central1"},
    async (event) => {
      const uid = event.params.userId;
      try {
        await admin.auth().deleteUser(uid);
      } catch (error) {
        if (!error || error.code !== "auth/user-not-found") {
          console.error("Auth delete after profile delete failed", uid, error);
        }
      }
    },
);

const mailTriggers = require("./mail/triggers");
exports.onUserCreatedEmail = mailTriggers.onUserCreatedEmail;
exports.onPharmacyUpdatedEmail = mailTriggers.onPharmacyUpdatedEmail;
exports.trialEndingReminders = mailTriggers.trialEndingReminders;
