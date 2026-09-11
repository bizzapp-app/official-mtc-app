// Supabase Edge Function: admin-create-user
// Requires caller JWT of an active administrator.
// Uses SERVICE ROLE only on the server — never expose to the browser.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing Authorization" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user: caller },
      error: callerErr,
    } = await userClient.auth.getUser();
    if (callerErr || !caller) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: callerProfile } = await admin
      .from("profiles")
      .select("role, status")
      .eq("id", caller.id)
      .maybeSingle();

    const role = callerProfile?.role;
    const active = (callerProfile?.status || "active") === "active";
    if (!active || role !== "administrator") {
      return new Response(JSON.stringify({ error: "Only administrators can create users" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const username = String(body.username || "").trim().toLowerCase();
    const password = String(body.password || "");
    const full_name = String(body.full_name || "").trim();
    const userRole = String(body.role || "student").toLowerCase();
    const title = String(body.title || "");
    const phone = String(body.phone || "");
    const status = String(body.status || "active");

    const allowed = [
      "administrator",
      "principal",
      "registrar",
      "finance_officer",
      "lecturer",
      "librarian",
      "reception",
      "student",
    ];
    if (!username || !/^[a-z0-9._-]{3,32}$/.test(username) || !password || password.length < 8 || !full_name) {
      return new Response(JSON.stringify({ error: "full_name, username, and password (min 8) are required; username may contain letters, numbers, dots, underscores and hyphens." }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    if (!allowed.includes(userRole)) {
      return new Response(JSON.stringify({ error: "Invalid role" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    // There is one bootstrap administrator. New administrator accounts are not created from the portal.
    if (userRole === "administrator") {
      return new Response(JSON.stringify({ error: "Administrator accounts are bootstrapped directly in Supabase. The portal creates non-administrator accounts." }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const email = `${username}@portal.mercylife.local`;
    const { data: existingProfile } = await admin.from("profiles").select("id").eq("username", username).maybeSingle();
    if (existingProfile) {
      return new Response(JSON.stringify({ error: "That username is already in use." }), { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email, password, email_confirm: true, user_metadata: { full_name, role: userRole, title, username }
    });

    if (createErr || !created.user) {
      return new Response(JSON.stringify({ error: createErr?.message || "Auth user creation failed" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { error: profileErr } = await admin.from("profiles").upsert({
      id: created.user.id,
      email,
      username,
      full_name,
      role: userRole,
      title,
      phone,
      status,
    });

    if (profileErr) {
      await admin.auth.admin.deleteUser(created.user.id);
      return new Response(JSON.stringify({ error: profileErr.message }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    await admin.from("audit_logs").insert({
      user_email: caller.email || "admin",
      action: "CREATE_USER",
      details: `Created ${userRole} account ${username}`,
    });

    return new Response(
      JSON.stringify({
        user: {
          id: created.user.id,
          email,
          full_name,
          role: userRole,
          title,
          phone,
          status,
        },
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: e?.message || "Server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
