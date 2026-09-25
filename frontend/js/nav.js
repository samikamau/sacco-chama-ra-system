// Shared site navigation. Rendered once, used by every page - edit this
// single file instead of the nav block on each HTML page.

const NAV_ICONS = {
  home: '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 11l9-7 9 7"/><path d="M5 10v9a1 1 0 0 0 1 1h4v-6h4v6h4a1 1 0 0 0 1-1v-9"/></svg>',
  users: '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="9" cy="8" r="3"/><path d="M3 20c0-3.3 2.7-6 6-6s6 2.7 6 6"/><circle cx="17" cy="9" r="2.4"/><path d="M15.5 14.2c2.4.4 4.5 2.4 4.5 5.8"/></svg>',
  cash: '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="2.5" y="5.5" width="19" height="13" rx="2"/><line x1="2.5" y1="10" x2="21.5" y2="10"/><line x1="6" y1="14.5" x2="10" y2="14.5"/></svg>',
  percent: '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><line x1="5" y1="19" x2="19" y2="5"/><circle cx="7" cy="7" r="2.3"/><circle cx="17" cy="17" r="2.3"/></svg>',
  outbox: '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v11"/><path d="M8 10l4 4 4-4"/><path d="M4 16v3a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-3"/></svg>',
  bank: '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 10l9-6 9 6"/><line x1="4" y1="10" x2="20" y2="10"/><line x1="5" y1="10" x2="5" y2="19"/><line x1="9.5" y1="10" x2="9.5" y2="19"/><line x1="14.5" y1="10" x2="14.5" y2="19"/><line x1="19" y1="10" x2="19" y2="19"/><line x1="3" y1="20" x2="21" y2="20"/></svg>',
  doc: '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6 2.5h9l4 4V21a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V3.5a1 1 0 0 1 1-1z"/><line x1="8" y1="12" x2="16" y2="12"/><line x1="8" y1="16" x2="16" y2="16"/></svg>',
  chart: '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><line x1="5" y1="20" x2="5" y2="12"/><line x1="12" y1="20" x2="12" y2="6"/><line x1="19" y1="20" x2="19" y2="15"/><line x1="3" y1="20" x2="21" y2="20"/></svg>',
  calculator: '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="2.5" width="14" height="19" rx="2"/><line x1="8" y1="7" x2="16" y2="7"/><line x1="8" y1="12" x2="8" y2="12.01"/><line x1="12" y1="12" x2="12" y2="12.01"/><line x1="16" y1="12" x2="16" y2="12.01"/><line x1="8" y1="16" x2="8" y2="16.01"/><line x1="12" y1="16" x2="12" y2="16.01"/><line x1="16" y1="16" x2="16" y2="18.5"/></svg>',
  key: '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="15" r="4"/><path d="M11 12l8-8"/><path d="M16 7l2.5 2.5"/><path d="M13.5 9.5L16 12"/></svg>',
  logout: '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><line x1="16" y1="12" x2="21" y2="12"/><path d="M18 9l3 3-3 3"/></svg>',
};

const NAV_ITEMS = [
  { href: 'index.html',       label: 'Dashboard',            icon: 'home' },
  { href: 'members.html',     label: 'Members Management',   icon: 'users' },
  { href: 'loans.html',       label: 'Loan Management',      icon: 'percent' },
  { href: 'expenditure.html', label: 'Expenditure',          icon: 'outbox' },
  { href: 'banking.html',     label: 'Banking',              icon: 'bank' },
  { href: 'reports.html',     label: 'Reports',              icon: 'chart' },
];

const MEMBERS_ITEMS = [
  { href: 'members.html',   label: 'All Members' },
  { href: 'statement.html', label: 'Member Statements' },
];

// Terminology that changes depending on the organisation's type. Falls
// back to the SACCO wording whenever org_type is unset or unrecognised.
const TERMINOLOGY = {
  sacco:                  { sidebarMembers: 'Members Management', allMembers: 'All Members' },
  chama:                  { sidebarMembers: 'Chama Members',      allMembers: 'All Chama Members' },
  residents_association:  { sidebarMembers: 'Residents',          allMembers: 'All Residents' },
};

async function getOrgContext() {
  const fallback = { terms: TERMINOLOGY.sacco, modules: { loans: true, expenditure: true, banking: true }, orgType: 'sacco' };
  try {
    if (typeof currentOrg !== 'function') return fallback;
    const org = await currentOrg();
    if (!org) return fallback;
    const { data } = await supabaseClient.from('organisations')
      .select('org_type, enabled_modules').eq('id', org.organisation_id).single();
    const orgType = data?.org_type || 'sacco';
    return {
      terms: TERMINOLOGY[orgType] || TERMINOLOGY.sacco,
      modules: data?.enabled_modules || fallback.modules,
      orgType,
    };
  } catch (e) {
    return fallback;
  }
}

