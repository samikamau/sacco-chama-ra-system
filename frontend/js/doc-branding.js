// doc-branding.js
// Shared helper for applying an organisation's own colors and logo to
// printable outputs (member statements, financial reports). This is
// deliberately separate from nav.js: the app's own UI (sidebar, dashboard,
// buttons) always stays Edhafu-branded, only documents handed to an
// organisation's own members/stakeholders use that organisation's identity.

// Fetches the current organisation's saved branding. Returns nulls for
// anything not customized, so callers can fall back to Edhafu defaults.
async function getDocBranding() {
  const fallback = { primaryColor: null, accentColor: null, logoUrl: null };
  try {
    if (typeof currentOrg !== 'function') return fallback;
    const org = await currentOrg();
    if (!org) return fallback;
    const { data } = await supabaseClient.from('organisations')
      .select('brand_primary_color, brand_accent_color, logo_path')
      .eq('id', org.organisation_id).single();
    if (!data) return fallback;
    let logoUrl = null;
    if (data.logo_path) {
      const { data: urlData } = supabaseClient.storage.from('org-logos').getPublicUrl(data.logo_path);
      logoUrl = urlData ? urlData.publicUrl : null;
    }
    return {
      primaryColor: data.brand_primary_color || null,
      accentColor: data.brand_accent_color || null,
      logoUrl,
    };
  } catch (e) {
    return fallback;
  }
}

// Applies branding to a document's printable area. Pass the container
// element that wraps the statement/report (so the color override doesn't
// leak into the surrounding app chrome, sidebar, nav, etc.), plus the
// element that should hold the logo image (an existing <img> or a <div>
// to insert one into).
//
// Usage:
//   const branding = await getDocBranding();
//   applyDocBranding(branding, {
//     scopeEl: document.getElementById('statement-print-area'),
//     logoEl: document.getElementById('statement-logo-slot'),
//   });
function applyDocBranding(branding, { scopeEl, logoEl } = {}) {
  if (!branding) return;

  if (scopeEl && (branding.primaryColor || branding.accentColor)) {
    if (branding.primaryColor) scopeEl.style.setProperty('--color-primary', branding.primaryColor);
    if (branding.accentColor) scopeEl.style.setProperty('--color-accent', branding.accentColor);
  }

  if (logoEl && branding.logoUrl) {
    if (logoEl.tagName === 'IMG') {
      logoEl.src = branding.logoUrl;
      logoEl.alt = 'Organisation logo';
    } else {
      logoEl.innerHTML = `<img src="${branding.logoUrl}" alt="Organisation logo" style="height:48px;max-width:220px;object-fit:contain">`;
    }
  }
}
