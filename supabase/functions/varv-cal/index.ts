// VARV. – träningsplanen som kalender att prenumerera på.
// Länken innehåller en hemlig nyckel per användare: …/functions/v1/varv-cal?t=NYCKEL
// Slå av "Enforce JWT verification" för funktionen, annars kan Kalender inte hämta den.
import { createClient } from "npm:@supabase/supabase-js@2";

const SB = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

Deno.serve(async (req) => {
  const t = new URL(req.url).searchParams.get("t") || "";
  if (!/^[0-9a-f]{32}$/.test(t)) return new Response("Saknas", { status: 404 });
  const { data } = await SB.from("cal_feeds").select("ics").eq("token", t).maybeSingle();
  if (!data || !data.ics) return new Response("Saknas", { status: 404 });
  return new Response(data.ics, {
    headers: { "Content-Type": "text/calendar; charset=utf-8", "Cache-Control": "max-age=1800", "Content-Disposition": 'inline; filename="varv.ics"' },
  });
});
