import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authorization = request.headers.get("Authorization");
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!authorization) return json({ error: "Authentication required" }, 401);
  if (!url || !anonKey || !serviceRoleKey) {
    return json({ error: "Function configuration is incomplete" }, 500);
  }

  const sessionClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: auth, error: authError } = await sessionClient.auth.getUser();
  if (authError || !auth.user) return json({ error: "Invalid session" }, 401);

  const admin = createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: actor, error: actorError } = await admin
    .from("users")
    .select("role")
    .eq("id", auth.user.id)
    .single();
  if (actorError || actor?.role !== "admin") {
    return json({ error: "Only an administrator can review role requests" }, 403);
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return json({ error: "Request body must be valid JSON" }, 400);
  }
  const userId = body.userId;
  const decision = body.decision;
  const schoolId = typeof body.schoolId === "string" ? body.schoolId.trim() : "";
  if (typeof userId !== "string" || !["approve", "reject"].includes(String(decision))) {
    return json({ error: "Invalid account review request" }, 400);
  }

  const { data: target, error: targetError } = await admin
    .from("users")
    .select("id, requested_role, approval_status")
    .eq("id", userId)
    .single();
  if (targetError || target?.approval_status !== "pending" ||
      !["teacher", "admin"].includes(String(target.requested_role))) {
    return json({ error: "This account has no pending elevated-role request" }, 404);
  }
  if (decision === "approve" && target.requested_role === "teacher" && !schoolId) {
    return json({ error: "A school ID is required to approve a teacher" }, 400);
  }
  if (decision === "approve" && target.requested_role === "teacher") {
    const { data: school, error: schoolError } = await admin
      .from("schools")
      .select("id")
      .eq("id", schoolId)
      .maybeSingle();
    if (schoolError) return json({ error: "Could not validate the school" }, 500);
    if (!school) return json({ error: "That school was not found" }, 400);
  }

  const updates = decision === "approve"
    ? {
      role: target.requested_role,
      approval_status: "approved",
      ...(target.requested_role === "teacher" ? { school_id: schoolId } : {}),
    }
    : { approval_status: "rejected" };
  const { error: updateError } = await admin
    .from("users")
    .update(updates)
    .eq("id", userId)
    .eq("approval_status", "pending");
  if (updateError) return json({ error: "Could not update account approval" }, 500);
  return json({ approvalStatus: decision === "approve" ? "approved" : "rejected" });
});
