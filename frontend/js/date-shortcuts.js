/* =========================================================================
   Fast date entry.

   A native date input will not accept typed shortcuts: the browser owns the
   keystrokes. So each date field is replaced with a plain text box that
   parses what is typed, and the original input is kept as a hidden field
   holding the ISO value. Every page that already reads
   document.getElementById('f-date').value keeps working untouched.

   Shortcuts, in the order an accountant reaches for them:

     t          today
     y          yesterday
     + / -      a day forward or back, repeatable
     m          first day of this month
     e          last day of this month
     q          last day of last month
     30         the 30th of this month
     3001       30 January, this year
     30012026   30 January 2026
     300126     30 January 2026
     30/01/26   also 30-01-26 and 30.01.26

   Day comes before month throughout, as written in Kenya.
   ========================================================================= */

(function () {

  function pad(n) { return String(n).padStart(2, '0'); }

  function toISO(d) {
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
  }

  function fromISO(s) {
    if (!s) return null;
    const p = s.split('-');
    if (p.length !== 3) return null;
    const d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
    return isNaN(d) ? null : d;
  }

  function display(d) {
    return d ? pad(d.getDate()) + '/' + pad(d.getMonth() + 1) + '/' + d.getFullYear() : '';
  }

  // Two digits means this century, which is right for every date a member
  // payment will ever carry.
  function fullYear(y) {
    return y < 100 ? 2000 + y : y;
  }

  // Rejects 31 February rather than rolling it into March, which is the
  // sort of silent correction that puts a payment in the wrong period.
  function build(day, month, year) {
    const d = new Date(year, month - 1, day);
    if (d.getDate() !== day || d.getMonth() !== month - 1) return null;
    return d;
  }

  function parse(text, current) {
    const raw = (text || '').trim();
    if (!raw) return null;

    const today = new Date();
    const base = current || today;
    const key = raw.toLowerCase();

    if (key === 't' || key === 'today') return today;
    if (key === 'y' || key === 'yesterday') {
      const d = new Date(today); d.setDate(d.getDate() - 1); return d;
    }
    if (key === 'm') return new Date(base.getFullYear(), base.getMonth(), 1);
    if (key === 'e') return new Date(base.getFullYear(), base.getMonth() + 1, 0);
    if (key === 'q') return new Date(base.getFullYear(), base.getMonth(), 0);

    // Repeated + or - moves that many days, so "+++" is three days on.
    if (/^\++$/.test(key) || /^-+$/.test(key)) {
      const d = new Date(base);
      d.setDate(d.getDate() + (key[0] === '+' ? key.length : -key.length));
      return d;
    }
    // Or an explicit count: +7, -14
    const step = key.match(/^([+-])(\d+)$/);
    if (step) {
      const d = new Date(base);
      d.setDate(d.getDate() + (step[1] === '+' ? 1 : -1) * Number(step[2]));
      return d;
    }

    // Separated: 30/01/26, 30-1-2026, 30.01.2026
    const sep = key.match(/^(\d{1,2})[\/\-. ](\d{1,2})(?:[\/\-. ](\d{2,4}))?$/);
    if (sep) {
      return build(Number(sep[1]), Number(sep[2]),
                   sep[3] ? fullYear(Number(sep[3])) : base.getFullYear());
    }

    // Run together, length decides the meaning.
    if (/^\d+$/.test(key)) {
      if (key.length <= 2) {
        return build(Number(key), base.getMonth() + 1, base.getFullYear());
      }
      if (key.length === 4) {
        return build(Number(key.slice(0,2)), Number(key.slice(2,4)), base.getFullYear());
      }
      if (key.length === 6) {
        return build(Number(key.slice(0,2)), Number(key.slice(2,4)),
                     fullYear(Number(key.slice(4,6))));
      }
      if (key.length === 8) {
        return build(Number(key.slice(0,2)), Number(key.slice(2,4)),
                     Number(key.slice(4,8)));
      }
    }

    return null;
  }

  /* Upgrades one date input. The original keeps its id and its ISO value,
     so nothing that reads it needs to change. */
  function enableDateShortcuts(inputId, options) {
    const opts = options || {};
    const original = document.getElementById(inputId);
    if (!original || original.dataset.shortcutsOn === '1') return;

    const maxDate = opts.max ? fromISO(opts.max)
                  : (original.max ? fromISO(original.max) : null);
    const minDate = opts.min ? fromISO(opts.min)
                  : (original.min ? fromISO(original.min) : null);

    // The original becomes the hidden carrier of the ISO value.
    original.type = 'hidden';
    original.dataset.shortcutsOn = '1';

    const box = document.createElement('input');
    box.type = 'text';
    box.autocomplete = 'off';
    box.inputMode = 'numeric';
    box.placeholder = 'dd/mm/yyyy, or t for today';
    box.className = original.className;
    box.style.cssText = original.style.cssText;
    box.setAttribute('aria-label', opts.label || 'Date');
    original.parentNode.insertBefore(box, original.nextSibling);

    const note = document.createElement('div');
    note.style.cssText = 'font-size:11px;color:var(--color-muted);margin-top:3px;min-height:14px';
    note.textContent = '';
    box.parentNode.insertBefore(note, box.nextSibling);

    function show(d, message) {
      box.value = display(d);
      original.value = d ? toISO(d) : '';
      note.textContent = message || (d ? d.toLocaleDateString('en-KE',
        { weekday:'long', day:'numeric', month:'long', year:'numeric' }) : '');
      note.style.color = 'var(--color-muted)';
      // Anything else listening to the original field still hears about it.
      original.dispatchEvent(new Event('change', { bubbles: true }));
    }

    function reject(message) {
      note.textContent = message;
      note.style.color = 'var(--color-alert)';
    }

    function commit() {
      const current = fromISO(original.value);
      const d = parse(box.value, current);

      if (!d) {
        if (!box.value.trim()) { show(null, ''); return; }
        reject('Not a date. Try 30/01/2026, 30012026, or t for today.');
        return;
      }
      if (maxDate && d > maxDate) {
        reject('That date is later than ' + display(maxDate) + '.');
        return;
      }
      if (minDate && d < minDate) {
        reject('That date is earlier than ' + display(minDate) + '.');
        return;
      }
      show(d);
    }

    box.addEventListener('blur', commit);
    box.addEventListener('keydown', e => {
      if (e.key === 'Enter') { e.preventDefault(); commit(); }
      // Arrows nudge a day at a time without touching the keyboard's number row.
      if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
        e.preventDefault();
        const current = fromISO(original.value) || new Date();
        const d = new Date(current);
        d.setDate(d.getDate() + (e.key === 'ArrowUp' ? 1 : -1));
        if (maxDate && d > maxDate) return;
        if (minDate && d < minDate) return;
        show(d);
      }
    });
    box.addEventListener('focus', () => box.select());

    // Start from whatever the field already held.
    const starting = fromISO(original.value);
    if (starting) show(starting); else show(null, '');

    return {
      set: iso => show(fromISO(iso)),
      get: () => original.value,
    };
  }

  /* ---------------------------------------------------------------------
     Applies itself to every date field on the page, so a page only needs
     the script tag and nothing else. A field opts out with
     data-no-shortcuts, and one already upgraded is never touched twice.

     Drawers and tables build their fields after load, so new ones are
     picked up as they appear rather than only at startup.
     --------------------------------------------------------------------- */

  let autoId = 0;

  function upgradeAll(root) {
    const scope = root && root.querySelectorAll ? root : document;
    scope.querySelectorAll('input[type="date"]').forEach(el => {
      if (el.dataset.noShortcuts !== undefined) return;
      if (el.dataset.shortcutsOn === '1') return;
      // Needs an id to be addressable; one is given if the page omitted it.
      if (!el.id) el.id = 'date-auto-' + (++autoId);
      const label = el.closest('.field')?.querySelector('label')?.textContent?.replace('*','').trim();
      enableDateShortcuts(el.id, { label: label || 'Date' });
    });
  }

  function start() {
    upgradeAll(document);
    new MutationObserver(records => {
      for (const r of records) {
        for (const node of r.addedNodes) {
          if (node.nodeType !== 1) continue;
          if (node.matches && node.matches('input[type="date"]')) upgradeAll(node.parentNode);
          else upgradeAll(node);
        }
      }
    }).observe(document.body, { childList: true, subtree: true });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }

  window.enableDateShortcuts = enableDateShortcuts;
  window.parseDateShortcut = parse;
})();
