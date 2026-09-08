// =========================================================================
// AUTH HELPERS
// Every protected page calls requireSession() on load. If there's no
// session, the user is bounced to login.html. currentOrg() resolves which
// organisation the logged-in user belongs to (Phase 1 assumes one org per
// user; multi-org switching can be added later without a schema change).
// =========================================================================

async function requireSession() {
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) {
    window.location.href = "login.html";
    return null;
  }
  return session;
}

async function currentOrg() {
  const { data, error } = await supabaseClient
    .from("organisation_users")
    .select("organisation_id, role, organisations(name, org_type, currency)")
    .eq("status", "active")
    .limit(1)
    .single();

  if (error) {
    console.error("Could not resolve organisation for this user:", error.message);
    return null;
  }
  return data;
}

async function signOut() {
  await supabaseClient.auth.signOut();
  window.location.href = "login.html";
}

function showError(el, message) {
  el.textContent = message;
  el.style.display = "block";
}

function money(n) {
  return Number(n || 0).toLocaleString("en-KE", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}
