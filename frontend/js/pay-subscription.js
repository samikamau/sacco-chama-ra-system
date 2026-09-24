// Shared "Pay Subscription" modal, used by both the dashboard and the
// suspended-account page so payment details live in exactly one place.
//
// Usage:
//   renderPayModal();                       // injects the markup once
//   setPayDetails(fee, accountNumber);      // fill in org-specific values
//   openPayModal(); / closePayModal();
//
// STK push: PAY_PUSH_ENDPOINT is intentionally left null until the real
// endpoint exists. While it's null the modal shows manual Paybill
// instructions only. Set it to your endpoint URL and the "Pay now"
// button starts working with no other change needed.
const PAY_PUSH_ENDPOINT = null;

const PAYBILL_NUMBER = '247247';

let payFee = null;
let payAccountNumber = null;

function setPayDetails(fee, accountNumber) {
  payFee = fee;
  payAccountNumber = accountNumber;
  const feeEl = document.getElementById('pay-fee');
  const acctEl = document.getElementById('pay-account');
  if (feeEl) feeEl.textContent = fee != null ? 'KES ' + money(fee) : 'Not set';
  if (acctEl) acctEl.textContent = accountNumber || 'Not yet assigned';
}

function renderPayModal() {
  if (document.getElementById('pay-drawer')) return;

  const backdrop = document.createElement('div');
  backdrop.className = 'drawer-backdrop';
  backdrop.id = 'pay-backdrop';
  backdrop.onclick = closePayModal;

  const drawer = document.createElement('div');
  drawer.className = 'drawer';
  drawer.id = 'pay-drawer';
  drawer.innerHTML = `
    <h2>Pay Subscription</h2>

    <div style="background:var(--color-bg,#F7F6F3);border-radius:8px;padding:14px;margin:12px 0">
      <div style="display:flex;justify-content:space-between;padding:4px 0">
        <span style="color:var(--color-muted)">Paybill</span>
        <strong style="font-family:var(--font-mono)">${PAYBILL_NUMBER}</strong>
      </div>
      <div style="display:flex;justify-content:space-between;padding:4px 0">
        <span style="color:var(--color-muted)">Account number</span>
        <strong style="font-family:var(--font-mono)" id="pay-account">-</strong>
      </div>
      <div style="display:flex;justify-content:space-between;padding:4px 0;border-top:1px solid var(--color-line);margin-top:6px;padding-top:8px">
        <span style="color:var(--color-muted)">Amount</span>
        <strong id="pay-fee">-</strong>
      </div>
    </div>

    <div id="pay-push-area"></div>

    <details style="margin-top:12px">
      <summary style="cursor:pointer;color:var(--color-muted);font-size:13px">Pay manually instead</summary>
      <ol style="font-size:13px;margin:8px 0 0 18px;line-height:1.7">
        <li>Go to M-Pesa, then Lipa na M-Pesa, then Pay Bill</li>
        <li>Business number: <strong>${PAYBILL_NUMBER}</strong></li>
        <li>Account number: <strong id="pay-account-2">-</strong></li>
        <li>Enter the amount and confirm</li>
      </ol>
    </details>

    <p id="pay-status" style="display:none;font-size:13px;margin-top:10px"></p>

    <button class="btn" style="margin-top:14px;background:var(--color-muted)" onclick="closePayModal()">Close</button>
  `;

  document.body.appendChild(backdrop);
  document.body.appendChild(drawer);

  // Keep the duplicated account number in the manual instructions in sync.
  const observer = new MutationObserver(() => {
    const a = document.getElementById('pay-account');
    const b = document.getElementById('pay-account-2');
    if (a && b) b.textContent = a.textContent;
  });
  const acctEl = document.getElementById('pay-account');
  if (acctEl) observer.observe(acctEl, { childList: true, characterData: true, subtree: true });

  renderPushArea();
}

function renderPushArea() {
  const area = document.getElementById('pay-push-area');
  if (!area) return;

  if (!PAY_PUSH_ENDPOINT) {
    area.innerHTML = `
      <p style="font-size:13px;color:var(--color-muted)">
        Use the Paybill details above to pay. Once your payment is received your
        account will be activated.
      </p>`;
    return;
  }

  area.innerHTML = `
    <div class="field">
      <label>M-Pesa phone number</label>
      <input id="pay-phone" type="tel" placeholder="2547XXXXXXXX">
    </div>
    <button class="btn accent" style="width:100%" onclick="sendStkPush()">Pay now</button>
    <p style="font-size:12px;color:var(--color-muted);margin-top:6px">
      You'll get a prompt on your phone to enter your M-Pesa PIN.
    </p>`;
}

async function sendStkPush() {
  const statusEl = document.getElementById('pay-status');
  const phone = (document.getElementById('pay-phone') || {}).value;
  statusEl.style.display = 'block';
  statusEl.style.color = 'var(--color-muted)';

  if (!phone || !/^2547\d{8}$/.test(phone.trim())) {
    statusEl.style.color = 'var(--color-alert, #E11D48)';
    statusEl.textContent = 'Enter a valid phone number in the format 2547XXXXXXXX.';
    return;
  }

  statusEl.textContent = 'Sending payment request…';
  try {
    const res = await fetch(PAY_PUSH_ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        phone: phone.trim(),
        amount: payFee,
        account_number: payAccountNumber,
      }),
    });
    if (!res.ok) throw new Error('Payment request failed (' + res.status + ')');
    statusEl.style.color = 'var(--color-success, #10B981)';
    statusEl.textContent = 'Check your phone and enter your M-Pesa PIN to complete payment.';
  } catch (e) {
    statusEl.style.color = 'var(--color-alert, #E11D48)';
    statusEl.textContent = e.message + '. Use the manual Paybill option below instead.';
  }
}

function openPayModal() {
  const b = document.getElementById('pay-backdrop');
  const d = document.getElementById('pay-drawer');
  if (b) b.classList.add('open');
  if (d) d.classList.add('open');
}

function closePayModal() {
  const b = document.getElementById('pay-backdrop');
  const d = document.getElementById('pay-drawer');
  if (b) b.classList.remove('open');
  if (d) d.classList.remove('open');
}
