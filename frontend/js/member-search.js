// Reusable searchable member picker. Replaces a plain <select> with a
// text input that filters as you type ("member-search-input"), a hidden
// input holding the actual selected member id ("member-search-hidden"),
// and a dropdown list of matches. Nothing is selected by default.
//
// Usage: setupMemberSearch(inputId, hiddenId, listId, members, onChange)
//   inputId  - id of the visible text <input>
//   hiddenId - id of a hidden <input type="hidden"> that will hold the member id
//   listId   - id of an empty container <div> for the dropdown results
//   members  - array of { id, member_number, full_name }
//   onChange - optional callback(memberId | null), fired on selection or clear

function ensureMemberSearchStyles() {
  if (document.getElementById('member-search-styles')) return;
  const style = document.createElement('style');
  style.id = 'member-search-styles';
  style.textContent = `
    .member-search-list {
      display: none; position: absolute; z-index: 20; left: 0; right: 0; top: 100%;
      background: #fff; border: 1px solid var(--color-line, #ddd); border-radius: 6px;
      max-height: 220px; overflow-y: auto; box-shadow: 0 6px 16px rgba(0,0,0,0.1);
      margin-top: 2px;
    }
    .member-search-item { padding: 8px 12px; cursor: pointer; font-size: 13px; }
    .member-search-item:hover, .member-search-item.highlighted { background: var(--color-bg, #F7F6F3); }
    .member-search-empty { padding: 8px 12px; font-size: 13px; color: var(--color-muted, #888); }
  `;
  document.head.appendChild(style);
}

function setupMemberSearch(inputId, hiddenId, listId, members, onChange) {
  ensureMemberSearchStyles();
  const input = document.getElementById(inputId);
  const hidden = document.getElementById(hiddenId);
  const list = document.getElementById(listId);
  if (!input || !hidden || !list) return;

  list.classList.add('member-search-list');

  function render(query) {
    const q = (query || '').trim().toLowerCase();
    const matches = !q ? members.slice(0, 20) : members.filter(m =>
      m.full_name.toLowerCase().includes(q) || m.member_number.toLowerCase().includes(q)
    ).slice(0, 20);

    list.innerHTML = matches.length
      ? matches.map(m => `<div class="member-search-item" data-id="${m.id}">${m.member_number} — ${m.full_name}</div>`).join('')
      : `<div class="member-search-empty">No matching members</div>`;
    list.style.display = 'block';
  }

  input.addEventListener('focus', () => render(input.value));
  input.addEventListener('input', () => {
    if (hidden.value) { hidden.value = ''; if (onChange) onChange(null); }
    render(input.value);
  });

  list.addEventListener('mousedown', (e) => {
    const item = e.target.closest('.member-search-item');
    if (!item || !item.dataset.id) return;
    const m = members.find(x => x.id === item.dataset.id);
    if (!m) return;
    input.value = `${m.member_number} — ${m.full_name}`;
    hidden.value = m.id;
    list.style.display = 'none';
    if (onChange) onChange(m.id);
  });

  document.addEventListener('click', (e) => {
    if (e.target !== input && !list.contains(e.target)) list.style.display = 'none';
  });
}
