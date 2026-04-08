import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'modeller.dart';

class PiyasaMotoru {
  final Function onUpdate;

  // Ek dinleyiciler (detay sayfası vb.)
  final List<void Function()> _extraListeners = [];
  void addListener(void Function() cb) => _extraListeners.add(cb);
  void removeListener(void Function() cb) => _extraListeners.remove(cb);
  void _notifyAll() {
    onUpdate();
    for (final cb in List.of(_extraListeners)) {
      cb();
    }
  }

  List<AssetType> market = [];
  bool isLoading = true;
  bool isPrimaryEngineActive = false;
  bool isLiveConnection = false;
  double currentUsdRate = 0.0;

  List<PortfolioItem> debts = [];
  List<PortfolioItem> credits = [];
  PortfolioItem wallet = PortfolioItem(
      id: "me",
      personName: "Kişisel Kasa",
      isCredit: true,
      assets: {},
      date: DateTime.now());

  List<Map<String, dynamic>> historyData = [];
  Map<String, Map<String, dynamic>> assetHistory = {};
  List<Map<String, dynamic>> intraDayHistory = [];

  double liveNetWorth = 0;
  double liveWalletVal = 0;
  double liveCreditVal = 0;
  double liveDebtVal = 0;

  /// Sheets'ten okunan güncel sürüm bilgisi (Canlı Kur B21)
  String sheetVersion = '';

  Timer? _refreshTimer;
  Timer? _simulationTimer;
  final Random _random = Random();
  DateTime? _lastFetchTime;

  // Google Sheets geçmiş veri URL'si (geçmiş sekmesi)
  static const String _sheetsHistoryUrl =
      'https://docs.google.com/spreadsheets/d/1hXX1HmhjTGihxapua3D9iV3gq0kNRufy2ZQDD7HykeU/export?format=csv&gid=1578620279';

  // Google Sheets saatlik veri URL'si (saatlik sekmesi)
  static const String _sheetsSaatlikUrl =
      'https://docs.google.com/spreadsheets/d/1hXX1HmhjTGihxapua3D9iV3gq0kNRufy2ZQDD7HykeU/export?format=csv&gid=395501293';

  PiyasaMotoru({required this.onUpdate});

  /// Portföy değerlerini yeniden hesaplar.
  /// [notify] true ise onUpdate() çağırır (UI güncellenir).
  /// Manuel setState yapan yerlerden notify: false ile çağır.
  void recalcLiveValues({bool notify = false}) {
    _syncCustomAssets();
    // TL her zaman 1₺ = 1₺
    final tlIdx = market.indexWhere((e) => e.id == "tl");
    if (tlIdx >= 0) {
      market[tlIdx].sellPrice = 1;
      market[tlIdx].buyPrice = 1;
      market[tlIdx].baseSellPrice = 1;
      market[tlIdx].baseBuyPrice = 1;
    }
    liveWalletVal = wallet.getTotalValue(market);
    liveCreditVal =
        credits.fold(0, (sum, i) => sum + i.getTotalValue(market));
    liveDebtVal = debts.fold(0, (sum, i) => sum + i.getTotalValue(market));
    liveNetWorth = liveWalletVal + liveCreditVal - liveDebtVal;
    if (notify) onUpdate();
  }

