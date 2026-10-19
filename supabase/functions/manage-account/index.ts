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

  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: auth, error: authError } = await caller.auth.getUser();
  if (authError || !auth.user) return json({ error: "Invalid session" }, 401);

  const admin = createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: actor, error: actorError } = await admin
    .from("users")
    .select("role, school_id, is_active")
    .eq("id", auth.user.id)
    .single();
  if (actorError || !actor || actor.is_active === false) {
    return json({ error: "Active account required" }, 403);
  }
  if (actor.role !== "admin" && actor.role !== "teacher") {
    return json({ error: "Only administrators and teachers can manage accounts" }, 403);
  }

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return json({ error: "Request body must be valid JSON" }, 400);
  }
  if (!isRecord(payload)) return json({ error: "Invalid request body" }, 400);
  const body = payload;

  if (body.action === "create") {
    const fullName = typeof body.fullName === "string" ? body.fullName.trim() : "";
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    const password = typeof body.password === "string" ? body.password : "";
    const username = typeof body.username === "string" ? body.username.trim() : "";
    const requestedRole = typeof body.role === "string" ? body.role : "";
    const suffix = { admin: "A", teacher: "T", student: "S" }[
      requestedRole as "admin" | "teacher" | "student"
    ];
    if (
      !["admin", "teacher", "student"].includes(requestedRole) ||
      !suffix ||
      (actor.role === "teacher" && requestedRole !== "student")
    ) {
      return json({ error: "You cannot create an account with that role" }, 403);
    }
    if (
      fullName.length < 2 ||
      fullName.length > 100 ||
      fullName.trim().split(/\s+/).length < 2
    ) {
      return json({ error: "Enter first and last name (up to 100 characters)" }, 400);
    }
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      return json({ error: "Enter a valid email address" }, 400);
    }
    if (password.length < 8 || password.length > 128) {
      return json({ error: "Password must be between 8 and 128 characters" }, 400);
    }
    if (
      !/^[A-Z][a-z]{1,49}@[ATS]\.edu$/.test(username) ||
      !username.endsWith(`@${suffix}.edu`)
    ) {
      return json({ error: `Username must match Firstlastname@${suffix}.edu` }, 400);
    }
    const { data: existingUsername, error: usernameError } = await admin
      .from("users")
      .select("id")
      .ilike("username", username)
      .maybeSingle();
    if (usernameError) {
      return json({ error: "Could not check whether the username is available" }, 500);
    }
    if (existingUsername) {
      return json({ error: "That username is already in use. Add a different last name." }, 409);
    }

    let schoolId: string | null = null;
    let sectionId: string | null = null;
    if (requestedRole !== "admin") {
      schoolId = actor.role === "teacher"
        ? actor.school_id
        : typeof body.schoolId === "string"
        ? body.schoolId
        : null;
      if (!schoolId) return json({ error: "A school is required" }, 400);
      const { data: school, error: schoolError } = await admin
        .from("schools")
        .select("id")
        .eq("id", schoolId)
        .maybeSingle();
      if (schoolError) return json({ error: "Could not validate the school" }, 500);
      if (!school) return json({ error: "That school was not found" }, 400);
    }
    if (requestedRole === "student") {
      sectionId = typeof body.sectionId === "string" ? body.sectionId : null;
      if (!sectionId) return json({ error: "Choose a student grade and section" }, 400);
      const { data: section, error: sectionError } = await admin
        .from("sections")
        .select("id")
        .eq("id", sectionId)
        .eq("school_id", schoolId)
        .maybeSingle();
      if (sectionError) return json({ error: "Could not validate the class section" }, 500);
      if (!section) return json({ error: "That section is not in the selected school" }, 400);
    }

    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        full_name: fullName,
        username,
        requested_role: requestedRole,
        school_id: schoolId,
        section_id: sectionId,
      },
    });
    if (createError || !created.user) {
      const errorMessage = createError?.message ?? "Could not create account";
      if (errorMessage.toLowerCase().includes("database error saving new user")) {
        return json({
          error: "The database rejected account setup. Apply the latest username-format migration and confirm the username is unique and matches the selected role.",
        }, 400);
      }
      return json({ error: errorMessage }, 400);
    }

    const accountUpdates: Record<string, unknown> = {
      must_change_password: true,
    };
    if (actor.role === "admin" && requestedRole !== "student") {
      accountUpdates.role = requestedRole;
      accountUpdates.approval_status = "approved";
    }
    const { error: updateError } = await admin
        .from("users")
        .update(accountUpdates)
        .eq("id", created.user.id);
    if (updateError) {
      const { error: cleanupError } = await admin.auth.admin.deleteUser(created.user.id);
      return json({
        error: cleanupError
          ? "Could not finish account setup or clean up the incomplete account"
          : "Could not finish setting up the account",
      }, 500);
    }
    return json({ id: created.user.id, username });
  }

  if (body.action === "delete") {
    const userId = typeof body.userId === "string" ? body.userId : "";
    if (!userId || userId === auth.user.id) {
      return json({ error: "Choose another account to delete" }, 400);
    }
    const { data: target, error: targetError } = await admin
      .from("users")
      .select("role, school_id, requested_role")
      .eq("id", userId)
      .maybeSingle();
    if (targetError) return json({ error: "Could not load the account" }, 500);
    if (!target || !["student", "teacher"].includes(target.role)) {
      return json({ error: "Only student or teacher accounts can be deleted" }, 403);
    }
    if (
      actor.role === "teacher" &&
      (target.role !== "student" ||
        (target.requested_role != null && target.requested_role !== "student") ||
        !actor.school_id ||
        target.school_id !== actor.school_id)
    ) {
      return json({ error: "Teachers can delete only students from their school" }, 403);
    }
    const { data: profilePhotos, error: photosError } = await admin.storage
      .from("profile-photos")
      .list(userId);
    if (photosError) {
      return json({ error: "Could not clean up the account's profile photos" }, 500);
    }
    const photos = profilePhotos ?? [];
    if (photos.length > 0) {
      const { error: removePhotosError } = await admin.storage
        .from("profile-photos")
        .remove(photos.map((photo) => `${userId}/${photo.name}`));
      if (removePhotosError) {
        return json({ error: "Could not clean up the account's profile photos" }, 500);
      }
    }
    const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
    if (deleteError) return json({ error: "Could not delete the account" }, 500);
    return json({ success: true });
  }

  return json({ error: "Unsupported account action" }, 400);
});
