// =========================================================================
// AUTH HELPERS
// =========================================================================

async function requireSession() {
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) { window.location.href = "login.html"; return null; }
  return session;
}

async function currentOrg() {
  const preferredId = localStorage.getItem("active_org_id");

  if (preferredId) {
    const { data, error } = await supabaseClient
      .from("organisation_users")
      .select("organisation_id, role, organisations(name, org_type, currency)")
      .eq("status", "active")
      .eq("organisation_id", preferredId)
      .limit(1).single();
    if (!error && data) return data;
    // Preferred org no longer valid (removed, access revoked) - fall through
    // to picking any active membership instead.
    localStorage.removeItem("active_org_id");
  }

  const { data, error } = await supabaseClient
    .from("organisation_users")
    .select("organisation_id, role, organisations(name, org_type, currency)")
    .eq("status", "active").limit(1).single();
  if (error) { console.error("Could not resolve org:", error.message); return null; }
  if (data) localStorage.setItem("active_org_id", data.organisation_id);
  return data;
}

// All organisations (SACCO, Chama, Residents Association, etc.) the
// current user is an active member of - used to populate the org switcher.
async function listMyOrganisations() {
  const { data, error } = await supabaseClient
    .from("organisation_users")
    .select("organisation_id, role, organisations(name, org_type, account_number, status)")
    .eq("status", "active");
  if (error) { console.error("Could not list organisations:", error.message); return []; }
  return data || [];
}

// Switch the active organisation and reload so every page re-fetches
// data scoped to the newly selected org.
function switchOrg(orgId) {
  localStorage.setItem("active_org_id", orgId);
  Object.keys(sessionStorage)
    .filter(k => k.startsWith("org_settings_"))
    .forEach(k => sessionStorage.removeItem(k));
  window.location.href = "index.html";
}

// Load org settings (feature flags, labels) - cached in sessionStorage
async function getOrgSettings(orgId) {
  const cacheKey = 'org_settings_' + orgId;
  const cached = sessionStorage.getItem(cacheKey);
  if (cached) return JSON.parse(cached);

  const { data, error } = await supabaseClient.rpc('fn_org_settings', {
    p_organisation_id: orgId
  });
  if (error || !data) return {
    org_type: 'sacco', show_loans: true, show_investments: false,
    show_assets: false, member_id_label: 'Member No.',
    member_id_prefix: 'SC', contribution_label: 'Contributions',
    fund_label: 'Member Funds'
  };
  sessionStorage.setItem(cacheKey, JSON.stringify(data));
  return data;
}

// Apply org settings to nav - hide/show modules based on org type
function applyOrgNav(settings) {
  const type = settings.org_type;

  // Hide loans for non-SACCO org types unless explicitly enabled
  if (!settings.show_loans) {
    document.querySelectorAll('a[href="loans.html"]').forEach(el => {
      el.closest('.nav-group') ? el.closest('.nav-group').style.display = 'none'
        : el.style.display = 'none';
    });
  }

  // Update nav label based on org type
  document.querySelectorAll('a[href="loans.html"]').forEach(el => {
    if (type === 'chama') el.textContent = 'Loan & Advances';
    else if (type === 'residents_association') el.style.display = 'none';
  });

  // Update page title brand
  const brand = document.querySelector('.brand');
  if (brand && settings.org_name) brand.textContent = settings.org_name;
}

async function signOut() {
  localStorage.removeItem("active_org_id");
  sessionStorage.clear();
  await supabaseClient.auth.signOut();
  window.location.href = "login.html";
}

function showError(el, message) {
  el.textContent = message; el.style.display = "block";
}

function money(n) {
  return Number(n||0).toLocaleString("en-KE", {minimumFractionDigits:2,maximumFractionDigits:2});
}
