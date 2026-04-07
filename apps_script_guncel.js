// ================================================
// Altın Asistanım — BİST 100 + Tam Otomasyon (GÜNCEL)
// Truncgil (Altın/Döviz) + CoinGecko (Kripto) + Google Finance (Borsa) + Binance (Fallback)
// FİX: Sayı format sorunu, borsa geçmişi kaydetme, BIST 100 tam liste
// ================================================

const KALIBRASYON_SHEET = 'Kalibrasyon';
const GECMIS_SHEET      = 'Geçmiş';
const SAATLIK_GECMIS    = 'Saatlik';
const BORSA_CANLI       = 'Borsa Canlı';
const BORSA_GECMIS      = 'Borsa Geçmiş';

// ------------------------------------------------
// BIST 100 TAM LİSTE (2025-2026 Dönemi)
// ------------------------------------------------
const BIST100 = [
  'AEFES','AGESA','AKBNK','AKFGY','AKFYE','AKSA','AKSEN','ALARK','ALFAS','ALGYO',
  'ARCLK','ASELS','ASTOR','BERA','BIMAS','BRISA','BRYAT','BUCIM','CCOLA','CEMTS',
  'CIMSA','CWENE','DOHOL','ECILC','EGEEN','EKGYO','ENJSA','ENKAI','EREGL','EUPWR',
  'FROTO','GARAN','GENIL','GUBRF','HALKB','HEKTS','ISCTR','ISGYO','KCHOL','KLSER',
  'KMPUR','KONTR','KONYA','KOZAA','KOZAL','KRDMD','KZBGY','MAVI','MGROS','MPARK',
  'OBAMS','ODAS','OTKAR','OYAKC','PETKM','PGSUS','SAHOL','SASA','SELEC','SISE',
  'SKBNK','SMRTG','SOKM','TAVHL','TCELL','THYAO','TKFEN','TOASO','TSKB','TTKOM',
  'TTRAK','TUBIL','TUPRS','TURSG','ULKER','VAKBN','VESBE','VESTL','YKBNK','ZOREN',
  'AGHOL','ANSGR','BASGZ','BIOEN','BTCIM','CANTE','DOAS','ESSEN','GESAN','GLYHO',
  'GOLTS','INDES','IPEKE','KAYSE','KERVT','KONKA','LIDER','LOGO','MAGEN','NETAS',
  'NUGYO','OSMEN','PAPIL','PENTA','QUAGR','RGYAS','SARKY','SNGYO','TABGD','TMSN'
];

// ------------------------------------------------
// UYGULAMADAKİ ALTIN VE DÖVİZ EMTİALARI
// ------------------------------------------------
const ASSET_MAP = {
  'has':       { key: 'HAS' },
  'gram':      { key: 'GRA' },
  'gram22':    { key: 'YIA' },
  'ceyrek':    { key: 'CEYREKALTIN' },
  'yarim':     { key: 'YARIMALTIN' },
  'tam':       { key: 'TAMALTIN' },
  'ata':       { key: 'ATAALTIN' },
  'resat':     { key: 'RESATALTIN' },
  'hamit':     { key: 'HAMITALTIN' },
  'gremse':    { key: 'GREMSEALTIN' },
  'bilezik14': { key: '14AYARALTIN' },
  'silver':    { key: 'GUMUS' },
  'ons':       { key: 'ONS' },
  'usd':       { key: 'USD' },
  'eur':       { key: 'EUR' },
  'gbp':       { key: 'GBP' }
};

const FALLBACK_COEFFS = {
  'has':       { sell: 1.0566, buy: 1.0346 },
  'gram':      { sell: 1.0566, buy: 1.0243 },
  'gram22':    { sell: 1.0624, buy: 1.0010 },
  'ceyrek':    { sell: 1.1885, buy: 1.0663 },
  'yarim':     { sell: 1.0953, buy: 1.0696 },
  'tam':       { sell: 1.0597, buy: 1.0428 },
  'ata':       { sell: 1.0599, buy: 1.0340 },
  'resat':     { sell: 1.0599, buy: 1.0340 },
  'hamit':     { sell: 1.0599, buy: 1.0340 },
  'gremse':    { sell: 1.0643, buy: 1.0224 },
  'bilezik14': { sell: 1.2990, buy: 0.9620 },
  'silver':    { sell: 1.0705, buy: 0.9806 },
  'ons':       { sell: 1.0000, buy: 1.0000 },
  'usd':       { sell: 1.0000, buy: 1.0000 },
  'eur':       { sell: 1.0000, buy: 1.0000 },
  'gbp':       { sell: 1.0000, buy: 1.0000 }
};

