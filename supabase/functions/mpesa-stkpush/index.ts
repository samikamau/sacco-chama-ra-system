// Supabase Edge Function: mpesa-stkpush (v2: log first, then prompt)
// Control: every payment request is saved as PENDING BEFORE the phone is prompted,
// so no money can be received without a record in subscription_payments.
// Deploy: npx supabase functions deploy mpesa-stkpush

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const BASE = Deno.env.get("MPESA_ENV") === "production"
  ? "https://api.safaricom.co.ke"
  : "https://sandbox.safaricom.co.ke";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

async function getToken(): Promise<string> {
  const key = Deno.env.get("MPESA_CONSUMER_KEY")!;
  const secret = Deno.env.get("MPESA_CONSUMER_SECRET")!;
  const res = await fetch(`${BASE}/oauth/v1/generate?grant_type=client_credentials`, {
    headers: { Authorization: "Basic " + btoa(`${key}:${secret}`) },
  });
  if (!res.ok) throw new Error("M-Pesa auth failed: " + (await res.text()));
  return (await res.json()).access_token;
}

// Kenya time (UTC+3) as YYYYMMDDHHmmss
function timestamp(): string {
  const d = new Date(Date.now() + 3 * 60 * 60 * 1000);
  return d.toISOString().replace(/[-:TZ.]/g, "").slice(0, 14);
}

// Accepts 0712345678, 712345678, +254712345678, 0112345678
function normalisePhone(p: string): string {
  let s = String(p).replace(/\D/g, "");
  if (s.startsWith("0")) s = "254" + s.slice(1);
  if (s.length === 9) s = "254" + s;
  if (!/^254(7|1)\d{8}$/.test(s)) throw new Error("Invalid Safaricom number");
  return s;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  let recordId: string | null = null;

  try {
    const { plan_id, phone, organisation_id } = await req.json();
    if (!plan_id || !organisation_id) throw new Error("plan_id and organisation_id are required");

    // Confirm the caller is a signed-in user
    const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
    if (userErr || !userData.user) throw new Error("Not signed in");
    // TODO: also confirm userData.user.id belongs to organisation_id using your membership table

    // Price comes from the database, not the browser
    const { data: plan, error: planErr } = await admin
      .from("subscription_plans").select("*")
      .eq("id", plan_id).eq("is_active", true).single();
    if (planErr || !plan) throw new Error("Plan not found");

    const amount = Math.round(Number(plan.price_kes));
    const msisdn = normalisePhone(phone);
    const accountRef = `${plan.app_code}-${String(organisation_id).slice(0, 5)}`.toUpperCase().slice(0, 12);

    // STEP 1: Save the request BEFORE contacting Safaricom
    const { data: rec, error: insErr } = await admin
      .from("subscription_payments")
      .insert({
        organisation_id,
        app_code: plan.app_code,
        plan_id: plan.id,
        channel: "STK",
        phone: msisdn,
        amount,
        account_reference: accountRef,
        status: "PENDING",
      })
      .select("id")
      .single();
    if (insErr || !rec) throw new Error("DB insert failed: " + (insErr?.message ?? "no record"));
    recordId = rec.id;

    // STEP 2: Send the STK push
    const shortcode = Deno.env.get("MPESA_SHORTCODE")!;
    const passkey = Deno.env.get("MPESA_PASSKEY")!;
    const ts = timestamp();

    const payload = {
      BusinessShortCode: shortcode,
      Password: btoa(shortcode + passkey + ts),
      Timestamp: ts,
      TransactionType: Deno.env.get("MPESA_TXN_TYPE") ?? "CustomerPayBillOnline", // Till: CustomerBuyGoodsOnline
      Amount: amount,
      PartyA: msisdn,
      PartyB: Deno.env.get("MPESA_PARTYB") ?? shortcode,                            // Till: till number
      PhoneNumber: msisdn,
      CallBackURL: Deno.env.get("MPESA_CALLBACK_URL")!,
      AccountReference: accountRef,
      TransactionDesc: "Subscription",
    };

    const token = await getToken();
    const res = await fetch(`${BASE}/mpesa/stkpush/v1/processrequest`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const data = await res.json();
    if (data.ResponseCode !== "0") {
      throw new Error(data.errorMessage ?? data.ResponseDescription ?? "STK push rejected");
    }

    // STEP 3: Attach Safaricom's IDs so the callback can find this record
    const { error: updErr } = await admin
      .from("subscription_payments")
      .update({
        merchant_request_id: data.MerchantRequestID,
        checkout_request_id: data.CheckoutRequestID,
        updated_at: new Date().toISOString(),
      })
      .eq("id", recordId);
    if (updErr) console.error("Could not attach CheckoutRequestID", recordId, updErr.message);

    return Response.json(
      { ok: true, checkout_request_id: data.CheckoutRequestID, message: data.CustomerMessage },
      { headers: cors },
    );
  } catch (e) {
    const msg = (e as Error).message;
    // If the record was saved but the prompt failed, mark it FAILED with the reason
    if (recordId) {
      await admin
        .from("subscription_payments")
        .update({ status: "FAILED", result_desc: msg, updated_at: new Date().toISOString() })
        .eq("id", recordId)
        .eq("status", "PENDING");
    }
    return Response.json({ ok: false, error: msg }, { status: 400, headers: cors });
  }
});
