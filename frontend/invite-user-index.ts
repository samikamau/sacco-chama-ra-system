// invite-user
// Creates (or finds) the auth user for an invited email address and sends
// them a link to set their own password. Replaces the old flow, which
// asked an administrator to create logins by hand in the Supabase
// dashboard and then pass the person a link themselves.
//
// The caller must be an org_admin of the organisation they are inviting
// into; that is checked against the database, not trusted from the client.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { email, organisation_id, redirect_to } = await req.json();

    if (!email || !organisation_id) {
      return json({ error: "email and organisation_id are required" }, 400);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // 1. Who is calling? Use their own token so RLS and auth.uid() apply.
    const callerClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user: caller }, error: callerError } = await callerClient.auth.getUser();
    if (callerError || !caller) {
      return json({ error: "Not signed in" }, 401);
    }

    // 2. Is the caller actually an admin of this organisation?
    const admin = createClient(supabaseUrl, serviceKey);
    const { data: membership } = await admin
      .from("organisation_users")
      .select("role, status")
      .eq("organisation_id", organisation_id)
      .eq("user_id", caller.id)
      .maybeSingle();

    if (!membership || membership.role !== "org_admin" || membership.status !== "active") {
      return json({ error: "Only an organisation administrator can invite users" }, 403);
    }

    // 3. Create the auth user, or reuse the existing one if this email
    //    already has a login (someone in another organisation, say).
    const redirectTo = redirect_to || "https://edhafu.com/ledgers/reset-password.html";

    const { data: invited, error: inviteError } = await admin.auth.admin
      .inviteUserByEmail(email, { redirectTo });

    if (inviteError) {
      const alreadyExists = (inviteError.message || "").toLowerCase().includes("already");
      if (!alreadyExists) {
        return json({ error: inviteError.message }, 400);
      }
      // Existing account: send a set-password link instead of a new invite,
      // so they can still get in without an admin doing anything manually.
      const { error: linkError } = await admin.auth.resetPasswordForEmail(email, { redirectTo });
      if (linkError) return json({ error: linkError.message }, 400);
      return json({ ok: true, existing_account: true });
    }

    return json({ ok: true, existing_account: false, user_id: invited?.user?.id ?? null });
  } catch (e) {
    return json({ error: String(e?.message ?? e) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