// ------------------------------------------------
// YARDIMCI FONKSİYONLAR
// ------------------------------------------------
function parseNum(v) {
  let s = String(v ?? 0).trim();
  if (/^\d{1,3}(\.\d{3})+(,\d+)?$/.test(s)) {
    s = s.replace(/\./g, '').replace(',', '.');
  } else {
    s = s.replace(',', '.');
  }
  return parseFloat(s) || 0;
}

function round2(n) {
  return Math.round(n * 100) / 100;
}

// FIX: Sayıyı noktayla yazılacak şekilde zorla (Türkçe locale sorununu önler)
function forceNumber(val) {
  let n = parseFloat(val);
  return isNaN(n) ? 0 : n;
}

function loadCoeffs() {
  const props  = PropertiesService.getScriptProperties();
  const coeffs = {};
  Object.keys(ASSET_MAP).forEach(k => {
    const stored = props.getProperty('coeff_' + k);
    coeffs[k] = stored ? JSON.parse(stored) : FALLBACK_COEFFS[k];
  });
  return coeffs;
}

function saveCoeffs(coeffs) {
  const props = PropertiesService.getScriptProperties();
  Object.keys(coeffs).forEach(k => {
    props.setProperty('coeff_' + k, JSON.stringify(coeffs[k]));
  });
}

function fetchWithRetry(url, options = {}, maxRetries = 3) {
  for (let i = 0; i < maxRetries; i++) {
    try {
      const res = UrlFetchApp.fetch(url, options);
      if (res.getResponseCode() === 200) {
        return JSON.parse(res.getContentText());
      }
    } catch (e) {
      Utilities.sleep(1000);
    }
  }
  return null;
}

// ------------------------------------------------
// CANLI VERİ: Truncgil + CoinGecko + Binance Fallback
// ------------------------------------------------
function fetchCanliVeriler() {
  let veri = {};

  let truncData = fetchWithRetry('https://finans.truncgil.com/v4/today.json', { headers: { 'User-Agent': 'Mozilla/5.0' }, muteHttpExceptions: true });
  if (truncData) veri = truncData;

  let cryptoData = fetchWithRetry('https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum&vs_currencies=usd&include_24hr_change=true', { muteHttpExceptions: true });
  if (cryptoData) {
    if (cryptoData.bitcoin) veri['BTC'] = { 'Selling': cryptoData.bitcoin.usd, 'Buying': cryptoData.bitcoin.usd, 'Change': cryptoData.bitcoin.usd_24h_change };
    if (cryptoData.ethereum) veri['ETH'] = { 'Selling': cryptoData.ethereum.usd, 'Buying': cryptoData.ethereum.usd, 'Change': cryptoData.ethereum.usd_24h_change };
  }

  let binanceOns = fetchWithRetry('https://api.binance.com/api/v3/ticker/price?symbol=PAXGUSDT', { muteHttpExceptions: true });
  if (binanceOns && binanceOns.price) {
     if(!veri['ONS']) veri['ONS'] = { 'Selling': parseFloat(binanceOns.price), 'Buying': parseFloat(binanceOns.price), 'Change': 0 };
  }

  return veri;
}

// ------------------------------------------------
// MANUEL KALİBRASYON
// ------------------------------------------------
function computeCoeffs(refPrices, canliVeri) {
  const coeffs = {};
  Object.keys(ASSET_MAP).forEach(ourKey => {
    const cfg = ASSET_MAP[ourKey];
    const ref = refPrices[ourKey];
    const apiItem = canliVeri[cfg.key];
    if (!ref || !apiItem) { coeffs[ourKey] = null; return; }
    const apiSell = parseNum(apiItem['Selling']);
    const apiBuy  = parseNum(apiItem['Buying']);
    if (!apiSell) { coeffs[ourKey] = null; return; }
    coeffs[ourKey] = {
      sell: Math.round((ref.sell / apiSell) * 10000) / 10000,
      buy:  apiBuy > 0 ? Math.round((ref.buy / apiBuy) * 10000) / 10000 : FALLBACK_COEFFS[ourKey].buy
    };
  });
  return coeffs;
}

