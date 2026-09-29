/* =====================================================================
   EDHAFU LEGAL GATE  (works for Edhafu Ledgers and Edhafu Payroll)
   After login, checks whether the user has accepted the current legal
   documents. If not, shows a blocking screen with a tick box. Acceptance
   is recorded in the database with a server timestamp, IP and device.

   HOW TO USE (one line per page, after your Supabase client is created):
     EdhafuLegal.init(yourSupabaseClient, 'edhafu_ledgers');   // Ledgers
     EdhafuLegal.init(yourSupabaseClient, 'edhafu_payroll');   // Payroll
   ===================================================================== */
(function () {
  const NAMES = {
    terms: 'Terms of Service',
    privacy: 'Privacy Policy',
    dpa: 'Data Processing Agreement',
    billing: 'Subscription, Billing and Refund Policy',
    aup: 'Acceptable Use Policy'
  };

  function orgFromUrl() {
    const org = new URLSearchParams(window.location.search).get('org');
    return /^[0-9a-f-]{36}$/i.test(org || '') ? org : null;
  }

  async function init(client, product) {
    if (!client || !product) { console.warn('EdhafuLegal: client and product are required'); return; }
    try {
      const { data: { session } } = await client.auth.getSession();
      if (!session) return;   // not logged in: the login page handles it

      const { data: pending, error } = await client
        .from('pending_acceptances')
        .select('id, doc_type, version, content_url')
        .eq('product', product);
      if (error) { console.warn('EdhafuLegal:', error.message); return; }
      if (!pending || pending.length === 0) return;

      const { count } = await client
        .from('legal_acceptances')
        .select('id', { count: 'exact', head: true });
      const firstTime = (count || 0) === 0;

      show(client, product, pending, firstTime);
    } catch (e) {
      console.warn('EdhafuLegal:', e);
    }
  }

  function show(client, product, pending, firstTime) {
    if (document.getElementById('edhafuLegalGate')) return;
    const links = pending.map(d =>
      `<li><a href="${d.content_url}" target="_blank" rel="noopener">${NAMES[d.doc_type] || d.doc_type}</a>
       <span class="elg-v">version ${d.version}</span></li>`).join('');

    const wrap = document.createElement('div');
    wrap.id = 'edhafuLegalGate';
    wrap.innerHTML = `
      <style>
        #edhafuLegalGate{position:fixed;inset:0;z-index:99999;background:rgba(15,36,82,.55);
          display:grid;place-items:center;padding:16px;font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
        #edhafuLegalGate .elg-card{background:#fff;color:#1b2333;width:100%;max-width:480px;border-radius:12px;
          padding:24px;box-shadow:0 20px 50px rgba(15,36,82,.25);border-top:4px solid #0F2452}
        #edhafuLegalGate h2{margin:0 0 8px;font-size:20px;color:#0F2452}
        #edhafuLegalGate p{margin:0 0 12px;font-size:14px;line-height:1.5;color:#4a5468}
        #edhafuLegalGate ul{margin:0 0 16px;padding-left:18px;font-size:14px;line-height:1.9}
        #edhafuLegalGate a{color:#0F2452;font-weight:600}
        #edhafuLegalGate .elg-v{color:#7a8396;font-size:12px;margin-left:4px}
        #edhafuLegalGate label{display:flex;gap:10px;align-items:flex-start;font-size:14px;line-height:1.45;margin-bottom:16px;cursor:pointer}
        #edhafuLegalGate input{margin-top:3px;width:18px;height:18px;accent-color:#0F2452;flex:none}
        #edhafuLegalGate button{width:100%;padding:12px;border:0;border-radius:8px;background:#0F2452;color:#fff;
          font-size:15px;font-weight:600;cursor:pointer}
        #edhafuLegalGate button:disabled{background:#b7bfcf;cursor:not-allowed}
        #edhafuLegalGate button:focus-visible{outline:3px solid #CF1B30;outline-offset:2px}
        #edhafuLegalGate .elg-err{color:#CF1B30;font-size:13px;margin:10px 0 0;display:none}
      </style>
      <div class="elg-card" role="dialog" aria-modal="true" aria-labelledby="elgTitle">
        <h2 id="elgTitle">${firstTime ? 'Before you continue' : "We've updated our terms"}</h2>
        <p>${firstTime
          ? 'Please read and accept these documents to use Edhafu.'
          : 'Please review and accept the updated documents to keep using Edhafu. You can still export your data if you do not accept.'}</p>
        <ul>${links}</ul>
        <label><input type="checkbox" id="elgTick">
          <span>I have read and agree to the documents above, for myself and for the organisation I use Edhafu for.</span></label>
        <button id="elgBtn" disabled>Accept and continue</button>
        <p class="elg-err" id="elgErr"></p>
      </div>`;
    document.body.appendChild(wrap);
    document.body.style.overflow = 'hidden';

    const tick = wrap.querySelector('#elgTick');
    const btn = wrap.querySelector('#elgBtn');
    const err = wrap.querySelector('#elgErr');
    tick.addEventListener('change', () => { btn.disabled = !tick.checked; });

    btn.addEventListener('click', async () => {
      btn.disabled = true; btn.textContent = 'Saving...'; err.style.display = 'none';
      const args = { p_document_ids: pending.map(d => d.id), p_context: firstTime ? 'signup' : 'reacceptance' };
      if (product === 'edhafu_ledgers') args.p_organisation_id = orgFromUrl();
      const { error } = await client.rpc('accept_legal_documents', args);
      if (error) {
        err.textContent = 'Your acceptance was not saved. Check your connection and try again. If it keeps failing, email admin@edhafu.com.';
        err.style.display = 'block';
        btn.textContent = 'Accept and continue'; btn.disabled = !tick.checked;
        console.warn('EdhafuLegal:', error.message);
        return;
      }
      wrap.remove();
      document.body.style.overflow = '';
    });
  }

  window.EdhafuLegal = { init };
})();
