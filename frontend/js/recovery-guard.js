// Shared detection for password-recovery / invite links.
//
// Supabase has used more than one link format over time:
//   - older: #access_token=...&type=recovery   (URL hash fragment)
//   - newer: ?token_hash=...&type=recovery     (URL query string)
//   - also:  ?code=...                          (PKCE exchange)
// Checking only one of these leaves a hole where a recovery link silently
// logs someone straight into the app. These helpers check all of them.

function getRecoveryContext() {
  const hash = window.location.hash || '';
  const search = window.location.search || '';
  const combined = hash + ' ' + search;

  const isRecovery =
    combined.includes('type=recovery') ||
    combined.includes('type=invite') ||
    combined.includes('type=signup');

  // A token identifier unique to this specific link, used to record that
  // it has been consumed. Falls back across the formats above.
  let token = 'none';
  const m1 = hash.match(/access_token=([^&]+)/);
  const m2 = search.match(/token_hash=([^&]+)/);
  const m3 = search.match(/[?&]code=([^&]+)/);
  if (m1) token = m1[1].slice(-32);
  else if (m2) token = m2[1].slice(-32);
  else if (m3) token = m3[1].slice(-32);

  return { isRecovery, token, hash, search };
}

function recoveryUsedKey(token) {
  return 'pwreset_used_' + token;
}

function isRecoveryLinkUsed(token) {
  try { return localStorage.getItem(recoveryUsedKey(token)) === '1'; }
  catch (e) { return false; }
}

function markRecoveryLinkUsed(token) {
  try { localStorage.setItem(recoveryUsedKey(token), '1'); }
  catch (e) { /* non-critical */ }
}

// Called at the top of login.html and index.html. Returns true if the
// page should stop what it is doing (a redirect has been issued).
async function handleRecoveryRedirect() {
  const ctx = getRecoveryContext();
  if (!ctx.isRecovery) return false;

  // Carry the original hash and query through so reset-password.html can
  // complete the exchange itself in the newer formats.
  const suffix = ctx.search + ctx.hash;

  if (isRecoveryLinkUsed(ctx.token)) {
    try { await supabaseClient.auth.signOut(); } catch (e) {}
    window.location.replace('reset-password.html' + suffix);
    return true;
  }

  window.location.replace('reset-password.html' + suffix);
  return true;
}
