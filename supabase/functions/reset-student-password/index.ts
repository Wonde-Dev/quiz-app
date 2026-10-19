import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function temporaryPassword(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@$%";
  const cutoff = 256 - (256 % alphabet.length);
  let password = "";
  while (password.length < 20) {
    const bytes = crypto.getRandomValues(new Uint8Array(32));
    for (const byte of bytes) {
      if (byte >= cutoff) continue;
      password += alphabet[byte % alphabet.length];
      if (password.length === 20) break;
    }
  }
  return password;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers });
  }
  if (request.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers,
    });
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization) {
    return new Response(JSON.stringify({ error: "Authentication required" }), {
      status: 401,
      headers,
    });
  }

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceRoleKey) {
    return new Response(JSON.stringify({ error: "Function configuration is incomplete" }), {
      status: 500,
      headers,
    });
  }

  const callerClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: authData, error: authError } = await callerClient.auth.getUser();
  if (authError || !authData.user) {
    return new Response(JSON.stringify({ error: "Invalid session" }), {
      status: 401,
      headers,
    });
  }

  const adminClient = createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: actor, error: actorError } = await adminClient
    .from("users")
    .select("role, school_id, is_active, full_name")
    .eq("id", authData.user.id)
    .single();
  if (actorError || !actor || actor.is_active === false ||
      !["admin", "teacher"].includes(actor.role)) {
    return new Response(JSON.stringify({ error: "Only teachers and administrators can reset passwords" }), {
      status: 403,
      headers,
    });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: "Request body must be valid JSON" }), {
      status: 400,
      headers,
    });
  }
  const accountIds =
    body != null && typeof body === "object" && !Array.isArray(body) &&
        "accountIds" in body
      ? body.accountIds
      : body != null && typeof body === "object" && !Array.isArray(body) &&
          "studentIds" in body
      ? body.studentIds
      : null;
  if (
    !Array.isArray(accountIds) ||
    accountIds.length === 0 ||
    accountIds.length > 100 ||
    accountIds.some((id) => typeof id !== "string")
  ) {
    return new Response(JSON.stringify({ error: "Select between 1 and 100 accounts" }), {
      status: 400,
      headers,
    });
  }

  const distinctIds = [...new Set(accountIds as string[])];
  const results: Array<{ accountId: string; username: string; temporaryPassword: string }> = [];
  const failures: Array<{ accountId: string; error: string }> = [];
  const activityWarnings: string[] = [];

  for (const accountId of distinctIds) {
    if (accountId === authData.user.id) {
      failures.push({ accountId, error: "You cannot reset your own password from account management" });
      continue;
    }
    const { data: student, error: studentError } = await adminClient
      .from("users")
      .select("id, username, full_name, role, school_id, must_change_password, requested_role")
      .eq("id", accountId)
      .single();
    if (
      studentError ||
      !student ||
      !["student", "teacher", "admin"].includes(student.role) ||
      (actor.role === "teacher" &&
        (student.role !== "student" ||
          (student.requested_role != null && student.requested_role !== "student") ||
          !actor.school_id ||
          student.school_id !== actor.school_id))
    ) {
      failures.push({
        accountId,
        error: actor.role === "teacher"
          ? "Student not found or not in your school"
          : "Account not found",
      });
      continue;
    }

    const password = temporaryPassword();
    const { error: flagError } = await adminClient
      .from("users")
      .update({ must_change_password: true })
      .eq("id", accountId);
    if (flagError) {
      failures.push({ accountId, error: "Could not mark the account for a password change" });
      continue;
    }

    const { error: passwordError } = await adminClient.auth.admin.updateUserById(
      accountId,
      { password },
    );
    if (passwordError) {
      const { error: rollbackError } = await adminClient
        .from("users")
        .update({ must_change_password: student.must_change_password ?? false })
        .eq("id", accountId);
      failures.push({
        accountId,
        error: rollbackError
          ? "Password reset failed and account state needs administrator review"
          : "Password reset failed",
      });
      continue;
    }
    results.push({
      accountId,
      username: student.username ?? accountId,
      temporaryPassword: password,
    });
    const { error: activityError } = await adminClient.from("audit_logs").insert({
      action: "password_reset",
      performed_by: authData.user.id,
      target_user: accountId,
      details: {
        actor_name: actor.full_name,
        target_name: student.full_name ?? student.username ?? accountId,
      },
    });
    if (activityError) {
      activityWarnings.push(
        `${student.username ?? accountId}: password reset succeeded, but activity could not be recorded`,
      );
    }
  }

  return new Response(JSON.stringify({ results, failures, activityWarnings }), {
    status: 200,
    headers,
  });
});