function runManualCalibration() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let kSheet = ss.getSheetByName(KALIBRASYON_SHEET);
  if (!kSheet) return;
  const lastRow = kSheet.getLastRow();
  if (lastRow < 2) return;
  const rows = kSheet.getRange(2, 1, lastRow - 1, 3).getValues();
  const refPrices = {};
  rows.forEach(r => {
    const kod  = String(r[0]).trim().toLowerCase();
    const sell = parseNum(r[1]);
    const buy  = parseNum(r[2]);
    if (kod && sell > 0) refPrices[kod] = { sell, buy };
  });
  if (Object.keys(refPrices).length === 0) return;
  const canliVeri = fetchCanliVeriler();
  const newCoeffs = computeCoeffs(refPrices, canliVeri);
  const current   = loadCoeffs();
  Object.keys(newCoeffs).forEach(k => {
    if (newCoeffs[k]) current[k] = newCoeffs[k];
  });
  saveCoeffs(current);
  kSheet.getRange(1, 5).setValue('Son kalibrasyon:');
  kSheet.getRange(1, 6).setValue(new Date().toLocaleString('tr-TR'));
  fetchAndUpdatePrices();
}

// ------------------------------------------------
// YAPISTIRMA TETİKLEYİCİ
// ------------------------------------------------
function autoTetikleyiciler(e) {
  if (!e) return;
  const sheet = e.source.getActiveSheet();
  const sheetName = sheet.getName();

  if (sheetName === KALIBRASYON_SHEET) {
    runManualCalibration();
  }

  if (sheetName === BORSA_CANLI && e.range.getColumn() === 1 && e.range.getRow() > 1) {
    const hisseKodu = String(e.value).trim().toUpperCase();
    const row = e.range.getRow();
    if (hisseKodu && hisseKodu !== 'UNDEFINED') {
      sheet.getRange(row, 2).setFormula('=IFERROR(GOOGLEFINANCE("IST:' + hisseKodu + '";"price");"")');
      sheet.getRange(row, 3).setFormula('=IFERROR(GOOGLEFINANCE("IST:' + hisseKodu + '";"changepct")/100;"")');
    } else {
      sheet.getRange(row, 2).clearContent();
      sheet.getRange(row, 3).clearContent();
    }
  }
}

// ------------------------------------------------
// ANA FİYAT GÜNCELLEME (Her 5 dakikada bir)
// FIX: Sayı formatı düzeltmesi — noktayla yazım garantisi
// ------------------------------------------------
function fetchAndUpdatePrices() {
  const sheet  = SpreadsheetApp.getActiveSpreadsheet().getSheets()[0];
  const coeffs = loadCoeffs();

  try {
    const data       = fetchCanliVeriler();
    const gramChange = parseNum(data['GRA']?.['Change']);
    const lastRow    = sheet.getLastRow();
    if (lastRow < 2) return;

    const hasCol4  = sheet.getLastColumn() >= 4;
    const colCount = hasCol4 ? 3 : 2;
    const kodRange = sheet.getRange(2, 1, lastRow - 1, 1).getValues();
    const writeData = sheet.getRange(2, 2, lastRow - 1, colCount).getValues();

    for (let i = 0; i < kodRange.length; i++) {
      const kod = String(kodRange[i][0]).trim().toLowerCase();

      if (kod === 'btc' || kod === 'eth') {
          if (data[kod.toUpperCase()]) {
             writeData[i][0] = forceNumber(data[kod.toUpperCase()]['Selling']);
             writeData[i][1] = forceNumber(data[kod.toUpperCase()]['Buying']);
             if (hasCol4) writeData[i][2] = forceNumber(data[kod.toUpperCase()]['Change']) / 100;
          }
          continue;
      }

      const cfg = ASSET_MAP[kod];
      if (!cfg || !data[cfg.key]) continue;

      const coeff   = coeffs[kod] || FALLBACK_COEFFS[kod];
      const item    = data[cfg.key];
      const rawSell = parseNum(item['Selling']);
      const rawBuy  = parseNum(item['Buying']);
      let   change  = parseNum(item['Change']);

      if (!rawSell) continue;
      if (!change && change !== 0) change = gramChange;

      writeData[i][0] = round2(rawSell * coeff.sell);
      writeData[i][1] = round2(rawBuy  * coeff.buy);
      if (hasCol4) writeData[i][2] = change / 100;
    }

    sheet.getRange(2, 2, lastRow - 1, colCount).setValues(writeData);

  } catch(e) {}
}

