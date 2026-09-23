// Shared site navigation. Rendered once, used by every page — edit this
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

  const { terms, modules, orgType } = await getOrgContext();
  const { myOrgs, activeOrgId } = await getOrgSwitcherData();

  let current = window.location.pathname.split('/').pop() || 'index.html';
  current = NAV_ALIASES[current] || current;

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
  const activeOrgTypeLabel = activeOrg ? (ORG_TYPE_LABELS[activeOrg.organisations.org_type] || '') : '';

  const switcherItems = myOrgs.map(o => {
    const isActive = o.organisation_id === activeOrgId;
    return `<a href="#" onclick="switchOrg('${o.organisation_id}');return false;"
      style="display:flex;justify-content:space-between;align-items:center;padding:8px 12px;font-size:13px;color:#222;text-decoration:none;${isActive ? 'background:var(--color-bg, #F7F6F3);font-weight:600' : ''}">
      <span>${o.organisations.name}</span>
      <span style="font-size:11px;color:var(--color-muted, #888)">${ORG_TYPE_LABELS[o.organisations.org_type] || ''}</span>
    </a>`;
  }).join('');

  mount.innerHTML = `
    <div class="brand" style="line-height:1.15">
      <span style="font-size:28px;font-weight:700;color:#E63946">e</span><span style="font-size:28px;font-weight:700;color:#FFFFFF">dhafu</span>
      <div style="font-size:12px;font-weight:400;letter-spacing:0.06em;color:rgba(255,255,255,0.65);margin-top:2px">Finance Simplified</div>
    </div>
    <div style="position:relative;margin-bottom:12px">
      <button type="button" onclick="toggleOrgSwitcher(event)"
        style="width:100%;text-align:left;background:rgba(255,255,255,0.08);border:1px solid rgba(255,255,255,0.15);color:#fff;padding:8px 10px;border-radius:6px;font-size:12px;cursor:pointer;display:flex;justify-content:space-between;align-items:center;gap:6px">
        <span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${activeOrgName}${activeOrgTypeLabel ? ' <span style="opacity:0.65">(' + activeOrgTypeLabel + ')</span>' : ''}</span>
        <span>▾</span>
      </button>
      <div id="org-switcher-menu" style="display:none;position:absolute;z-index:30;top:100%;left:0;right:0;background:#fff;border-radius:6px;box-shadow:0 8px 20px rgba(0,0,0,0.25);margin-top:4px;overflow:hidden">
        ${switcherItems}
      </div>
    </div>
    ${topLinks}
    <a href="${ACCOUNTANT_ITEMS[0].href}" class="nav-accountant-toggle ${isAccountantActive ? 'active' : ''}" style="display:flex;align-items:center;gap:6px">
      ${NAV_ICONS.calculator}Accountant
    </a>
    <a href="users.html" class="${current === 'users.html' ? 'active' : ''}" style="display:flex;align-items:center;gap:6px">
      ${NAV_ICONS.key}Users
    </a>
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
// Inserted as the first child of <main class="main"> on every page —
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
      color: var(--color-primary, #1B6E45);
      background: var(--color-accent-tint, rgba(27,110,69,0.08));
      border-bottom-color: rgba(27,110,69,0.35);
      transform: translateY(-1px);
    }
    .nav-group-tab:active { transform: translateY(0); }
    .nav-group-tab.active {
      color: var(--color-primary, #1B6E45); font-weight: 600;
      background: var(--color-accent-tint, rgba(27,110,69,0.1));
      border-bottom-color: var(--color-accent, #1B6E45);
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
