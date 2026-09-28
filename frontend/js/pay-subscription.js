// pay-subscription.js
// M-Pesa subscription popup for the dashboard.
// Usage: <button onclick="openPayModal()">Pay Subscription</button>
// Needs: supabase-js loaded on the page, and window.currentOrgId set by the dashboard.

(function () {
  // ---------- SETTINGS ----------
  const CONFIG = {
    SUPABASE_URL: "https://xrjctoisrgycfesstgbg.supabase.co",
    SUPABASE_KEY: "sb_publishable_KNEHRVU2nK2OUb8DB_CMww_g5OZ7teo",
    APP_CODE: "sacco",
    SUPPORT: "Sami Accountants on 0722 908 232",
  };
  // ------------------------------

  // Use the page's Supabase client if it exists, otherwise create one (same login session)
  function getClient() {
    if (window.__payClient) return window.__payClient;
    const s = window.supabase;
    window.__payClient = s && s.auth ? s : s.createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_KEY);
    return window.__payClient;
  }

  const kes = (n) => "KES " + Number(n).toLocaleString("en-KE", { maximumFractionDigits: 2 });
  const fmtDate = (d) => new Date(d).toLocaleDateString("en-KE", {
    day: "numeric", month: "short", year: "numeric", timeZone: "Africa/Nairobi",
  });
  const cycleText = { monthly: "Every month", quarterly: "Every 3 months", annual: "Once a year" };
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => (
    { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]
  ));
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  function normalisePhone(p) {
    let s = String(p).replace(/\D/g, "");
    if (s.startsWith("0")) s = "254" + s.slice(1);
    if (s.length === 9) s = "254" + s;
    return /^254(7|1)\d{8}$/.test(s) ? s : null;
  }

  // ---------- Styles (all prefixed mp- so they don't clash with the app) ----------
  const css = `
    .mp-backdrop { position: fixed; inset: 0; background: rgba(0, 30, 12, 0.18); z-index: 9999; }
    .mp-modal { position: fixed; width: min(21rem, calc(100vw - 1.5rem)); background: #fff; color: #1B2A1F;
      border-radius: 12px; overflow: hidden; box-shadow: 0 14px 40px rgba(0, 40, 15, 0.28);
      font-family: inherit; display: flex; flex-direction: column; max-height: calc(100vh - 1.5rem);
      text-transform: none; letter-spacing: normal; }
    .mp-modal * { box-sizing: border-box; }
    .mp-head { background: #00A651; color: #fff; padding: 0.7rem 0.9rem; display: flex;
      align-items: center; justify-content: space-between; flex: none; }
    .mp-brand { font-weight: 800; font-size: 1.1rem; letter-spacing: 0.02em; margin: 0; line-height: 1.1; color: #fff; }
    .mp-brand span { font-weight: 500; font-size: 0.78rem; display: block; letter-spacing: 0; opacity: 0.9; margin-top: 0.15rem; }
    .mp-close { background: transparent; border: 0; color: #fff; font-size: 1.4rem; line-height: 1;
      cursor: pointer; padding: 0.2rem 0.45rem; border-radius: 6px; }
    .mp-close:focus-visible { outline: 2px solid #fff; }
    .mp-body { padding: 0.9rem; overflow-y: auto; font-size: 0.88rem; }
    .mp-standing { font-size: 0.82rem; color: #4A5A4E; margin: 0 0 0.8rem; }
    .mp-standing strong { color: #1B2A1F; }
    .mp-modal .mp-label { display: block; font-weight: 600; font-size: 0.82rem; margin: 0 0 0.4rem;
      color: #1B2A1F; text-transform: none; letter-spacing: normal; }
    .mp-plans { border: 1px solid #D6E9DB; border-radius: 9px; overflow: hidden; margin-bottom: 0.8rem; }
    .mp-modal .mp-plan { display: grid; grid-template-columns: auto 1fr auto; gap: 0.6rem; align-items: center;
      padding: 0.55rem 0.75rem; border-top: 1px solid #E6F2E9; cursor: pointer; margin: 0;
      color: #1B2A1F; text-transform: none; letter-spacing: normal; font-size: 0.88rem; font-weight: 400; }
    .mp-plan:first-child { border-top: 0; }
    .mp-plan:has(input:checked) { background: #E9F7EE; }
    .mp-plan input { accent-color: #00A651; width: 1rem; height: 1rem; margin: 0; }
    .mp-plan-name { font-weight: 600; color: #1B2A1F; }
    .mp-plan-cycle { font-size: 0.75rem; color: #5E6E62; }
    .mp-plan-price { font-weight: 700; white-space: nowrap; color: #1B2A1F; }
    .mp-empty { padding: 0.7rem 0.8rem; margin: 0; color: #5E6E62; }
    .mp-phone { width: 100%; border: 1.5px solid #CFE3D5; border-radius: 9px;
      padding: 0.6rem 0.75rem; font-size: 0.98rem; letter-spacing: 0.03em; color: #1B2A1F; background: #fff; }
    .mp-phone:focus { outline: none; border-color: #00A651; box-shadow: 0 0 0 3px rgba(0, 166, 81, 0.2); }
    .mp-hint { font-size: 0.74rem; color: #5E6E62; margin: 0.35rem 0 0; }
    .mp-pay { margin-top: 0.85rem; width: 100%; background: #00A651; color: #fff; border: 0;
      border-radius: 9px; padding: 0.7rem; font-weight: 700; font-size: 0.95rem; cursor: pointer; }
    .mp-pay:hover { background: #008A43; }
    .mp-pay:focus-visible { outline: 3px solid rgba(0, 166, 81, 0.35); outline-offset: 2px; }
    .mp-pay:disabled { opacity: 0.6; cursor: wait; }
    .mp-status { margin-top: 0.7rem; font-size: 0.82rem; }
    .mp-status:empty { margin-top: 0; }
    .mp-status.mp-error { color: #B3261E; }
    .mp-wait { display: flex; gap: 0.5rem; align-items: flex-start; margin: 0; }
    .mp-dot { flex: none; width: 0.5rem; height: 0.5rem; margin-top: 0.35rem; border-radius: 50%;
      background: #00A651; animation: mp-pulse 1.3s ease-in-out infinite; }
    @keyframes mp-pulse { 50% { opacity: 0.25; } }
    .mp-receipt { position: relative; background: #F2FAF4; border: 1px solid #CFE8D6; border-radius: 9px;
      padding: 0.9rem 0.85rem 0.8rem; }
    .mp-receipt h3 { margin: 0 0 0.75rem; font-size: 1rem; padding-right: 4.5rem; color: #1B2A1F; }
    .mp-receipt dl { display: grid; grid-template-columns: auto 1fr; gap: 0.35rem 0.8rem; margin: 0; font-size: 0.84rem; }
    .mp-receipt dt { color: #5E6E62; }
    .mp-receipt dd { margin: 0; text-align: right; font-weight: 600; }
    .mp-stamp { position: absolute; top: 0.7rem; right: 0.8rem; border: 2.5px solid #00A651; color: #00A651;
      border-radius: 4px; font-weight: 800; font-size: 0.85rem; letter-spacing: 0.12em; padding: 0.05rem 0.4rem;
      transform: rotate(-8deg); animation: mp-press 0.35s cubic-bezier(0.2, 1.4, 0.4, 1) both; }
    @keyframes mp-press { from { transform: rotate(-8deg) scale(1.8); opacity: 0; } }
    .mp-done { margin-top: 0.75rem; width: 100%; background: #fff; color: #00843F; border: 1.5px solid #00A651;
      border-radius: 9px; padding: 0.6rem; font-weight: 700; cursor: pointer; }
    @media (max-width: 639px) {
      .mp-modal { left: 0.75rem; right: 0.75rem; bottom: 0.75rem; width: auto; }
    }
    @media (prefers-reduced-motion: reduce) { .mp-dot, .mp-stamp { animation: none; } }
    .mp-backdrop[hidden], .mp-backdrop [hidden] { display: none !important; }
  `;

  let root = null;
  let plans = [];
  let busy = false;
  let anchor = null;

  // Place the popup right under (or above) the Pay Subscription button
  function position() {
    if (!root || root.hidden) return;
    const m = root.querySelector(".mp-modal");
    m.style.top = m.style.left = m.style.bottom = m.style.maxHeight = "";
    if (window.innerWidth < 640 || !anchor) return;   // phones: bottom sheet via CSS
    const r = anchor.getBoundingClientRect();
    const gap = 8, pad = 12;
    const w = m.offsetWidth;
    const left = Math.min(Math.max(pad, r.right - w), window.innerWidth - w - pad);
    const below = window.innerHeight - r.bottom - gap - pad;
    const above = r.top - gap - pad;
    m.style.left = left + "px";
    if (below >= 380 || below >= above) {
      m.style.top = (r.bottom + gap) + "px";
      m.style.maxHeight = below + "px";
    } else {
      m.style.bottom = (window.innerHeight - r.top + gap) + "px";
      m.style.maxHeight = above + "px";
    }
  }

  function build() {
    if (root) return;
    const style = document.createElement("style");
    style.textContent = css;
    document.head.appendChild(style);

    root = document.createElement("div");
    root.className = "mp-backdrop";
    root.hidden = true;
    root.innerHTML = `
      <div class="mp-modal" role="dialog" aria-modal="true" aria-labelledby="mp-title">
        <div class="mp-head">
          <p class="mp-brand" id="mp-title">M-PESA<span>Pay subscription</span></p>
          <button class="mp-close" type="button" aria-label="Close">&times;</button>
        </div>
        <div class="mp-body">
          <p class="mp-standing" id="mp-standing">Checking your subscription...</p>
          <div id="mp-form">
            <span class="mp-label">Choose a plan</span>
            <div class="mp-plans" id="mp-plans"></div>
            <label class="mp-label" for="mp-phone">M-Pesa number</label>
            <input class="mp-phone" id="mp-phone" type="tel" inputmode="numeric" autocomplete="tel" placeholder="0712 345 678">
            <p class="mp-hint">You'll get a prompt on this phone to enter your M-Pesa PIN.</p>
            <button class="mp-pay" id="mp-pay" type="button">Pay</button>
            <div class="mp-status" id="mp-status" role="status" aria-live="polite"></div>
          </div>
          <div id="mp-receipt" hidden></div>
        </div>
      </div>`;
    document.body.appendChild(root);

    root.querySelector(".mp-close").addEventListener("click", close);
    root.addEventListener("click", (e) => { if (e.target === root) close(); });
    document.addEventListener("keydown", (e) => { if (e.key === "Escape" && !root.hidden) close(); });
    window.addEventListener("resize", position);
    root.querySelector("#mp-plans").addEventListener("change", updateButton);
    root.querySelector("#mp-pay").addEventListener("click", pay);
  }

  const $ = (id) => root.querySelector("#" + id);

  function close() {
    if (busy && !confirm("A payment is still waiting for confirmation. Close anyway? If you paid, your subscription will still update.")) return;
    root.hidden = true;
    document.body.style.overflow = "";
  }

  function showError(msg) { $("mp-status").className = "mp-status mp-error"; $("mp-status").textContent = msg; }
  function showWaiting(msg) {
    $("mp-status").className = "mp-status";
    $("mp-status").innerHTML = `<p class="mp-wait"><span class="mp-dot" aria-hidden="true"></span><span>${esc(msg)}</span></p>`;
  }

  function selectedPlan() {
    const id = root.querySelector('input[name="mp-plan"]:checked')?.value;
    return plans.find((p) => p.id === id);
  }
  function updateButton() {
    const p = selectedPlan();
    $("mp-pay").textContent = p ? `Pay ${kes(p.price_kes)}` : "Pay";
  }

  async function loadStanding(orgId) {
    const { data, error } = await getClient().rpc("get_subscription", { p_org: orgId, p_app: CONFIG.APP_CODE });
    const el = $("mp-standing");
    if (error) { el.textContent = "Couldn't load your subscription status."; return null; }
    const s = data?.[0] ?? null;
    const live = s && ["active", "trial"].includes(s.status) && new Date(s.current_period_end) > new Date();
    if (live) el.innerHTML = `Active until <strong>${fmtDate(s.current_period_end)}</strong>. Paying now adds time on top.`;
    else if (s?.current_period_end) el.innerHTML = `Your subscription ended on <strong>${fmtDate(s.current_period_end)}</strong>.`;
    else el.textContent = "No active subscription yet.";
    return s;
  }

  async function loadPlans() {
    const { data, error } = await getClient()
      .from("subscription_plans")
      .select("id, name, billing_cycle, price_kes")
      .eq("app_code", CONFIG.APP_CODE)
      .eq("is_active", true)
      .order("price_kes");
    if (error || !data?.length) {
      $("mp-plans").innerHTML = `<p class="mp-empty">No plans are available right now. Contact ${esc(CONFIG.SUPPORT)}.</p>`;
      $("mp-pay").disabled = true;
      return;
    }
    plans = data;
    $("mp-pay").disabled = false;
    $("mp-plans").innerHTML = data.map((p, i) => `
      <label class="mp-plan">
        <input type="radio" name="mp-plan" value="${esc(p.id)}" ${i === 0 ? "checked" : ""}>
        <span><span class="mp-plan-name">${esc(p.name)}</span><br><span class="mp-plan-cycle">${cycleText[p.billing_cycle] ?? ""}</span></span>
        <span class="mp-plan-price">${kes(p.price_kes)}</span>
      </label>`).join("");
    updateButton();
  }

  function friendly(err) {
    if (!err) return "Couldn't start the payment. Try again.";
    if (err.includes("Invalid Safaricom number")) return "Enter a Safaricom number, for example 0712 345 678.";
    if (err.includes("Not signed in")) return "Your session has ended. Sign in again and retry.";
    if (err.includes("Plan not found")) return "That plan is no longer available. Close and reopen this window.";
    return `Couldn't start the payment: ${err}`;
  }

  async function poll(checkoutId) {
    for (let i = 0; i < 40; i++) {
      await sleep(3000);
      const { data } = await getClient().rpc("get_payment_status", { p_checkout: checkoutId });
      const row = data?.[0];
      if (row && row.status !== "PENDING") return row;
    }
    return null;
  }

  function showReceipt(row, plan, sub) {
    $("mp-form").hidden = true;
    $("mp-receipt").hidden = false;
    $("mp-receipt").innerHTML = `
      <div class="mp-receipt">
        <span class="mp-stamp" aria-hidden="true">PAID</span>
        <h3>Payment received</h3>
        <dl>
          <dt>M-Pesa receipt</dt><dd>${esc(row.mpesa_receipt)}</dd>
          <dt>Amount</dt><dd>${kes(row.mpesa_amount)}</dd>
          <dt>Plan</dt><dd>${esc(plan?.name)}</dd>
          <dt>Paid on</dt><dd>${fmtDate(row.transaction_date ?? new Date())}</dd>
          ${sub?.current_period_end ? `<dt>Active until</dt><dd>${fmtDate(sub.current_period_end)}</dd>` : ""}
        </dl>
      </div>
      <button class="mp-done" type="button" id="mp-done">Done</button>`;
    $("mp-done").addEventListener("click", close);
    $("mp-done").focus();
    position();
  }

  async function pay() {
    if (busy) return;
    const orgId = window.currentOrgId;
    const plan = selectedPlan();
    const phone = normalisePhone($("mp-phone").value);
    if (!plan) return showError("Choose a plan first.");
    if (!phone) { $("mp-phone").focus(); return showError("Enter a Safaricom number, for example 0712 345 678."); }

    busy = true;
    $("mp-pay").disabled = true;
    showWaiting("Sending the payment prompt to your phone.");

    const { data, error } = await getClient().functions.invoke("mpesa-stkpush", {
      body: { plan_id: plan.id, organisation_id: orgId, phone },
    });
    let result = data;
    if (error) {
      try { result = await error.context.json(); } catch { result = { ok: false, error: error.message }; }
    }
    if (!result?.ok) {
      busy = false; $("mp-pay").disabled = false;
      return showError(friendly(result?.error));
    }

    showWaiting("Check your phone and enter your M-Pesa PIN to confirm.");
    const row = await poll(result.checkout_request_id);
    busy = false;
    $("mp-pay").disabled = false;

    if (!row) return showError("M-Pesa hasn't confirmed yet. If you entered your PIN, your subscription will update within a few minutes.");
    if (row.status === "SUCCESS") {
      await sleep(1500);
      const sub = await loadStanding(orgId);
      if (typeof window.loadSubscriptionStatus === "function") {
        try { window.loadSubscriptionStatus(orgId); } catch (e) { /* ignore */ }
      }
      return showReceipt(row, plan, sub);
    }
    if (row.status === "CANCELLED") return showError("You cancelled the prompt on your phone. No money was taken. You can try again.");
    showError(`The payment didn't go through (${row.result_desc || "unknown reason"}). You can try again.`);
  }

  // ---------- Public function called by the button ----------
  window.openPayModal = async function (evt) {
    if (!window.currentOrgId) {
      alert("Your organisation is still loading. Wait a moment and try again.");
      return;
    }
    build();
    const ae = document.activeElement;
    anchor = (evt && evt.currentTarget && evt.currentTarget.getBoundingClientRect) ? evt.currentTarget
      : (ae && ae.matches && ae.matches("button, a")) ? ae
      : document.querySelector('[onclick*="openPayModal"]');
    // reset to a fresh form each time it opens
    $("mp-form").hidden = false;
    $("mp-receipt").hidden = true;
    $("mp-status").textContent = "";
    $("mp-status").className = "mp-status";
    $("mp-standing").textContent = "Checking your subscription...";
    root.hidden = false;
    document.body.style.overflow = "hidden";
    position();
    $("mp-phone").focus({ preventScroll: true });
    await Promise.all([loadStanding(window.currentOrgId), loadPlans()]);
    position();
  };
})();