// ------------------------------------------------
// GECE 23:00 — ALTIN/KRİPTO GEÇMİŞİ
// FIX: Sayı formatı plain number olarak kaydedilir
// ------------------------------------------------
function kaydetGecmis() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const canliSheet = ss.getSheets()[0];
  let gecmisSheet = ss.getSheetByName(GECMIS_SHEET);

  if (!gecmisSheet) {
    gecmisSheet = ss.insertSheet(GECMIS_SHEET);
    gecmisSheet.appendRow(['TARİH']);
    gecmisSheet.setFrozenRows(1);
  }

  const lastRow = canliSheet.getLastRow();
  if (lastRow < 2) return;

  const data = canliSheet.getRange(2, 1, lastRow - 1, 2).getValues();
  const tarih = Utilities.formatDate(new Date(), "GMT+3", "yyyy-MM-dd");

  let headers = gecmisSheet.getRange(1, 1, 1, Math.max(1, gecmisSheet.getLastColumn())).getValues()[0].map(h => String(h).trim().toUpperCase());
  gecmisSheet.getRange(1, 1, 1, headers.length).setValues([headers]);

  const priceMap = {};
  data.forEach(row => {
    const kod = String(row[0]).trim().toUpperCase();
    const fiyat = forceNumber(row[1]);
    if (kod && fiyat > 0) {
      priceMap[kod] = fiyat;
      if (!headers.includes(kod)) {
        headers.push(kod);
        gecmisSheet.getRange(1, headers.length).setValue(kod).setFontWeight('bold').setBackground('#f3f3f3');
      }
    }
  });

  let targetRow = -1;
  const histLastRow = gecmisSheet.getLastRow();
  if (histLastRow >= 2) {
    const mevcutTarihler = gecmisSheet.getRange(2, 1, histLastRow - 1, 1).getValues();
    for (let i = 0; i < mevcutTarihler.length; i++) {
      const t = mevcutTarihler[i][0];
      const tarihStr = t instanceof Date ? Utilities.formatDate(t, "GMT+3", "yyyy-MM-dd") : String(t).trim();
      if (tarihStr === tarih) { targetRow = i + 2; break; }
    }
  }

  if (targetRow > -1) {
    const existingData = gecmisSheet.getRange(targetRow, 1, 1, headers.length).getValues()[0];
    for (let i = 1; i < headers.length; i++) {
      if (priceMap[headers[i]] !== undefined) existingData[i] = priceMap[headers[i]];
    }
    gecmisSheet.getRange(targetRow, 1, 1, headers.length).setValues([existingData]);
  } else {
    const newRow = new Array(headers.length).fill('');
    newRow[0] = tarih;
    for (let i = 1; i < headers.length; i++) {
      if (priceMap[headers[i]] !== undefined) newRow[i] = priceMap[headers[i]];
    }
    gecmisSheet.insertRowBefore(2);
    gecmisSheet.getRange(2, 1, 1, newRow.length).setValues([newRow]);
  }

  kaydetBorsaGecmis();
}

