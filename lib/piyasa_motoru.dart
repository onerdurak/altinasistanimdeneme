import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'modeller.dart';
import 'gecmis_veriler.dart';

class PiyasaMotoru {
  final Function onUpdate;

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

  Timer? _refreshTimer;
  Timer? _simulationTimer;
  final Random _random = Random();
  DateTime? _lastFetchTime;

  PiyasaMotoru({required this.onUpdate});

  void _recalcLiveValues() {
    _syncCustomAssets();
    liveWalletVal = wallet.getTotalValue(market);
    liveCreditVal =
        credits.fold(0, (sum, i) => sum + i.getTotalValue(market));
    liveDebtVal = debts.fold(0, (sum, i) => sum + i.getTotalValue(market));
    liveNetWorth = liveWalletVal + liveCreditVal - liveDebtVal;
    onUpdate();
  }

  void baslat() {
    _initializeMarketSkeleton();
    loadMarketOrder();
    loadAllUserData().then((_) {
      // 1. Önce cache'den hızlı aç (eski verilerle anında göster)
      loadMarketCache();
      _recalcLiveValues();

      // 2. Sonra 1 kez veri çek, matrix başlat
      fetchLiveData().then((_) {
        _recalcLiveValues();
        _lastFetchTime = DateTime.now();
        fillHistoricalGaps();
      });
    });

    // 5 dakikada bir veri çek (arada sadece matrix çalışır)
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      fetchLiveData(silent: true).then((_) {
        _lastFetchTime = DateTime.now();
      });
    });
    _startTickerSimulation();
  }

  void kapat() {
    _refreshTimer?.cancel();
    _simulationTimer?.cancel();
  }

  void _syncCustomAssets() {
    try {
      var gram22 = market.firstWhere((e) => e.id == "gram22");
      var yarimGram = market.firstWhere((e) => e.id == "yarim_gram22");
      yarimGram.baseSellPrice = gram22.baseSellPrice / 2;
      yarimGram.baseBuyPrice = gram22.baseBuyPrice / 2;
      yarimGram.sellPrice = gram22.sellPrice / 2;
      yarimGram.buyPrice = gram22.buyPrice / 2;
    } catch (e) {}
  }

  void _startTickerSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!isLiveConnection) return;

      // Sadece birkaç varlığı hafifçe oynasın (3-4 tane yeterli)
      int changeCount = min(4, market.length);
      List<int> allIndices = List.generate(market.length, (i) => i)
        ..shuffle(_random);

      for (int i = 0; i < changeCount; i++) {
        var asset = market[allIndices[i]];
        if (asset.baseSellPrice > 0) {
          double maxDeviation = min(5.0, asset.baseSellPrice * 0.003);
          double maxStep = min(0.8, asset.baseSellPrice * 0.0005);
          double step = (_random.nextDouble() - 0.5) * 2.0 * maxStep;
          double newSell = asset.sellPrice + step;

          newSell = newSell.clamp(
              asset.baseSellPrice - maxDeviation,
              asset.baseSellPrice + maxDeviation);

          double proportionalChange =
              (newSell - asset.baseSellPrice) / asset.baseSellPrice;
          asset.sellPrice = newSell;
          asset.buyPrice = asset.baseBuyPrice * (1 + proportionalChange);
          if (asset.isDollarBase && asset.baseUsdPrice > 0) {
            asset.usdPrice = asset.baseUsdPrice * (1 + proportionalChange);
          }
        }
      }

      _syncCustomAssets();

      // Portfolio değerlerini her tick yerine sadece 4 tick'te 1 hesapla (12sn)
      if (timer.tick % 4 == 0) {
        liveWalletVal = wallet.getTotalValue(market);
        liveCreditVal =
            credits.fold(0, (sum, i) => sum + i.getTotalValue(market));
        liveDebtVal = debts.fold(0, (sum, i) => sum + i.getTotalValue(market));
        liveNetWorth = liveWalletVal + liveCreditVal - liveDebtVal;
      }

      onUpdate();
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

  // Sheets verisini 30 saniye sonra arka planda çek (Binance'i beklemesin)
  void _scheduleSheetsUpdate() {
    Future.delayed(const Duration(seconds: 4), () async {
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
      ]);

      Map<String, double> usdRates = results[0];
      Map<String, double> eurUsdRates = results[1];
      Map<String, double> goldOnsUsd = results[2];
      Map<String, double> btcUsd = results[3];
      Map<String, double> ethUsd = results[4];

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

        dPrices["silver"] = silverBaseTL * 1.0957;
        dPrices["usd"] = usdTry * 1.004;
        dPrices["eur"] = eurTry * 1.004;
        dPrices["ons"] = paxgUsd * usdTry;
        dPrices["btc"] = btc * usdTry;
        dPrices["eth"] = eth * usdTry;

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

      realGoldHistory.forEach((dateKey, hasPrice) {
        Map<String, dynamic> dPrices = {};
        DateTime targetDate = DateTime.parse(dateKey);
        double rawBase = hasPrice / 1.031;

        dPrices["has"] = (rawBase * 1.0767) + (rawBase * 0.01);
        dPrices["gram"] = (rawBase * 1.0821) + (rawBase * 0.01);
        dPrices["ceyrek"] =
            (rawBase * 1.605 * 1.1040) + (rawBase * 1.605 * 0.01);
        dPrices["yarim"] =
            (rawBase * 3.210 * 1.1006) + (rawBase * 3.210 * 0.01);
        dPrices["tam"] = (rawBase * 6.420 * 1.0964) + (rawBase * 6.420 * 0.01);
        dPrices["ata"] = (rawBase * 6.610 * 1.0934) + (rawBase * 6.610 * 0.01);
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

        double usdTry = 0.0;
        if (realUsdHistory.containsKey(dateKey)) {
          usdTry = realUsdHistory[dateKey]!;
        } else {
          List<String> sortedUsdDates = realUsdHistory.keys.toList()..sort();
          String? closestDate;
          for (var d in sortedUsdDates) {
            if (DateTime.parse(d).isAfter(targetDate)) {
              closestDate = d;
              break;
            }
          }
          if (closestDate != null &&
              DateTime.parse(closestDate).difference(targetDate).inDays.abs() <
                  7) {
            usdTry = realUsdHistory[closestDate]!;
          } else {
            int daysSince2015 =
                targetDate.difference(DateTime(2015, 1, 1)).inDays;
            if (daysSince2015 < 0) daysSince2015 = 0;
            double estimatedOns = 1200.0 + (daysSince2015 * (1600.0 / 3650.0));
            usdTry = rawBase / (estimatedOns / 31.1035);
          }
        }

        double btcUsd = 0.0;
        if (realBtcHistory.containsKey(dateKey)) {
          btcUsd = realBtcHistory[dateKey]!;
        } else {
          List<String> sortedBtcDates = realBtcHistory.keys.toList()..sort();
          String? before;
          String? after;
          for (var d in sortedBtcDates) {
            if (DateTime.parse(d).isBefore(targetDate) ||
                DateTime.parse(d).isAtSameMomentAs(targetDate)) {
              before = d;
            } else {
              after = d;
              break;
            }
          }
          if (before != null &&
              targetDate.difference(DateTime.parse(before)).inDays <= 30) {
            btcUsd = realBtcHistory[before]!;
          } else if (after != null &&
              DateTime.parse(after).difference(targetDate).inDays <= 30) {
            btcUsd = realBtcHistory[after]!;
          } else {
            int daysSince2015 =
                targetDate.difference(DateTime(2015, 1, 1)).inDays;
            if (daysSince2015 < 0) daysSince2015 = 0;
            btcUsd = 300.0 * pow(1.00147, daysSince2015);
            if (btcUsd > 120000) btcUsd = 120000.0;
          }
        }

        double eurTry = usdTry * 1.08;
        double ethUsd = btcUsd * 0.05;
        double goldOns = (rawBase / usdTry) * 31.1035;

        double silverPrice = 0.0;
        if (realSilverHistory.containsKey(dateKey)) {
          silverPrice = realSilverHistory[dateKey]!;
        } else {
          List<String> sortedSilverDates = realSilverHistory.keys.toList()
            ..sort();
          String? before;
          String? after;
          for (var d in sortedSilverDates) {
            if (DateTime.parse(d).isBefore(targetDate) ||
                DateTime.parse(d).isAtSameMomentAs(targetDate)) {
              before = d;
            } else {
              after = d;
              break;
            }
          }
          if (before != null &&
              targetDate.difference(DateTime.parse(before)).inDays <= 30) {
            silverPrice = realSilverHistory[before]!;
          } else if (after != null &&
              DateTime.parse(after).difference(targetDate).inDays <= 30) {
            silverPrice = realSilverHistory[after]!;
          } else {
            double silverBaseTL = rawBase / 66.0;
            silverPrice = silverBaseTL * 1.0957;
          }
        }

        dPrices["silver"] = silverPrice;
        dPrices["usd"] = usdTry * 1.004;
        dPrices["eur"] = eurTry * 1.004;
        dPrices["ons"] = goldOns;
        dPrices["btc"] = btcUsd;
        dPrices["eth"] = ethUsd;

        assetHistory[dateKey] = dPrices;
      });

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
      currentPrices[a.id] = a.isDollarBase ? a.usdPrice : a.sellPrice;
    }
    String timeKey = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    if (intraDayHistory.isEmpty || intraDayHistory.last["time"] != timeKey) {
      intraDayHistory.add({"time": timeKey, "prices": currentPrices});
      if (intraDayHistory.length > 288) intraDayHistory.removeAt(0);
      await prefs.setString('intraday_history', jsonEncode(intraDayHistory));
    }

    Map<String, dynamic> todayPrices = {};
    for (var a in market) {
      todayPrices[a.id] = a.isDollarBase ? a.usdPrice : a.sellPrice;
    }
    assetHistory[todayKey] = todayPrices;
    await prefs.setString('asset_history_v2', jsonEncode(assetHistory));
  }
}