  void baslat() {
    _initializeMarketSkeleton();
    loadMarketOrder();
    loadAllUserData().then((_) async {
      // 1. Önce cache'den hızlı aç (eski verilerle anında göster)
      await loadMarketCache();
      recalcLiveValues(notify: true);

      // 2. Sonra 1 kez veri çek, matrix başlat
      await fetchLiveData();
      recalcLiveValues(notify: true);
      _lastFetchTime = DateTime.now();
      // Sheets'ten geçmiş + saatlik verileri çek, sonra boşlukları doldur
      _fetchHistoricalFromSheets().then((_) => fillHistoricalGaps());
      _fetchIntraDayFromSheets();
    });

    // 5 dakikada bir veri çek (arada sadece matrix çalışır)
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      fetchLiveData(silent: true).then((_) {
        _lastFetchTime = DateTime.now();
      });
    });
    // İlk veri gelene kadar 3 saniye bekle, sonra simulation başlat
    Future.delayed(const Duration(seconds: 3), () {
      _startTickerSimulation();
    });
  }

  void kapat() {
    _refreshTimer?.cancel();
    _simulationTimer?.cancel();
  }

  void _syncCustomAssets() {
    final g22Idx = market.indexWhere((e) => e.id == "gram22");
    final ygIdx = market.indexWhere((e) => e.id == "yarim_gram22");
    if (g22Idx >= 0 && ygIdx >= 0) {
      final gram22 = market[g22Idx];
      final yarimGram = market[ygIdx];
      yarimGram.baseSellPrice = gram22.baseSellPrice / 2;
      yarimGram.baseBuyPrice = gram22.baseBuyPrice / 2;
      yarimGram.sellPrice = gram22.sellPrice / 2;
      yarimGram.buyPrice = gram22.buyPrice / 2;
    }
  }

  // Sabit emtialar
  static const _neverTick = {'tl', 'usd', 'eur', 'gbp'};
  // Hafta sonu da çalışanlar
  static const _weekendActive = {'btc', 'eth', 'ons'};

  void _startTickerSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (!isLiveConnection) return;

      final now = DateTime.now();
      final weekendRestricted = now.weekday == DateTime.saturday ||
          (now.weekday == DateTime.sunday && now.hour < 20);

      for (var asset in market) {
        if (_neverTick.contains(asset.id)) continue;
        if (asset.baseSellPrice <= 0) continue;
        if (weekendRestricted && !_weekendActive.contains(asset.id)) continue;

        // USD bazlı varlıklar (BTC, ETH, ONS) için oransal hareket
        double maxStep = asset.isDollarBase
            ? asset.baseSellPrice * 0.0004
            : asset.baseSellPrice * 0.0002;
        double step = (_random.nextDouble() - 0.5) * 2.0 * maxStep;
        double maxDev = asset.isDollarBase
            ? asset.baseSellPrice * 0.001
            : min(10.0, asset.baseSellPrice * 0.002);
        double newSell = (asset.sellPrice + step).clamp(
            asset.baseSellPrice - maxDev, asset.baseSellPrice + maxDev);

        double r = (newSell - asset.baseSellPrice) / asset.baseSellPrice;
        asset.sellPrice = newSell;
        asset.buyPrice = asset.baseBuyPrice * (1 + r);
        if (asset.isDollarBase && asset.baseUsdPrice > 0) {
          asset.usdPrice = asset.baseUsdPrice * (1 + r);
        }
      }

      _syncCustomAssets();
      _notifyAll();
    });
  }

  // --- KARMA MOTOR: ÖNCE BİNANCE (HIZLI) → SONRA SHEETS (YAVAŞ, ARKA PLAN) ---
  // 5 dakikada 1 çeker, arada matrix simülasyonu çalışır
  Future<void> fetchLiveData({bool silent = false, bool force = false}) async {
    // Son çekimden 5 dakika geçmediyse ve zorla değilse atla
    if (silent && !force && _lastFetchTime != null) {
      final elapsed = DateTime.now().difference(_lastFetchTime!);
      if (elapsed.inMinutes < 5) return;
    }

    if (!silent) {
      isLoading = true;
      onUpdate();
    }

    try {
      // ── 1. ADIM: BİNANCE (hızlı, önce gelsin) ──
      bool binanceOk = await _fetchBinanceData();

      if (binanceOk) {
        isPrimaryEngineActive = true;
        isLiveConnection = true;
        _lastFetchTime = DateTime.now();
        _syncCustomAssets();
        updateDailyHistory();
        saveMarketCache();
        // Matrix hemen başlasın, Sheets'i beklemesin
        onUpdate();
      }

      // ── 2. ADIM: SHEETS (yavaş, arka planda 30sn sonra) ──
      _scheduleSheetsUpdate();
    } catch (e) {
      isLiveConnection = false;
    } finally {
      if (!silent) {
        isLoading = false;
        onUpdate();
      }
    }
  }

  // Sheets verisini 1 saniye sonra arka planda çek (Binance'i beklemesin)
  void _scheduleSheetsUpdate() {
    Future.delayed(const Duration(seconds: 1), () async {
      await _fetchSheetsData();
    });
  }

  // ── BİNANCE: Döviz + Kripto + ONS (hızlı) ──
  Future<bool> _fetchBinanceData() async {
    try {
      final results = await Future.wait([
        http.get(Uri.parse(
            'https://api.binance.com/api/v3/ticker/24hr?symbol=USDTTRY'))
            .timeout(const Duration(seconds: 5),
                onTimeout: () => http.Response('', 408)),
        http.get(Uri.parse(
            'https://api.binance.com/api/v3/ticker/24hr?symbol=EURUSDT'))
            .timeout(const Duration(seconds: 5),
                onTimeout: () => http.Response('', 408)),
        http.get(Uri.parse(
            'https://api.binance.com/api/v3/ticker/24hr?symbol=PAXGUSDT'))
            .timeout(const Duration(seconds: 5),
                onTimeout: () => http.Response('', 408)),
        http.get(Uri.parse(
            'https://api.binance.com/api/v3/ticker/24hr?symbol=BTCUSDT'))
            .timeout(const Duration(seconds: 5),
                onTimeout: () => http.Response('', 408)),
        http.get(Uri.parse(
            'https://api.binance.com/api/v3/ticker/24hr?symbol=ETHUSDT'))
            .timeout(const Duration(seconds: 5),
                onTimeout: () => http.Response('', 408)),
        http.get(Uri.parse(
            'https://api.binance.com/api/v3/ticker/24hr?symbol=GBPUSDT'))
            .timeout(const Duration(seconds: 5),
                onTimeout: () => http.Response('', 408)),
      ]);

      if (results[0].statusCode != 200) return false;

      final usdData = json.decode(results[0].body);
      double usdTry = double.parse(usdData['lastPrice']);
      double usdChange = double.parse(usdData['priceChangePercent']);
      currentUsdRate = usdTry;

      for (var a in market) {
        if (a.id == 'usd') {
          a.applyNewPrices(
              usdTry * a.sellMarkup, usdTry * a.buyMarkup, usdChange);
        }
      }

      if (results[1].statusCode == 200) {
        final d = json.decode(results[1].body);
        double eurUsd = double.parse(d['lastPrice']);
        double eurChange = double.parse(d['priceChangePercent']);
        double eurTry = eurUsd * usdTry;
        for (var a in market) {
          if (a.id == 'eur') {
            a.applyNewPrices(
                eurTry * a.sellMarkup, eurTry * a.buyMarkup, eurChange);
          }
        }
      }

      if (results[2].statusCode == 200) {
        final d = json.decode(results[2].body);
        double goldOnsUsd = double.parse(d['lastPrice']);
        double onsChange = double.parse(d['priceChangePercent']);
        double onsTry = goldOnsUsd * usdTry;
        for (var a in market) {
          if (a.id == 'ons') {
            a.applyNewPrices(onsTry, onsTry, onsChange, nUsd: goldOnsUsd);
          }
        }
      }

      if (results[3].statusCode == 200) {
        final d = json.decode(results[3].body);
        double btcUsd = double.parse(d['lastPrice']);
        double btcChange = double.parse(d['priceChangePercent']);
        double btcTry = btcUsd * usdTry;
        for (var a in market) {
          if (a.id == 'btc') {
            a.applyNewPrices(btcTry, btcTry, btcChange, nUsd: btcUsd);
          }
        }
      }

      if (results[4].statusCode == 200) {
        final d = json.decode(results[4].body);
        double ethUsd = double.parse(d['lastPrice']);
        double ethChange = double.parse(d['priceChangePercent']);
        double ethTry = ethUsd * usdTry;
        for (var a in market) {
          if (a.id == 'eth') {
            a.applyNewPrices(ethTry, ethTry, ethChange, nUsd: ethUsd);
          }
        }
      }

      if (results[5].statusCode == 200) {
        final d = json.decode(results[5].body);
        double gbpUsd = double.parse(d['lastPrice']);
        double gbpChange = double.parse(d['priceChangePercent']);
        double gbpTry = gbpUsd * usdTry;
        for (var a in market) {
          if (a.id == 'gbp') {
            a.applyNewPrices(
                gbpTry * a.sellMarkup, gbpTry * a.buyMarkup, gbpChange);
          }
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  // ── SHEETS: Altın & Gümüş fiyatları (yavaş, arka planda) ──
  Future<void> _fetchSheetsData() async {
    try {
      final response = await http.get(Uri.parse(
          'https://docs.google.com/spreadsheets/d/1hXX1HmhjTGihxapua3D9iV3gq0kNRufy2ZQDD7HykeU/export?format=csv'))
          .timeout(const Duration(seconds: 10),
              onTimeout: () => http.Response('', 408));
      if (response.statusCode != 200) return;

      Map<String, Map<String, double>> sheetData = {};
      List<String> lines = response.body.split('\n');

      // B21 hücresinden sürüm bilgisini oku (satır 21, sütun B=index 1)
      if (lines.length >= 21) {
        List<String> row21 = _parseCsvLine(lines[20]);
        if (row21.length >= 2) {
          String v = row21[1].trim();
          if (v.isNotEmpty) sheetVersion = v;
        }
      }

      for (int i = 1; i < lines.length; i++) {
        String line = lines[i].trim();
        if (line.isEmpty) continue;
        List<String> cols = _parseCsvLine(line);
        if (cols.length < 4) continue;
        String kod = cols[0].trim().toLowerCase();
        double sell = _parseTurkishNumber(cols[1]);
        double buy = _parseTurkishNumber(cols[2]);
        double change = _parseTurkishNumber(cols[3]);
        if (kod.isNotEmpty && sell > 0) {
          sheetData[kod] = {'sell': sell, 'buy': buy, 'change': change};
        }
      }

      if (sheetData.isEmpty) return;

      const sheetsIds = [
        'has', 'gram', 'gram22', 'ceyrek', 'yarim', 'tam',
        'ata', 'resat', 'hamit', 'gremse', 'bilezik14', 'silver'
      ];
      for (var asset in market) {
        if (!sheetsIds.contains(asset.id)) continue;
        var data = sheetData[asset.id];
        if (data == null) continue;
        double sell = data['sell']!;
        double buy = data['buy']!;
        double change = data['change']!;
        if (sell <= 0) continue;
        if (buy <= 0) buy = sell * 0.98;
        asset.applyNewPrices(sell, buy, change);
      }

      _syncCustomAssets();
      saveMarketCache();
      onUpdate();
    } catch (e) {
      // Sheets başarısız olursa sessizce devam et
    }
  }

  // Tırnak içindeki virgülleri doğru parse eden CSV satır ayrıştırıcı
  List<String> _parseCsvLine(String line) {
    List<String> result = [];
    bool inQuotes = false;
    StringBuffer current = StringBuffer();
    for (int i = 0; i < line.length; i++) {
      String ch = line[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (ch == ',' && !inQuotes) {
        result.add(current.toString().trim());
        current.clear();
      } else {
        current.write(ch);
      }
    }
    result.add(current.toString().trim());
    return result;
  }

  // Türkçe sayı formatını double'a çevirir: "6.805,69" → 6805.69, "2,74%" → 2.74
  double _parseTurkishNumber(String raw) {
    try {
      String s = raw.trim().replaceAll('%', '').replaceAll('"', '');
      if (s.contains('.') && s.contains(',')) {
        // 6.805,69 → binlik nokta, ondalık virgül
        s = s.replaceAll('.', '').replaceAll(',', '.');
      } else if (s.contains(',')) {
        s = s.replaceAll(',', '.');
      }
      return double.tryParse(s) ?? 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  // ------------------------------------------------------------------
  // GOOGLE SHEETS'TEN GEÇMİŞ VERİLERİ ÇEK
  // ------------------------------------------------------------------
  Future<void> _fetchHistoricalFromSheets() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Günde 1 kez çek (cache kontrolü)
      String todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      String? lastFetch = prefs.getString('sheets_history_last_fetch');
      if (lastFetch == todayKey && assetHistory.isNotEmpty) return;

      final uri = Uri.parse(_sheetsHistoryUrl);
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return;

      String csvBody = response.body.trim();
      List<String> lines = csvBody.split('\n');
      if (lines.length < 2) return;

      // Header: Tarih,has,usd,eur,btc,eth,ons,silver
      List<String> headers = _parseCsvLine(lines[0])
          .map((h) => h.trim().toLowerCase())
          .toList();

      int iDate = headers.indexOf('tarih');
      int iHas = headers.indexOf('has');
      int iUsd = headers.indexOf('usd');
      int iEur = headers.indexOf('eur');
      int iBtc = headers.indexOf('btc');
      int iEth = headers.indexOf('eth');
      int iOns = headers.indexOf('ons');
      int iSilver = headers.indexOf('silver');
      int iGram = headers.indexOf('gram');
      int iGram22 = headers.indexOf('gram22');
      int iCeyrek = headers.indexOf('ceyrek');
      int iYarim = headers.indexOf('yarim');
      int iTam = headers.indexOf('tam');
      int iAta = headers.indexOf('ata');
      int iResat = headers.indexOf('resat');
      int iHamit = headers.indexOf('hamit');
      int iGremse = headers.indexOf('gremse');
      int iBilezik14 = headers.indexOf('bilezik14');
      int iGbp = headers.indexOf('gbp');

      if (iDate < 0 || iHas < 0) return;

      for (int i = 1; i < lines.length; i++) {
        String line = lines[i].trim();
        if (line.isEmpty) continue;

        List<String> cols = _parseCsvLine(line);
        if (cols.length <= iDate) continue;

        String dateKey = cols[iDate].trim();
        // Tarih formatını doğrula (yyyy-MM-dd)
        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateKey)) continue;

        double hasPrice = _getCol(cols, iHas);
        if (hasPrice <= 0) continue;

        double usdTry = _getCol(cols, iUsd);
        double eurTry = _getCol(cols, iEur);
        double btcUsd = _getCol(cols, iBtc);
        double ethUsd = _getCol(cols, iEth);
        double onsUsd = _getCol(cols, iOns);
        double silverTl = _getCol(cols, iSilver);
        double gbpTry = _getCol(cols, iGbp);

        // Sheets'te gerçek değerler varsa onları oku
        double gramReal = _getCol(cols, iGram);
        double gram22Real = _getCol(cols, iGram22);
        double ceyrekReal = _getCol(cols, iCeyrek);
        double yarimReal = _getCol(cols, iYarim);
        double tamReal = _getCol(cols, iTam);
        double ataReal = _getCol(cols, iAta);
        double resatReal = _getCol(cols, iResat);
        double hamitReal = _getCol(cols, iHamit);
        double gremseReal = _getCol(cols, iGremse);
        double bilezik14Real = _getCol(cols, iBilezik14);

        // HAS'tan diğer altın tiplerini türet (fallback)
        double rawBase = hasPrice / 1.031;
        Map<String, dynamic> dPrices = {};

        // Sheets'te gerçek değer varsa onu kullan, yoksa formülle hesapla
        dPrices["has"] = hasPrice;
        dPrices["gram"] = gramReal > 0
            ? gramReal
            : (rawBase * 1.0821) + (rawBase * 0.01);
        dPrices["gram22"] = gram22Real > 0
            ? gram22Real
            : (rawBase * 0.916 * 1.1134) + (rawBase * 0.916 * 0.01);
        dPrices["ceyrek"] = ceyrekReal > 0
            ? ceyrekReal
            : (rawBase * 1.605 * 1.1040) + (rawBase * 1.605 * 0.01);
        dPrices["yarim"] = yarimReal > 0
            ? yarimReal
            : (rawBase * 3.210 * 1.1006) + (rawBase * 3.210 * 0.01);
        dPrices["tam"] = tamReal > 0
            ? tamReal
            : (rawBase * 6.420 * 1.0964) + (rawBase * 6.420 * 0.01);
        dPrices["ata"] = ataReal > 0
            ? ataReal
            : (rawBase * 6.610 * 1.0934) + (rawBase * 6.610 * 0.01);
        dPrices["resat"] = resatReal > 0
            ? resatReal
            : (rawBase * 6.610 * 1.0934) + (rawBase * 6.610 * 0.01);
        dPrices["hamit"] = hamitReal > 0
            ? hamitReal
            : (rawBase * 6.610 * 1.0934) + (rawBase * 6.610 * 0.01);
        dPrices["gremse"] = gremseReal > 0
            ? gremseReal
            : (rawBase * 16.050 * 1.0939) + (rawBase * 16.050 * 0.01);
        dPrices["bilezik14"] = bilezik14Real > 0
            ? bilezik14Real
            : (rawBase * 0.585 * 1.3242) + (rawBase * 0.585 * 0.01);

        if (silverTl > 0) dPrices["silver"] = silverTl;
        if (usdTry > 0) dPrices["usd"] = usdTry;
        if (eurTry > 0) dPrices["eur"] = eurTry;
        if (gbpTry > 0) dPrices["gbp"] = gbpTry;
        // BTC, ETH, ONS her zaman USD bazında
        if (onsUsd > 0) dPrices["ons"] = onsUsd;
        if (btcUsd > 0) dPrices["btc"] = btcUsd;
        if (ethUsd > 0) dPrices["eth"] = ethUsd;

        assetHistory[dateKey] = dPrices;
      }

      // Yerel cache'e kaydet
      await prefs.setString('asset_history_v2', jsonEncode(assetHistory));
      await prefs.setString('sheets_history_last_fetch', todayKey);
    } catch (e) {
      // Sessizce devam et — cache'deki veriyle çalışır
    }
  }

  double _getCol(List<String> cols, int index) {
    if (index < 0 || index >= cols.length) return 0.0;
    String s = cols[index].trim();
    if (s.isEmpty) return 0.0;
    // Sheets Türkçe lokalde "6849,3600" formatında export eder
    return _parseTurkishNumber(s);
  }

  // ------------------------------------------------------------------
  // SHEETS'TEN SAATLİK VERİ ÇEK (Son 24 saat grafiği için)
  // ------------------------------------------------------------------
  Future<void> _fetchIntraDayFromSheets() async {
    try {
      final response = await http.get(Uri.parse(_sheetsSaatlikUrl))
          .timeout(const Duration(seconds: 10),
              onTimeout: () => http.Response('', 408));
      if (response.statusCode != 200) return;

      List<String> lines = response.body.split('\n');
      if (lines.length < 2) return;

      // Header: TARİH/SAAT, HAS, USD, EUR, BTC, ETH, ...
      List<String> headers = _parseCsvLine(lines[0])
          .map((h) => h.trim().toLowerCase().replaceAll('tarih/saat', 'time').replaceAll('tarih', 'time'))
          .toList();

      int iTime = headers.indexOf('time');
      if (iTime < 0) iTime = 0; // İlk sütun zaman

      List<Map<String, dynamic>> sheetsIntraDay = [];

      for (int i = 1; i < lines.length; i++) {
        String line = lines[i].trim();
        if (line.isEmpty) continue;
        List<String> cols = _parseCsvLine(line);
        if (cols.isEmpty) continue;

        String timeStr = cols[iTime].trim();
        if (timeStr.isEmpty) continue;

        Map<String, dynamic> prices = {};
        for (int j = 0; j < headers.length; j++) {
          if (j == iTime) continue;
          String kod = headers[j].trim().toLowerCase();
          if (kod.isEmpty) continue;
          double val = _getCol(cols, j);
          if (val > 0) prices[kod] = val;
        }

        if (prices.isNotEmpty) {
          sheetsIntraDay.add({"time": timeStr, "prices": prices});
        }
      }

      if (sheetsIntraDay.isNotEmpty) {
        // Sheets verisi ile yerel veriyi birleştir (Sheets öncelikli)
        Map<String, Map<String, dynamic>> merged = {};
        for (var entry in sheetsIntraDay) {
          merged[entry["time"]] = entry;
        }
        for (var entry in intraDayHistory) {
          String key = entry["time"];
          if (!merged.containsKey(key)) {
            merged[key] = entry;
          }
        }
        List<String> sortedKeys = merged.keys.toList()..sort();
        intraDayHistory = sortedKeys.map((k) => merged[k]!).toList();
        if (intraDayHistory.length > 288) {
          intraDayHistory = intraDayHistory.sublist(intraDayHistory.length - 288);
        }
      }
    } catch (e) {
      // Sessizce devam et
    }
  }

  // ------------------------------------------------------------------
  // GEÇMİŞ VERİ BOŞLUKLARINI DOLDUR (Binance Klines)
  // ------------------------------------------------------------------
  Future<void> fillHistoricalGaps() async {
    try {
      List<String> allDates = assetHistory.keys.toList()..sort();
      if (allDates.isEmpty) return;

      String lastDateStr = allDates.last;
      DateTime lastDate = DateTime.parse(lastDateStr);
      DateTime today = DateTime.now();
      int gapDays = today.difference(lastDate).inDays;

      if (gapDays < 2) return;

      final prefs = await SharedPreferences.getInstance();
      String? lastFillDate = prefs.getString('last_gap_fill_date');
      String todayKey = DateFormat('yyyy-MM-dd').format(today);
      if (lastFillDate == todayKey) return;

      int limit = gapDays > 365 ? 365 : gapDays + 1;
      int startTime = lastDate.millisecondsSinceEpoch;

      final results = await Future.wait([
        _fetchKlines('USDTTRY', startTime, limit),
        _fetchKlines('EURUSDT', startTime, limit),
        _fetchKlines('PAXGUSDT', startTime, limit),
        _fetchKlines('BTCUSDT', startTime, limit),
        _fetchKlines('ETHUSDT', startTime, limit),
        _fetchKlines('GBPUSDT', startTime, limit),
      ]);

      Map<String, double> usdRates = results[0];
      Map<String, double> eurUsdRates = results[1];
      Map<String, double> goldOnsUsd = results[2];
      Map<String, double> btcUsd = results[3];
      Map<String, double> ethUsd = results[4];
      Map<String, double> gbpUsdRates = results[5];

      if (usdRates.isEmpty && goldOnsUsd.isEmpty) return;

      Set<String> allNewDates = {
        ...usdRates.keys,
        ...goldOnsUsd.keys,
        ...btcUsd.keys
      };

      for (String dateKey in allNewDates) {
        if (assetHistory.containsKey(dateKey)) continue;

        double usdTry = usdRates[dateKey] ?? currentUsdRate;
        if (usdTry <= 0) continue;

        double eurUsd = eurUsdRates[dateKey] ?? 1.08;
        double paxgUsd = goldOnsUsd[dateKey] ?? 0;
        double btc = btcUsd[dateKey] ?? 0;
        double eth = ethUsd[dateKey] ?? 0;

        double rawBase = (paxgUsd / 31.1035) * usdTry;
        if (rawBase <= 0) continue;

        Map<String, dynamic> dPrices = {};
        dPrices["has"] = (rawBase * 1.0767) + (rawBase * 0.01);
        dPrices["gram"] = (rawBase * 1.0821) + (rawBase * 0.01);
        dPrices["ceyrek"] =
            (rawBase * 1.605 * 1.1040) + (rawBase * 1.605 * 0.01);
        dPrices["yarim"] =
            (rawBase * 3.210 * 1.1006) + (rawBase * 3.210 * 0.01);
        dPrices["tam"] =
            (rawBase * 6.420 * 1.0964) + (rawBase * 6.420 * 0.01);
        dPrices["ata"] =
            (rawBase * 6.610 * 1.0934) + (rawBase * 6.610 * 0.01);
        dPrices["gremse"] =
            (rawBase * 16.050 * 1.0939) + (rawBase * 16.050 * 0.01);
        dPrices["resat"] =
            (rawBase * 6.610 * 1.0934) + (rawBase * 6.610 * 0.01);
        dPrices["hamit"] =
            (rawBase * 6.610 * 1.0934) + (rawBase * 6.610 * 0.01);
        dPrices["gram22"] =
            (rawBase * 0.916 * 1.1134) + (rawBase * 0.916 * 0.01);
        dPrices["yarim_gram22"] =
            (rawBase * 0.458 * 1.1134) + (rawBase * 0.458 * 0.01);
        dPrices["bilezik14"] =
            (rawBase * 0.585 * 1.3242) + (rawBase * 0.585 * 0.01);

        double silverBaseTL = rawBase / 66.0;
        double eurTry = eurUsd * usdTry;
        double gbpUsd = gbpUsdRates[dateKey] ?? 1.27;
        double gbpTry = gbpUsd * usdTry;

        dPrices["silver"] = silverBaseTL * 1.0957;
        dPrices["usd"] = usdTry;
        dPrices["eur"] = eurTry;
        dPrices["gbp"] = gbpTry;
        dPrices["ons"] = paxgUsd;    // USD bazında
        dPrices["btc"] = btc;         // USD bazında
        dPrices["eth"] = eth;         // USD bazında

        assetHistory[dateKey] = dPrices;
      }

      await prefs.setString('asset_history_v2', jsonEncode(assetHistory));
      await prefs.setString('last_gap_fill_date', todayKey);
    } catch (e) {
      // Sessizce devam et
    }
  }

  Future<Map<String, double>> _fetchKlines(
      String symbol, int startTime, int limit) async {
    Map<String, double> result = {};
    try {
      final uri = Uri.parse(
          'https://api.binance.com/api/v3/klines?symbol=$symbol&interval=1d&startTime=$startTime&limit=$limit');
      final response = await http.get(uri);
      if (response.statusCode != 200) return result;

      List<dynamic> klines = json.decode(response.body);
      for (var kline in klines) {
        int openTimeMs = kline[0];
        DateTime date = DateTime.fromMillisecondsSinceEpoch(openTimeMs);
        String dateKey = DateFormat('yyyy-MM-dd').format(date);
        double closePrice = double.tryParse(kline[4].toString()) ?? 0.0;
        if (closePrice > 0) {
          result[dateKey] = closePrice;
        }
      }
    } catch (e) {
      // Sessizce devam et
    }
    return result;
  }

  void _initializeMarketSkeleton() {
    market = [
      AssetType(
          "gram", ["GRA", "GRAMALTIN"], "G", "24 Ayar Gram", 0, 0, "gold",
          sellMarkup: 1.0821, buyMarkup: 1.0333),
      AssetType("gram22", ["YIA", "22AYARBILEZIK"], "22K", "22 Ayar Gram", 0, 0,
          "gold",
          manualInput: false, sellMarkup: 1.1134, buyMarkup: 1.0314),
      AssetType("ceyrek", ["CEYREKALTIN"], "Ç", "Çeyrek Altın", 0, 0, "gold",
          sellMarkup: 1.1040, buyMarkup: 1.0547),
      AssetType("yarim", ["YARIMALTIN"], "Y", "Yarım Altın", 0, 0, "gold",
          sellMarkup: 1.1006, buyMarkup: 1.0547),
      AssetType("tam", ["TAMALTIN"], "T", "Tam Altın", 0, 0, "gold",
          sellMarkup: 1.0964, buyMarkup: 1.0514),
      AssetType("ata", ["ATAALTIN"], "A", "Ata Altın", 0, 0, "gold",
          sellMarkup: 1.0934, buyMarkup: 1.0495),
      AssetType("tl", [], "₺", "Türk Lirası", 1, 1, "currency",
          manualInput: true,
          sellMarkup: 1.000,
          buyMarkup: 1.000),
      AssetType("yarim_gram22", [], "0.5", "0.5 Gram (22K)", 0, 0, "gold",
          manualInput: false, sellMarkup: 1.1134, buyMarkup: 1.0314),
      AssetType("ons", ["ONS"], "ONS", "Altın / ONS", 0, 0, "ons",
          sellMarkup: 1.000, buyMarkup: 1.000, isDollarBase: true),
      AssetType("usd", ["USD"], "\$", "ABD Doları", 0, 0, "currency",
          manualInput: true, sellMarkup: 1.004, buyMarkup: 0.996),
      AssetType("eur", ["EUR"], "€", "Euro", 0, 0, "currency",
          manualInput: true, sellMarkup: 1.004, buyMarkup: 0.996),
      AssetType("silver", ["GUMUS"], "Ag", "Gümüş (TL)", 0, 0, "silver",
          manualInput: true, sellMarkup: 1.0957, buyMarkup: 1.0115),
      AssetType("btc", ["BTC"], "₿", "Bitcoin", 0, 0, "crypto",
          manualInput: false,
          sellMarkup: 1.000,
          buyMarkup: 1.000,
          isDollarBase: true),
      AssetType(
          "has", ["HAS", "GRAMHASALTIN"], "Has", "Has Altın", 0, 0, "gold",
          sellMarkup: 1.0767, buyMarkup: 1.0385),
      AssetType("gremse", ["GREMSEALTIN"], "Grm", "Gremse", 0, 0, "gold",
          sellMarkup: 1.0939, buyMarkup: 1.0482),
      AssetType("resat", ["RESATALTIN"], "R", "Reşat Altın", 0, 0, "gold",
          sellMarkup: 1.0934, buyMarkup: 1.0495),
      AssetType("hamit", ["HAMITALTIN"], "H", "Hamit Altın", 0, 0, "gold",
          sellMarkup: 1.0934, buyMarkup: 1.0495),
      AssetType(
          "bilezik14", ["14AYARALTIN"], "14K", "14 Ayar Gram", 0, 0, "gold",
          manualInput: false, sellMarkup: 1.3242, buyMarkup: 0.9711),
      AssetType("gbp", ["GBP"], "£", "Sterlin", 0, 0, "currency",
          manualInput: true, sellMarkup: 1.004, buyMarkup: 0.996),
      AssetType("eth", ["ETH"], "Ξ", "Ethereum", 0, 0, "crypto",
          manualInput: false,
          sellMarkup: 1.000,
          buyMarkup: 1.000,
          isDollarBase: true),
    ];
  }

  Future<void> loadMarketCache() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('market_cache')) {
      try {
        Map<String, dynamic> cacheData =
            jsonDecode(prefs.getString('market_cache')!);
        for (var a in market) {
          if (cacheData.containsKey(a.id)) {
            if (a.id == "usd") currentUsdRate = cacheData[a.id]['bs'] ?? 44.0;
            a.applyNewPrices(cacheData[a.id]['bs'] ?? 0.0,
                cacheData[a.id]['bb'] ?? 0.0, cacheData[a.id]['c'] ?? 0.0,
                nUsd: cacheData[a.id]['usd'] ?? 0.0);
          }
        }
      } catch (e) {}
    }
  }

  Future<void> saveMarketCache() async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> cacheData = {
      for (var a in market)
        a.id: {
          'bs': a.baseSellPrice,
          'bb': a.baseBuyPrice,
          'c': a.changeRate,
          'usd': a.usdPrice
        }
    };
    await prefs.setString('market_cache', jsonEncode(cacheData));
  }

  Future<void> loadMarketOrder() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('market_order')) {
      List<String>? orderIds = prefs.getStringList('market_order');
      if (orderIds != null && orderIds.isNotEmpty) {
        market.sort((a, b) => (orderIds.indexOf(a.id) == -1
                ? 999
                : orderIds.indexOf(a.id))
            .compareTo(
                orderIds.indexOf(b.id) == -1 ? 999 : orderIds.indexOf(b.id)));
      }
    }
  }

  Future<void> saveMarketOrder() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> orderIds = market.map((e) => e.id).toList();
    await prefs.setStringList('market_order', orderIds);
  }

  Future<void> loadAllUserData() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      if (prefs.containsKey('debts')) {
        debts = (jsonDecode(prefs.getString('debts')!) as List)
            .map((e) => PortfolioItem.fromJson(e))
            .toList();
      }
      if (prefs.containsKey('credits')) {
        credits = (jsonDecode(prefs.getString('credits')!) as List)
            .map((e) => PortfolioItem.fromJson(e))
            .toList();
      }
      if (prefs.containsKey('wallet')) {
        wallet = PortfolioItem.fromJson(jsonDecode(prefs.getString('wallet')!));
      }
      if (prefs.containsKey('history')) {
        historyData = List<Map<String, dynamic>>.from(
            jsonDecode(prefs.getString('history')!));
      }
      if (prefs.containsKey('intraday_history')) {
        intraDayHistory =
            (jsonDecode(prefs.getString('intraday_history')!) as List)
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
      }

      // Geçmiş veriler artık Google Sheets'ten çekilir (_fetchHistoricalFromSheets)
      // Önce varsa yerel cache'i yükle
      if (prefs.containsKey('asset_history_v2')) {
        Map<String, dynamic> localHistory =
            jsonDecode(prefs.getString('asset_history_v2')!);
        localHistory.forEach((key, value) {
          assetHistory[key] = Map<String, dynamic>.from(value);
        });
      }
    } catch (e) {}
  }

  Future<void> saveAllUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'debts', jsonEncode(debts.map((e) => e.toJson()).toList()));
    await prefs.setString(
        'credits', jsonEncode(credits.map((e) => e.toJson()).toList()));
    await prefs.setString('wallet', jsonEncode(wallet.toJson()));
    updateDailyHistory();
  }

  void updateDailyHistory() async {
    final prefs = await SharedPreferences.getInstance();
    double wVal = wallet.getTotalValue(market);
    double cVal = credits.fold(0, (sum, i) => sum + i.getTotalValue(market));
    double dVal = debts.fold(0, (sum, i) => sum + i.getTotalValue(market));

    String todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    int index =
        historyData.indexWhere((element) => element['date'] == todayKey);

    Map<String, double> prevWalletAssets = {};
    for (int i = historyData.length - 1; i >= 0; i--) {
      if (historyData[i]['date'] != todayKey &&
          historyData[i]['wallet_assets'] != null) {
        Map<String, dynamic> raw = historyData[i]['wallet_assets'] is Map
            ? historyData[i]['wallet_assets']
            : {};
        raw.forEach((k, v) => prevWalletAssets[k] = (v as num).toDouble());
        break;
      }
    }

    List<String> walletNotes = [];
    wallet.assets.forEach((assetId, qty) {
      try {
        var asset = market.firstWhere((e) => e.id == assetId);
        double prev = prevWalletAssets[assetId] ?? 0;
        double diff = qty - prev;
        if (diff > 0.001) {
          walletNotes.add("+${formatNumber(diff)} ${asset.name}");
        } else if (diff < -0.001) {
          walletNotes.add("${formatNumber(diff)} ${asset.name}");
        }
      } catch (e) {}
    });
    prevWalletAssets.forEach((assetId, prevQty) {
      if (!wallet.assets.containsKey(assetId) && prevQty > 0.001) {
        try {
          var asset = market.firstWhere((e) => e.id == assetId);
          walletNotes.add("-${formatNumber(prevQty)} ${asset.name}");
        } catch (e) {}
      }
    });

    List<String> creditNotes = [];
    for (var item in credits) {
      List<String> parts = [];
      item.assets.forEach((assetId, qty) {
        try {
          var asset = market.firstWhere((e) => e.id == assetId);
          parts.add("${formatNumber(qty)} ${asset.name}");
        } catch (e) {}
      });
      if (parts.isNotEmpty) {
        creditNotes.add("${item.personName}: ${parts.join(', ')}");
      }
    }

    List<String> debtNotes = [];
    for (var item in debts) {
      List<String> parts = [];
      item.assets.forEach((assetId, qty) {
        try {
          var asset = market.firstWhere((e) => e.id == assetId);
          parts.add("${formatNumber(qty)} ${asset.name}");
        } catch (e) {}
      });
      if (parts.isNotEmpty) {
        debtNotes.add("${item.personName}: ${parts.join(', ')}");
      }
    }

    Map<String, dynamic> todayData = {
      'date': todayKey,
      'net': (wVal + cVal - dVal),
      'wallet': wVal,
      'credit': cVal,
      'debt': dVal,
      'note': walletNotes.join(', '),
      'wallet_note': walletNotes.join('\n'),
      'credit_note': creditNotes.join('\n'),
      'debt_note': debtNotes.join('\n'),
      'wallet_assets': Map<String, double>.from(wallet.assets),
    };
    if (index != -1) {
      historyData[index] = todayData;
    } else {
      historyData.add(todayData);
    }
    if (historyData.length > 30)
      historyData = historyData.sublist(historyData.length - 30);
    await prefs.setString('history', jsonEncode(historyData));

    Map<String, dynamic> currentPrices = {};
    for (var a in market) {
      double p = a.isDollarBase ? a.usdPrice : a.sellPrice;
      if (p > 0) currentPrices[a.id] = p;
    }
    // Hiç geçerli fiyat yoksa kaydetme (henüz veri gelmemiş)
    if (currentPrices.isNotEmpty) {
      String timeKey = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
      if (intraDayHistory.isEmpty || intraDayHistory.last["time"] != timeKey) {
        intraDayHistory.add({"time": timeKey, "prices": currentPrices});
        if (intraDayHistory.length > 288) intraDayHistory.removeAt(0);
        await prefs.setString('intraday_history', jsonEncode(intraDayHistory));
      }
    }

    Map<String, dynamic> todayPrices = {};
    for (var a in market) {
      double p = a.isDollarBase ? a.usdPrice : a.sellPrice;
      if (p > 0) todayPrices[a.id] = p;
    }
    if (todayPrices.isNotEmpty) assetHistory[todayKey] = todayPrices;
    await prefs.setString('asset_history_v2', jsonEncode(assetHistory));
  }
}
