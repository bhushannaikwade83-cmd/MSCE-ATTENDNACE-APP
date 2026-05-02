const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

function jsonResponse(status: number, payload: Record<string, unknown>) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

async function sha256Hex(message: string): Promise<string> {
  const msgBuffer = new TextEncoder().encode(message);
  const hashBuffer = await crypto.subtle.digest("SHA-256", msgBuffer);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}

function mergeFullName(
  full: string,
  first?: string,
  middle?: string,
  last?: string,
): string {
  const parts = [first, middle, last].map((s) => (s ?? "").toString().trim()).filter((p) => p.length > 0);
  const joined = parts.join(" ").replace(/\s+/g, " ").trim();
  const fromFields = joined.length > 0 ? joined : "";
  const fromFull = full.trim();
  if (fromFull.length > 0) return fromFull;
  return fromFields.length > 0 ? fromFields : "Staff";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse(405, { success: false, error: "Method not allowed" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceKey) {
    return jsonResponse(500, { success: false, error: "Server misconfigured" });
  }

  const adminClient = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (!jwt) {
      return jsonResponse(401, { success: false, error: "Unauthorized" });
    }

    const { data: userData, error: userErr } = await adminClient.auth.getUser(jwt);
    if (userErr || !userData?.user) {
      return jsonResponse(401, { success: false, error: "Invalid session" });
    }

    const callerId = userData.user.id;

    const { data: prof, error: profErr } = await adminClient
      .from("profiles")
      .select("role, institute_id, status")
      .eq("id", callerId)
      .maybeSingle();

    if (profErr || !prof) {
      return jsonResponse(403, { success: false, error: "Profile not found" });
    }

    const role = (prof.role ?? "").toString();
    const st = (prof.status ?? "").toString().toLowerCase();
    if (role !== "admin" || !["approved", "active"].includes(st)) {
      return jsonResponse(403, { success: false, error: "Only institute admins can add institute instructors" });
    }

    const adminInstituteId = prof.institute_id as string;
    if (!adminInstituteId) {
      return jsonResponse(403, { success: false, error: "Admin has no institute" });
    }

    const body = await req.json().catch(() => null) as Record<string, unknown> | null;
    if (!body) {
      return jsonResponse(400, { success: false, error: "Invalid JSON body" });
    }

    const instituteKey = (body.instituteKey ?? body.institute_id ?? "").toString().trim();
    const pin = (body.pin ?? "").toString().trim();
    const fullNameRaw = (body.fullName ?? body.full_name ?? "").toString();
    const first = (body.firstName ?? body.first_name ?? "").toString().trim();
    const middle = (body.middleName ?? body.middle_name ?? "").toString().trim();
    const last = (body.lastName ?? body.last_name ?? "").toString().trim();

    if (!first || !middle || !last) {
      return jsonResponse(400, {
        success: false,
        error: "First name, middle name, and last name are all required.",
      });
    }

    const mobileDigits = ((body.mobile ?? body.phone ?? body.phone_number ?? "") as string).toString().replace(/\D/g, "");
    if (mobileDigits.length < 10 || mobileDigits.length > 15) {
      return jsonResponse(400, {
        success: false,
        error: "Enter a valid mobile number (10–15 digits).",
      });
    }

    const fullName = mergeFullName(fullNameRaw, first, middle, last);
    if (fullName.length < 2 || fullName.length > 200) {
      return jsonResponse(400, { success: false, error: "Invalid full name length" });
    }

    if (!/^\d{4}$/.test(pin)) {
      return jsonResponse(400, { success: false, error: "PIN must be 4 digits" });
    }

    const { data: inst, error: instErr } = await adminClient
      .from("institutes")
      .select("id, name, institute_code")
      .or(`id.eq.${instituteKey},institute_code.eq.${instituteKey}`)
      .limit(1)
      .maybeSingle();

    if (instErr || !inst?.id) {
      return jsonResponse(400, { success: false, error: "Institute not found for that ID" });
    }

    const instId = inst.id as string;
    if (instId !== adminInstituteId) {
      return jsonResponse(403, { success: false, error: "You can only add users to your own institute" });
    }

    const pinHash = await sha256Hex(pin);
    const { data: pinClashRows, error: pinClashErr } = await adminClient
      .from("profiles")
      .select("id")
      .eq("institute_id", instId)
      .eq("pin_hash", pinHash)
      .limit(1);

    if (pinClashErr) {
      return jsonResponse(500, { success: false, error: "Could not verify PIN uniqueness" });
    }
    if (pinClashRows && pinClashRows.length > 0) {
      return jsonResponse(409, {
        success: false,
        error:
          "This PIN is already in use in your institute. Use a different PIN for the institute instructor.",
      });
    }

    const { count, error: cntErr } = await adminClient
      .from("profiles")
      .select("id", { count: "exact", head: true })
      .eq("institute_id", instId)
      .eq("role", "attendance_user");

    if (cntErr) {
      return jsonResponse(500, { success: false, error: "Could not verify instructor count" });
    }
    const maxInstructors = 4;
    if ((count ?? 0) >= maxInstructors) {
      return jsonResponse(409, {
        success: false,
        error: `This institute already has the maximum of ${maxInstructors} institute instructors. Remove one before adding another.`,
      });
    }

    const instituteName = (inst.name ?? "").toString();
    const emailLocal = `att.${instId}.${crypto.randomUUID().replace(/-/g, "").slice(0, 16)}`;
    const email = `${emailLocal}@staff.msce-attendance.app`;
    const password = `${pin}|${instId}|msceStaffV2`;

    const { data: created, error: createErr } = await adminClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        institute_id: instId,
        institute_name: instituteName,
        app_role: "attendance_user",
        full_name: fullName,
        phone_number: mobileDigits,
      },
    });

    if (createErr || !created?.user?.id) {
      const msg = createErr?.message ?? "Could not create user";
      if (msg.toLowerCase().includes("already")) {
        return jsonResponse(409, {
          success: false,
          error: "Institute instructor login already exists for this institute. Use Dashboard → Auth to remove the old user if needed.",
        });
      }
      return jsonResponse(400, { success: false, error: msg });
    }

    const newId = created.user.id;

    const { error: updErr } = await adminClient.from("profiles").update({
      pin_hash: pinHash,
      pin_set_at: new Date().toISOString(),
      has_pin: true,
      phone_number: mobileDigits,
    }).eq("id", newId);

    if (updErr) {
      await adminClient.auth.admin.deleteUser(newId);
      return jsonResponse(500, { success: false, error: "Profile PIN sync failed; user was not created" });
    }

    return jsonResponse(200, {
      success: true,
      userId: newId,
      email,
      message: "Institute instructor created",
    });
  } catch (e) {
    return jsonResponse(500, { success: false, error: (e as Error).message });
  }
});