// ------------------------------------------------
// HER SAAT BAŞI — SAATLİK VERİ (Son 24 saat)
// FIX: Sayı formatı düzeltmesi
// ------------------------------------------------
function kaydetSaatlikVeri() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const canliSheet = ss.getSheets()[0];
  let saatlikSheet = ss.getSheetByName(SAATLIK_GECMIS);

  if (!saatlikSheet) {
    saatlikSheet = ss.insertSheet(SAATLIK_GECMIS);
    saatlikSheet.appendRow(['TARİH/SAAT']);
    saatlikSheet.setFrozenRows(1);
  }

  const lastRow = canliSheet.getLastRow();
  if (lastRow < 2) return;

  const data = canliSheet.getRange(2, 1, lastRow - 1, 2).getValues();
  const zaman = Utilities.formatDate(new Date(), "GMT+3", "yyyy-MM-dd HH:00");

  let headers = saatlikSheet.getRange(1, 1, 1, Math.max(1, saatlikSheet.getLastColumn())).getValues()[0].map(h => String(h).trim().toUpperCase());
  saatlikSheet.getRange(1, 1, 1, headers.length).setValues([headers]);

  const priceMap = {};
  data.forEach(row => {
    const kod = String(row[0]).trim().toUpperCase();
    const fiyat = forceNumber(row[1]);
    if (kod && fiyat > 0) {
      priceMap[kod] = fiyat;
      if (!headers.includes(kod)) {
        headers.push(kod);
        saatlikSheet.getRange(1, headers.length).setValue(kod).setFontWeight('bold').setBackground('#eef2f3');
      }
    }
  });

  let targetRow = -1;
  const toplamSatir = saatlikSheet.getLastRow();
  if (toplamSatir >= 2) {
    const mevcutZamanlar = saatlikSheet.getRange(2, 1, toplamSatir - 1, 1).getValues();
    for (let i = 0; i < mevcutZamanlar.length; i++) {
      const z = mevcutZamanlar[i][0];
      const zamanStr = z instanceof Date ? Utilities.formatDate(z, "GMT+3", "yyyy-MM-dd HH:00") : String(z).trim();
      if (zamanStr === zaman) { targetRow = i + 2; break; }
    }
  }

  if (targetRow > -1) {
    const existingData = saatlikSheet.getRange(targetRow, 1, 1, headers.length).getValues()[0];
    let updated = false;
    for (let i = 1; i < headers.length; i++) {
      if ((existingData[i] === '' || existingData[i] === null || existingData[i] === 0) && priceMap[headers[i]] !== undefined) {
        existingData[i] = priceMap[headers[i]];
        updated = true;
      }
    }
    if (updated) saatlikSheet.getRange(targetRow, 1, 1, headers.length).setValues([existingData]);
  } else {
    const newRow = new Array(headers.length).fill('');
    newRow[0] = zaman;
    for (let i = 1; i < headers.length; i++) {
      if (priceMap[headers[i]] !== undefined) newRow[i] = priceMap[headers[i]];
    }
    saatlikSheet.insertRowBefore(2);
    saatlikSheet.getRange(2, 1, 1, newRow.length).setValues([newRow]);

    const newTotal = saatlikSheet.getLastRow();
    if (newTotal > 25) {
      saatlikSheet.deleteRows(26, newTotal - 25);
    }
  }
}

// ------------------------------------------------
// GECE 23:00 — BORSA GEÇMİŞİ
// FIX: SpreadsheetApp.flush() ile GOOGLEFINANCE yüklenmesini bekle
// FIX: Değer kontrolünü güçlendir
// ------------------------------------------------
function kaydetBorsaGecmis() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const bCanli = ss.getSheetByName(BORSA_CANLI);
  const bGecmis = ss.getSheetByName(BORSA_GECMIS);

  if(!bCanli || !bGecmis) return;

  // FIX: GOOGLEFINANCE formüllerinin hesaplanmasını bekle
  SpreadsheetApp.flush();
  Utilities.sleep(3000); // 3 saniye ekstra bekle
  SpreadsheetApp.flush();

  const lastRow = bCanli.getLastRow();
  if(lastRow < 2) return;

  // 3 sütun oku: Hisse Kodu, Canlı Fiyat, Değişim
  const data = bCanli.getRange(2, 1, lastRow - 1, 2).getDisplayValues();
  const tarih = Utilities.formatDate(new Date(), "GMT+3", "yyyy-MM-dd");

  let headers = bGecmis.getRange(1, 1, 1, Math.max(1, bGecmis.getLastColumn())).getValues()[0].map(h => String(h).trim().toUpperCase());
  if (headers[0] === '' || headers[0] === 'TARİH') headers[0] = 'TARİH';

  // Aynı gün kaydı var mı kontrol et
  const histLastRow = bGecmis.getLastRow();
  if (histLastRow >= 2) {
    const mevcutTarihler = bGecmis.getRange(2, 1, histLastRow - 1, 1).getValues();
    for (let i = 0; i < mevcutTarihler.length; i++) {
      const t = mevcutTarihler[i][0];
      const tarihStr = t instanceof Date ? Utilities.formatDate(t, "GMT+3", "yyyy-MM-dd") : String(t).trim();
      if (tarihStr === tarih) return; // Bugün zaten kaydedilmiş
    }
  }

  const priceMap = {};
  let validCount = 0;
  data.forEach(row => {
    const ticker = String(row[0]).trim().toUpperCase();
    // FIX: getDisplayValues ile gelen string'i parse et
    const price = parseNum(row[1]);
    if(ticker && price > 0 && ticker !== '#N/A' && ticker !== '#HATA') {
      priceMap[ticker] = price;
      validCount++;
      if(!headers.includes(ticker)) {
        headers.push(ticker);
        bGecmis.getRange(1, headers.length).setValue(ticker).setFontWeight('bold').setBackground('#eef2f3');
      }
    }
  });

  // En az 5 geçerli hisse yoksa kaydetme (GOOGLEFINANCE yüklenememiş olabilir)
  if (validCount < 5) return;

  const newRow = new Array(headers.length).fill('');
  newRow[0] = tarih;
  for(let i = 1; i < headers.length; i++) {
    const ticker = String(headers[i]).trim().toUpperCase();
    if(priceMap[ticker] !== undefined) {
      newRow[i] = priceMap[ticker];
    }
  }

  bGecmis.insertRowBefore(2);
  bGecmis.getRange(2, 1, 1, newRow.length).setValues([newRow]);
}

