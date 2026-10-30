/* VARV. – koppling till Supabase.
   Fyll i från Supabase: Project Settings → API (eller "Connect").
   Nyckeln ska vara den publika (anon / publishable), aldrig service_role eller secret.
   Den publika nyckeln får ligga i koden – det är radnivåskyddet i databasen som skyddar datan.
   Så länge värdena nedan inte är ifyllda körs appen som förut, utan inloggning. */
window.VARV_SUPABASE = {
  url: "https://kwjnezbazyahyzsmpuyg.supabase.co",
  anonKey: "sb_publishable_rsSw4ZNaOGdesoK8KkA55Q_1qZCngdD",
  pushKey: "BKngCUNxkMao_gb9Zlpo97GmuYHNvhWmOXMg9AIuwPQEi9frf1S9awn-wFB8ERsy7-LqlU3ctAUwQITxpF_n_Po", // publik nyckel för notiser (VAPID)
  google: false // sätt till true när Google är påslaget under Authentication → Providers
};