const ACCOUNTANT_ITEMS = [
  { href: 'contributions.html',     label: 'Contributions' },
  { href: 'accounts.html',          label: 'Chart of Accounts' },
  { href: 'journal.html',           label: 'General Journal' },
  { href: 'periods.html',           label: 'Accounting Periods' },
  { href: 'opening-balances.html',  label: 'Opening Balances' },
  { href: 'reconcile.html',         label: 'Reconciliation' },
];

// Sub-pages that should highlight a top-level item even though their
// filename differs (e.g. member.html is a detail page under Members).
const NAV_ALIASES = { 'member.html': 'members.html' };

const ORG_TYPE_LABELS = { sacco: 'SACCO', chama: 'Chama', residents_association: 'Residents Assoc.' };

async function getOrgSwitcherData() {
  try {
    if (typeof listMyOrganisations !== 'function' || typeof currentOrg !== 'function') {
      return { myOrgs: [], activeOrgId: null };
    }
    const [myOrgs, active] = await Promise.all([listMyOrganisations(), currentOrg()]);
    return { myOrgs: myOrgs || [], activeOrgId: active ? active.organisation_id : null };
  } catch (e) {
    return { myOrgs: [], activeOrgId: null };
  }
}

async function renderNav() {
  const mount = document.getElementById('nav-mount');
  if (!mount) return;

  let current = window.location.pathname.split('/').pop() || 'index.html';
  current = NAV_ALIASES[current] || current;

  // Gate access before doing anything else - skip the check on the status
  // page itself (and login) to avoid a redirect loop.
  if (current !== 'account-status.html' && current !== 'login.html' && current !== 'create-organisation.html' && current !== 'platform-admin.html') {
    try {
      if (typeof currentOrg === 'function' && typeof supabaseClient !== 'undefined') {
        const org = await currentOrg();
        if (org) {
          const { data: accessStatus } = await supabaseClient.rpc('fn_org_access_status', {
            p_org_id: org.organisation_id,
          });
          if (accessStatus && accessStatus !== 'active') {
            window.location.href = 'account-status.html';
            return;
          }
        }
      }
    } catch (e) { /* if the access check itself fails, don't block the whole app */ }
  }

  const { terms, modules, orgType } = await getOrgContext();
  const { myOrgs, activeOrgId } = await getOrgSwitcherData();
  let isPlatformAdmin = false;
  try {
    if (typeof supabaseClient !== 'undefined') {
      const { data } = await supabaseClient.rpc('fn_is_platform_admin');
      isPlatformAdmin = !!data;
    }
  } catch (e) { /* not critical - link just won't show */ }

  const accountantHrefs = ACCOUNTANT_ITEMS.map(i => i.href);
  const isAccountantActive = accountantHrefs.includes(current);
  const membersHrefs = MEMBERS_ITEMS.map(i => i.href);
  const isMembersActive = membersHrefs.includes(current);

  // MODULE_MAP ties each optional nav item to its enabled_modules flag.
  // Items with no entry here are always shown.
  const MODULE_MAP = { 'loans.html': 'loans', 'expenditure.html': 'expenditure', 'banking.html': 'banking' };
  const visibleNavItems = NAV_ITEMS.filter(i => {
    const key = MODULE_MAP[i.href];
    return !key || modules[key] !== false;
  });

  const topLinks = visibleNavItems.map(i => {
    let label = i.href === 'members.html' ? terms.sidebarMembers : i.label;
    if (i.href === 'loans.html' && orgType === 'chama') label = 'Loans & Advances';
    return `
    <a href="${i.href}" class="${i.href === current ? 'active' : ''}" style="display:flex;align-items:center;gap:6px">
      ${NAV_ICONS[i.icon]}${label}
    </a>`;
  }).join('');

  const activeOrg = myOrgs.find(o => o.organisation_id === activeOrgId);
  const activeOrgName = activeOrg ? activeOrg.organisations.name : 'Select organisation';
  const activeOrgAcct = activeOrg ? activeOrg.organisations.account_number : null;

  const switcherItems = myOrgs.map(o => {
    const isActive = o.organisation_id === activeOrgId;
    const acct = o.organisations.account_number;
    return `<a href="#" onclick="switchOrg('${o.organisation_id}');return false;"
      style="display:flex;justify-content:space-between;align-items:center;padding:8px 12px;font-size:13px;color:#222;text-decoration:none;${isActive ? 'background:var(--color-bg, #F7F6F3);font-weight:600' : ''}">
      <span>${o.organisations.name}</span>
      <span style="font-size:11px;color:var(--color-muted, #888);font-family:var(--font-mono)">${acct || ''}</span>
    </a>`;
  }).join('');

  mount.innerHTML = `
    <div class="brand" style="margin-bottom:16px">
      <img src="data:image/png;base64,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" alt="Edhafu" style="height:34px;width:auto;display:block">
    </div>
    <div style="position:relative;margin-bottom:12px">
      <button type="button" onclick="toggleOrgSwitcher(event)"
        style="width:100%;text-align:left;background:rgba(255,255,255,0.08);border:1px solid rgba(255,255,255,0.15);color:#fff;padding:8px 10px;border-radius:6px;font-size:12px;cursor:pointer;display:flex;justify-content:space-between;align-items:center;gap:6px">
        <span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${activeOrgName}${activeOrgAcct ? ' <span style="opacity:0.65">' + activeOrgAcct + '</span>' : ''}</span>
        <span>▾</span>
      </button>
      <div id="org-switcher-menu" style="display:none;position:absolute;z-index:30;top:100%;left:0;right:0;background:#fff;border-radius:6px;box-shadow:0 8px 20px rgba(0,0,0,0.25);margin-top:4px;overflow:hidden">
        ${switcherItems}
        ${isPlatformAdmin ? `<a href="create-organisation.html" style="display:block;padding:8px 12px;font-size:13px;color:var(--color-primary, #00173D);text-decoration:none;border-top:1px solid var(--color-line, #ddd)">+ New organisation</a>` : ''}
      </div>
    </div>
    ${topLinks}
    <a href="${ACCOUNTANT_ITEMS[0].href}" class="nav-accountant-toggle ${isAccountantActive ? 'active' : ''}" style="display:flex;align-items:center;gap:6px">
      ${NAV_ICONS.calculator}Accountant
    </a>
    <a href="users.html" class="${current === 'users.html' ? 'active' : ''}" style="display:flex;align-items:center;gap:6px">
      ${NAV_ICONS.key}Organisation Settings
    </a>
    ${isPlatformAdmin ? `
    <a href="platform-admin.html" class="${current === 'platform-admin.html' ? 'active' : ''}" style="display:flex;align-items:center;gap:6px">
      ${NAV_ICONS.calculator}Platform Admin
    </a>` : ''}
    <a href="#" onclick="signOut()" style="display:flex;align-items:center;gap:6px">
      ${NAV_ICONS.logout}Sign out
    </a>`;

  const membersItemsThemed = MEMBERS_ITEMS.map(i =>
    i.href === 'members.html' ? { ...i, label: terms.allMembers } : i
  );
  renderGroupBar('members-bar', membersItemsThemed, current, isMembersActive);
  renderGroupBar('accountant-bar', ACCOUNTANT_ITEMS, current, isAccountantActive);
}

