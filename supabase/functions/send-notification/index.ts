// supabase/functions/send-notification/index.ts
//
// Deploy with:  supabase functions deploy send-notification
// Set the secret first: supabase secrets set RESEND_API_KEY=your_key_here
//
// Call from the frontend like:
//   await supabase.functions.invoke('send-notification', {
//     body: { to: 'member@example.com', subject: 'Contribution received', body: '<p>...</p>' }
//   });
//
// This function is intentionally the ONLY place the Resend API key exists.
// Never move this key into frontend code or a .env file that ships to Netlify.

import { serve } from "https://deno.land/std@0.203.0/http/server.ts";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const FROM_ADDRESS = "notifications@yourdomain.org"; // must be a domain verified in Resend

serve(async (req) => {
  try {
    const { to, subject, body } = await req.json();

    if (!to || !subject || !body) {
      return new Response(JSON.stringify({ error: "to, subject, and body are required" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const resendResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: FROM_ADDRESS,
        to: [to],
        subject,
        html: body,
      }),
    });

    const result = await resendResponse.json();

    if (!resendResponse.ok) {
      return new Response(JSON.stringify({ error: result }), {
        status: resendResponse.status,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ success: true, id: result.id }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