// ------------------------------------------------
// BORSA CANLI SAYFASINI BIST 100 İLE DOLDUR
// ------------------------------------------------
function setupBorsaSheets() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();

  let bCanli = ss.getSheetByName(BORSA_CANLI);
  if (!bCanli) {
    bCanli = ss.insertSheet(BORSA_CANLI);
  }

  // Başlıkları ayarla
  bCanli.getRange('A1').setValue('Hisse Kodu');
  bCanli.getRange('B1').setValue('Canlı Fiyat (TL)');
  bCanli.getRange('C1').setValue('Değişim (%)');
  bCanli.getRange('A1:C1').setFontWeight('bold').setBackground('#eef2f3');

  // Mevcut verileri temizle (başlık hariç)
  const existingLastRow = bCanli.getLastRow();
  if (existingLastRow > 1) {
    bCanli.getRange(2, 1, existingLastRow - 1, 3).clearContent();
  }

  // BIST 100 tüm hisseleri ekle
  BIST100.forEach((hisse, index) => {
    const row = index + 2;
    bCanli.getRange(row, 1).setValue(hisse);
    bCanli.getRange(row, 2).setFormula('=IFERROR(GOOGLEFINANCE("IST:' + hisse + '";"price");"")');
    bCanli.getRange(row, 3).setFormula('=IFERROR(GOOGLEFINANCE("IST:' + hisse + '";"changepct")/100;"")');
  });

  bCanli.getRange('B2:B').setNumberFormat('#,##0.00');
  bCanli.getRange('C2:C').setNumberFormat('0.00%');
  bCanli.setFrozenRows(1);
  bCanli.autoResizeColumns(1, 3);

  // Borsa Geçmiş sayfası
  let bGecmis = ss.getSheetByName(BORSA_GECMIS);
  if (!bGecmis) {
    bGecmis = ss.insertSheet(BORSA_GECMIS);
    const headers = ['TARİH'].concat(BIST100);
    bGecmis.appendRow(headers);
    bGecmis.getRange(1, 1, 1, headers.length).setFontWeight('bold').setBackground('#eef2f3');
    bGecmis.setFrozenRows(1);
  }
}

// ------------------------------------------------
// KALİBRASYON SAYFASI KURULUMU
// ------------------------------------------------
function setupKalibrasyonSheet() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  if (ss.getSheetByName(KALIBRASYON_SHEET)) return;
  const ks = ss.insertSheet(KALIBRASYON_SHEET);
  ks.getRange(1, 1, 1, 4).setValues([['Emtia Kodu', 'Satış', 'Alış', 'Değişim']]);
  ks.getRange(1, 1, 1, 4).setFontWeight('bold').setBackground('#f3f3f3');
  const emtialar = Object.keys(ASSET_MAP).map(k => [k, '', '', '']);
  ks.getRange(2, 1, emtialar.length, 4).setValues(emtialar);
  ks.setFrozenRows(1);
  ks.autoResizeColumns(1, 4);
}

// ------------------------------------------------
// İLK KURULUM — BİR KEZ ÇALIŞTIR
// ------------------------------------------------
function setupTriggers() {
  ScriptApp.getProjectTriggers().forEach(t => ScriptApp.deleteTrigger(t));

  // Her 5 Dakikada Canlı Veri
  ScriptApp.newTrigger('fetchAndUpdatePrices')
    .timeBased().everyMinutes(5).create();

  // Her Saat Başı Saatlik Kayıt
  ScriptApp.newTrigger('kaydetSaatlikVeri')
    .timeBased().everyHours(1).create();

  // Hücre Düzenleme Tetikleyici
  ScriptApp.newTrigger('autoTetikleyiciler')
    .forSpreadsheet(SpreadsheetApp.getActiveSpreadsheet())
    .onEdit().create();

  // Her Gece 23:00 Günlük Kapanış
  ScriptApp.newTrigger('kaydetGecmis')
    .timeBased().everyDays(1).atHour(23).create();

  setupKalibrasyonSheet();
  setupBorsaSheets();
  runManualCalibration();
}
