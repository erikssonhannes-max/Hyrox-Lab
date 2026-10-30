/* VARV. – koppling till Supabase.
   Fyll i från Supabase: Project Settings → API (eller "Connect").
   Nyckeln ska vara den publika (anon / publishable), aldrig service_role eller secret.
   Den publika nyckeln får ligga i koden – det är radnivåskyddet i databasen som skyddar datan.
   Så länge värdena nedan inte är ifyllda körs appen som förut, utan inloggning. */
window.VARV_SUPABASE = {
  url: "https://kwjnezbazyahyzsmpuyg.supabase.co",
  anonKey: "sb_publishable_rsSw4ZNaOGdesoK8KkA55Q_1qZCngdD",
  google: false // sätt till true när Google är påslaget under Authentication → Providers
};
