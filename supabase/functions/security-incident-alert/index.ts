import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-alert-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const INCIDENT_ALERT_WEBHOOK_URL = Deno.env.get("INCIDENT_ALERT_WEBHOOK_URL") ?? "";
const INCIDENT_ALERT_SECRET = Deno.env.get("INCIDENT_ALERT_SECRET") ?? "";

function jsonResponse(status: number, payload: Record<string, unknown>) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

async function postWebhook(message: Record<string, unknown>) {
  if (!INCIDENT_ALERT_WEBHOOK_URL) return { ok: false, status: 0, body: "missing webhook" };
  const res = await fetch(INCIDENT_ALERT_WEBHOOK_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(message),
  });
  const body = await res.text();
  return { ok: res.ok, status: res.status, body };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse(405, { success: false, error: "Method not allowed" });

  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    return jsonResponse(500, { success: false, error: "Missing Supabase env secrets" });
  }

  const secret = req.headers.get("x-alert-secret") ?? "";
  if (!INCIDENT_ALERT_SECRET || secret !== INCIDENT_ALERT_SECRET) {
    return jsonResponse(401, { success: false, error: "Unauthorized" });
  }

  try {
    const body = await req.json();
    const mode = (body?.mode ?? "single").toString();
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    });

    if (mode === "single") {
      const incident = body?.incident ?? {};
      const msg = {
        text: `SECURITY INCIDENT [${incident?.severity ?? "medium"}] ${incident?.title ?? "Incident"}`,
        incident,
      };
      const r = await postWebhook(msg);
      return jsonResponse(r.ok ? 200 : 502, { success: r.ok, status: r.status, response: r.body });
    }

    // batch mode: push recent open high/critical incidents
    const { data, error } = await supabase
      .from("security_incidents")
      .select("*")
      .in("severity", ["high", "critical"])
      .in("status", ["open", "investigating"])
      .order("created_at", { ascending: false })
      .limit(20);

    if (error) {
      return jsonResponse(500, { success: false, error: error.message });
    }

    let sent = 0;
    for (const incident of data ?? []) {
      const msg = {
        text: `SECURITY INCIDENT [${incident.severity}] ${incident.title}`,
        incident,
      };
      const r = await postWebhook(msg);
      if (r.ok) sent += 1;
    }

    return jsonResponse(200, { success: true, scanned: (data ?? []).length, sent });
  } catch (e) {
    return jsonResponse(500, { success: false, error: (e as Error).message });
  }
});
