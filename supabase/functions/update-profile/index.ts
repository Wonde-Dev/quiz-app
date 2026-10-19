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

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
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

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return json({ error: "Request body must be valid JSON" }, 400);
  }
  if (!isRecord(payload)) return json({ error: "Invalid request body" }, 400);
  const body = payload;
  const fullName = typeof body.fullName === "string" ? body.fullName.trim() : null;
  const avatarPath = typeof body.avatarPath === "string" ? body.avatarPath : null;
  if (fullName === null && avatarPath === null) {
    return json({ error: "A profile change is required" }, 400);
  }
  if (fullName !== null && (fullName.length < 2 || fullName.length > 100)) {
    return json({ error: "Name must be between 2 and 100 characters" }, 400);
  }

  const adminClient = createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const updates: Record<string, string> = {};
  if (fullName !== null) updates.full_name = fullName;
  if (avatarPath !== null) {
    const expectedPrefix = `${auth.user.id}/`;
    const validPath = new RegExp(
      `^${auth.user.id}/avatar\\.(jpg|jpeg|png|webp)$`,
    ).test(avatarPath);
    if (!avatarPath.startsWith(expectedPrefix) || !validPath) {
      return json({ error: "Invalid profile photo path" }, 400);
    }
    const { data: files, error: storageError } = await adminClient.storage
      .from("profile-photos")
      .list(auth.user.id, { search: avatarPath.substring(expectedPrefix.length) });
    if (storageError) return json({ error: "Could not validate profile photo" }, 500);
    if (!files?.some((file) => file.name === avatarPath.substring(expectedPrefix.length))) {
      return json({ error: "Profile photo was not uploaded" }, 400);
    }
    const publicUrl = adminClient.storage
      .from("profile-photos")
      .getPublicUrl(avatarPath).data.publicUrl;
    updates.avatar_url = `${publicUrl}?v=${Date.now()}`;
  }
  const { error: updateError } = await adminClient
    .from("users")
    .update(updates)
    .eq("id", auth.user.id);
  if (updateError) return json({ error: "Could not update profile" }, 500);
  return json({ success: true });
});
