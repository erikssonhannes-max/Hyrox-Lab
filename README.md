# VARV.

Träningsapp för Hyrox: stationsguider, plan efter måltid, splittider, racetidtagning med ljud, röst och vibration, logg och racepass för Garmin. Fungerar offline när sidan väl laddats.

VARV. är ett fristående projekt och har ingen koppling till HYROX.

Följ VARV.: [TikTok](https://www.tiktok.com/@varvtraining) · [LinkedIn](https://www.linkedin.com/company/varv)

Intern statistik: [/intern/](https://varvtraining.com/intern/) (kräver kod, se `supabase/stats.sql`).

## Inloggning med Supabase

Appen fungerar utan konto. När Supabase är inkopplat kan man skapa konto och logga in, och då sparas pass, rekord och inställningar i kontot och följer med mellan enheter. Det man loggat på enheten innan flyttas till kontot vid första inloggningen.

Sätt upp det så här:

1. Skapa ett projekt på supabase.com.
2. Öppna SQL Editor, klistra in innehållet i `supabase/schema.sql` och kör det.
3. Under Authentication → URL Configuration: sätt Site URL till `https://varvtraining.com/` och lägg till samma adress under Redirect URLs (lägg även till `http://localhost:8000/` om du testar lokalt).
4. Kopiera projektets URL och publika nyckel (anon eller publishable) till `supabase-config.js`. Använd aldrig service_role- eller secret-nyckeln.
5. Valfritt, Google: slå på Google under Authentication → Providers med klient-id och hemlighet från Google Cloud Console och sätt `google: true` i `supabase-config.js`.
6. Valfritt, inloggning med kod: lägg till `{{ .Token }}` i mallen Magic Link under Authentication → Emails, så får man en sexsiffrig kod i mejlet. Det behövs på iPhone när appen ligger på hemskärmen, eftersom länkar i mejl öppnas i Safari och inte i appen.

Inloggningssätt: e-post och lösenord, kod eller länk via e-post, glömt lösenord och Google.

## Konto, integritet och säkerhet

- På hemsidan måste man skapa konto efter startanimationen. Man godkänner villkoren, samtycker till att träningsdata sparas och intygar att man är 16 år eller äldre. Samtycket sparas på kontot.
- Integritetspolicy: `legal/integritet.html`. Användarvillkor: `legal/villkor.html`.
- Radera konto i Profil → Konto. Kräver att `supabase/konto.sql` körts i Supabase.
- Rekommenderade inställningar i Supabase under Authentication: Confirm email på, minsta lösenordslängd 8, Site URL och Redirect URLs satta till hemsidan.
- Profiler, användarnamn#kod, vänner och profilbilder: kör `supabase/profiler.sql` i Supabase.