function toggleOrgSwitcher(e) {
  e.preventDefault();
  e.stopPropagation();
  const menu = document.getElementById('org-switcher-menu');
  if (!menu) return;
  menu.style.display = menu.style.display === 'none' ? 'block' : 'none';
}
document.addEventListener('click', (e) => {
  const menu = document.getElementById('org-switcher-menu');
  if (menu && menu.style.display === 'block' && !menu.contains(e.target) && !e.target.closest('button')) {
    menu.style.display = 'none';
  }
});
// Inserted as the first child of <main class="main"> on every page -
// no per-page HTML edit needed. Shows automatically when the current
// page belongs to that group; the Accountant bar can also be toggled
// from the sidebar's Accountant link.
function ensureGroupTabStyles() {
  if (document.getElementById('nav-group-tab-styles')) return;
  const style = document.createElement('style');
  style.id = 'nav-group-tab-styles';
  style.textContent = `
    .nav-group-tab {
      display: inline-block; padding: 10px 18px; font-size: 14px; text-decoration: none;
      color: var(--color-muted, #666); border-bottom: 3px solid transparent;
      border-radius: 6px 6px 0 0; cursor: pointer; position: relative;
      transition: color 0.18s ease, background 0.18s ease, border-color 0.18s ease, transform 0.12s ease;
    }
    .nav-group-tab:hover {
      color: var(--color-primary, #00173D);
      background: var(--color-accent-tint, rgba(27,110,69,0.08));
      border-bottom-color: rgba(27,110,69,0.35);
      transform: translateY(-1px);
    }
    .nav-group-tab:active { transform: translateY(0); }
    .nav-group-tab.active {
      color: var(--color-primary, #00173D); font-weight: 600;
      background: var(--color-accent-tint, rgba(27,110,69,0.1));
      border-bottom-color: var(--color-accent, #00173D);
    }
  `;
  document.head.appendChild(style);
}

function renderGroupBar(barId, items, current, isActive) {
  const main = document.querySelector('main.main') || document.querySelector('.main');
  if (!main) return;

  ensureGroupTabStyles();

  let bar = document.getElementById(barId);
  if (!bar) {
    bar = document.createElement('div');
    bar.id = barId;
    main.insertBefore(bar, main.firstChild);
  }

  bar.style.cssText = `display:${isActive ? 'flex' : 'none'};gap:4px;flex-wrap:wrap;align-items:center;margin-bottom:20px;border-bottom:2px solid var(--color-line, #ddd);`;

  bar.innerHTML = items.map(i => {
    const active = i.href === current;
    return `<a href="${i.href}" class="nav-group-tab ${active ? 'active' : ''}">${i.label}</a>`;
  }).join('');
}

document.addEventListener('DOMContentLoaded', renderNav);
