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

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceRoleKey) {
    return json({ error: "Function configuration is incomplete" }, 500);
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return json({ error: "Request body must be valid JSON" }, 400);
  }

  const username = typeof body.username === "string"
    ? body.username.trim()
    : "";
  const password = typeof body.password === "string" ? body.password : "";

  if (!username || !password) {
    return json({ error: "Username/email and password are required" }, 400);
  }

  const admin = createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const auth = createClient(url, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // 1. Look up profile in public.users by username OR email (case-insensitive)
  const { data: profile, error: profileError } = await admin
    .from("users")
    .select("id, email, username, is_active, approval_status, role")
    .or(`username.ilike.${username},email.ilike.${username}`)
    .maybeSingle();

  if (profile && profile.is_active === false) {
    return json({ error: "Account is disabled. Please contact the administrator." }, 403);
  }

  // Build candidate emails to try
  const candidates: string[] = [];
  if (profile?.email) {
    candidates.push(profile.email.trim().toLowerCase());
  }
  const direct = username.trim().toLowerCase();
  if (!candidates.includes(direct)) {
    candidates.push(direct);
  }

  // Also check admin aliases
  if (direct.startsWith("wondedev") || direct.startsWith("wondeadmin") || direct.includes("@admin.edu")) {
    if (!candidates.includes("wondedev369@gmail.com")) candidates.push("wondedev369@gmail.com");
    if (!candidates.includes("wondeadmin@admin.edu")) candidates.push("wondeadmin@admin.edu");
  }

  let lastError: any = null;
  for (const candidateEmail of candidates) {
    try {
      const { data, error } = await auth.auth.signInWithPassword({
        email: candidateEmail,
        password,
      });

      if (!error && data?.session) {
        return json({
          access_token: data.session.access_token,
          refresh_token: data.session.refresh_token,
          user: data.user,
        });
      }
      if (error) {
        lastError = error;
      }
    } catch (e) {
      lastError = e;
    }
  }

  return json({
    error: lastError?.message || "Invalid login credentials",
  }, 401);
});
