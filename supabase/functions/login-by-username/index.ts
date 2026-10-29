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
    ? body.username.trim().toLowerCase()
    : "";
  const password = typeof body.password === "string" ? body.password : "";
  const isEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(username);
  const isAppUsername = /^[a-z0-9]{1,50}@(admin|teacher|students?|a|t|s)\.edu$/.test(username);
  const isLegacyUsername = /^[a-z0-9.-]{2,64}$/.test(username);
  if ((!isEmail && !isAppUsername && !isLegacyUsername) || password.length === 0) {
    return json({ error: "Invalid username or password" }, 401);
  }

  const admin = createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  let targetEmail = username;
  if (!isEmail) {
    const { data: profile, error: profileError } = await admin
      .from("users")
      .select("email, is_active")
      .or(`username.ilike.${username},email.ilike.${username}`)
      .maybeSingle();
    if (profileError || !profile?.email || profile.is_active === false) {
      return json({ error: "Invalid username or password" }, 401);
    }
    targetEmail = profile.email;
  }

  const auth = createClient(url, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data, error } = await auth.auth.signInWithPassword({
    email: targetEmail,
    password,
  });
  if (error || !data.session) {
    return json({ error: "Invalid username or password" }, 401);
  }

  return json({
    access_token: data.session.access_token,
    refresh_token: data.session.refresh_token,
  });
});
