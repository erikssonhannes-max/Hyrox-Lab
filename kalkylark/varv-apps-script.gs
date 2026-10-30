/**
 * VARV. – hämtar siffror från appen till kalkylarket.
 *
 * Läggs in i Google Kalkylark under Tillägg → Apps Script.
 * Den hemliga koden från supabase/stats.sql läggs under
 * Projektinställningar → Skriptegenskaper med namnet VARV_TOKEN.
 * Koden ska inte stå här i skriptet.
 */
const SUPABASE_URL = 'https://kwjnezbazyahyzsmpuyg.supabase.co';
const PUBLIC_KEY = 'sb_publishable_rsSw4ZNaOGdesoK8KkA55Q_1qZCngdD';

const FLIK = 'Varje månad';
const FORSTA_RAD = 7;          // första månaden (november 2026)
const KOLUMN_MANAD = 2;        // B
const KOLUMN_NYA = 3;          // C
const KOLUMN_AKTIVA = 4;       // D
const KOLUMN_PASS = 5;         // E

function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('VARV.')
    .addItem('Hämta siffror från appen', 'hamtaFranAppen')
    .addItem('Hämta automatiskt varje timme', 'startaAutomatik')
    .addItem('Sluta hämta automatiskt', 'stoppaAutomatik')
    .addToUi();
}

function hamtaFranAppen() {
  const token = PropertiesService.getScriptProperties().getProperty('VARV_TOKEN');
  if (!token) throw new Error('Lägg in VARV_TOKEN under Projektinställningar → Skriptegenskaper.');

  const svar = UrlFetchApp.fetch(SUPABASE_URL + '/rest/v1/rpc/varv_dashboard', {
    method: 'post',
    contentType: 'application/json',
    headers: { apikey: PUBLIC_KEY },
    payload: JSON.stringify({ p_token: token }),
    muteHttpExceptions: true
  });
  if (svar.getResponseCode() !== 200) {
    throw new Error('Kunde inte hämta från appen (' + svar.getResponseCode() + '): ' + svar.getContentText().slice(0, 200));
  }
  const rader = JSON.parse(svar.getContentText()).monthly;

  const blad = SpreadsheetApp.getActive().getSheetByName(FLIK);
  if (!blad) throw new Error('Hittar inte fliken "' + FLIK + '".');
  const antal = blad.getLastRow() - FORSTA_RAD + 1;
  const manader = blad.getRange(FORSTA_RAD, KOLUMN_MANAD, antal, 1).getValues()
    .map(r => r[0] instanceof Date ? Utilities.formatDate(r[0], 'Europe/Stockholm', 'yyyy-MM') : '');
  const forsta = manader[0];

  // Summera per månad. Allt före första månaden i arket räknas in i den.
  const perManad = {};
  rader.forEach(r => {
    let nyckel = String(r.month).slice(0, 7);
    if (nyckel < forsta) nyckel = forsta;
    const p = perManad[nyckel] || (perManad[nyckel] = { nya: 0, aktiva: 0, pass: 0 });
    p.nya += r.new_users;
    p.aktiva = Math.max(p.aktiva, r.active_users);
    p.pass += r.sessions;
  });

  const nu = Utilities.formatDate(new Date(), 'Europe/Stockholm', 'yyyy-MM');
  const ut = manader.map(m => {
    if (!m || m > nu) return ['', '', ''];
    const p = perManad[m] || { nya: 0, aktiva: 0, pass: 0 };
    return [p.nya, p.aktiva, p.pass];
  });
  blad.getRange(FORSTA_RAD, KOLUMN_NYA, antal, 3).setValues(ut).setBackground('#ffffff');

  // Visa att kolumnerna nu fylls i av appen.
  blad.getRange(FORSTA_RAD - 1, KOLUMN_NYA, 1, 3)
    .setValues([['Nya användare (från appen)', 'Aktiva användare (från appen)', 'Loggade pass (från appen)']]);
  blad.getRange(5, KOLUMN_MANAD)
    .setValue('Rosa = ni skriver   ·   Vitt = räknas ut eller hämtas från appen   ·   Senast hämtat ' +
      Utilities.formatDate(new Date(), 'Europe/Stockholm', 'd MMM HH:mm'));
}

function startaAutomatik() {
  stoppaAutomatik();
  ScriptApp.newTrigger('hamtaFranAppen').timeBased().everyHours(1).create();
  hamtaFranAppen();
  SpreadsheetApp.getActive().toast('Siffrorna hämtas nu automatiskt varje timme.', 'VARV.');
}

function stoppaAutomatik() {
  ScriptApp.getProjectTriggers()
    .filter(t => t.getHandlerFunction() === 'hamtaFranAppen')
    .forEach(t => ScriptApp.deleteTrigger(t));
}
