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

  PiyasaMotoru({required this.onUpdate});

  void baslat() {
    _initializeMarketSkeleton();
    loadMarketOrder();
    loadAllUserData().then((_) {
      loadMarketCache();
      fetchLiveData().then((_) {
        fillHistoricalGaps();
      });
    });

    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      fetchLiveData(silent: true);
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
    _simulationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!isLiveConnection) return;

      List<int> allIndices = List.generate(market.length, (i) => i)
        ..shuffle(_random);
      int changeCount = (market.length * 0.9).toInt();
      List<int> selectedIndices = allIndices.take(changeCount).toList();

      for (int i in selectedIndices) {
        var asset = market[i];
        if (asset.baseSellPrice > 0) {
          double maxDeviation = min(10.0, asset.baseSellPrice * 0.005);
          double maxStep = min(1.5, asset.baseSellPrice * 0.001);
          double step = (_random.nextDouble() - 0.5) * 2.0 * maxStep;
          double newSell = asset.sellPrice + step;

          if (newSell > asset.baseSellPrice + maxDeviation) {
            newSell = asset.baseSellPrice + maxDeviation;
          } else if (newSell < asset.baseSellPrice - maxDeviation) {
            newSell = asset.baseSellPrice - maxDeviation;
          }

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
      liveWalletVal = wallet.getTotalValue(market);
      liveCreditVal =
          credits.fold(0, (sum, i) => sum + i.getTotalValue(market));
      liveDebtVal = debts.fold(0, (sum, i) => sum + i.getTotalValue(market));
      liveNetWorth = liveWalletVal + liveCreditVal - liveDebtVal;

      onUpdate();
    });
  }

  // --- MOTOR TETİKLEYİCİSİ (İZOLASYON VE SIRALAMA) ---
  Future<void> fetchLiveData({bool silent = false}) async {
    if (!silent) {
      isLoading = true;
      onUpdate();
    }

    try {
      // 1. BİRİNCİ MOTOR: BİNANCE (Ana Motor)
      bool isBinanceSuccess = await _fetchFromBinanceEngine();
      isPrimaryEngineActive = isBinanceSuccess;

      // 2. İKİNCİ MOTOR: TRUNCGIL (Sadece Binance Çökerse Çalışır - Yedek Motor)
      bool isTruncgilSuccess = false;
      if (!isBinanceSuccess) {
        isTruncgilSuccess = await _fetchFromTruncgilEngine();
      }

      // İnternet var mı yok mu kontrolü
      isLiveConnection = isBinanceSuccess || isTruncgilSuccess;

      // 3. ÜÇÜNCÜ MOTOR: TCMB (Döviz kurlarını TCMB'den doğrula/güncelle)
      if (isLiveConnection) {
        await _fetchFromTcmbEngine();
      }

      // Eğer sistem Binance'den değil de yedek motor Truncgil'den çalıştıysa,
      // Truncgil kriptoları eksik verebilir, bu yüzden sadece kripto için Binance'i tekrar yokla
      if (!isBinanceSuccess && isLiveConnection) {
        await _fetchCryptoFromBinance();
      }
    } catch (e) {
      isLiveConnection = false;
    } finally {
      if (!silent) {
        isLoading = false;
        onUpdate();
      }
    }
  }

  // ------------------------------------------------------------------
  // BİRİNCİ MOTOR: BINANCE (Tamamen Bağımsız)
  // ------------------------------------------------------------------
  Future<bool> _fetchFromBinanceEngine() async {
    try {
      final binanceUsdRes = await http.get(Uri.parse(
          'https://api.binance.com/api/v3/ticker/24hr?symbol=USDTTRY'));
      final binanceEurRes = await http.get(Uri.parse(
          'https://api.binance.com/api/v3/ticker/24hr?symbol=EURUSDT'));
      final binancePaxgRes = await http.get(Uri.parse(
          'https://api.binance.com/api/v3/ticker/24hr?symbol=PAXGUSDT'));
      final binanceBtcRes = await http.get(Uri.parse(
          'https://api.binance.com/api/v3/ticker/24hr?symbol=BTCUSDT'));
      final binanceEthRes = await http.get(Uri.parse(
          'https://api.binance.com/api/v3/ticker/24hr?symbol=ETHUSDT'));

      if (binanceUsdRes.statusCode != 200 || binancePaxgRes.statusCode != 200)
        return false;

      double usdTry =
          double.parse(json.decode(binanceUsdRes.body)['lastPrice']);
      double usdChange =
          double.parse(json.decode(binanceUsdRes.body)['priceChangePercent']);
      double eurUsd =
          double.parse(json.decode(binanceEurRes.body)['lastPrice']);
      double eurTry = eurUsd * usdTry;
      double eurChange =
          double.parse(json.decode(binanceEurRes.body)['priceChangePercent']);

      double goldOns =
          double.parse(json.decode(binancePaxgRes.body)['lastPrice']);
      double goldOnsChange =
          double.parse(json.decode(binancePaxgRes.body)['priceChangePercent']);

      double btcUsd =
          double.parse(json.decode(binanceBtcRes.body)['lastPrice']);
      double btcChange =
          double.parse(json.decode(binanceBtcRes.body)['priceChangePercent']);
      double ethUsd =
          double.parse(json.decode(binanceEthRes.body)['lastPrice']);
      double ethChange =
          double.parse(json.decode(binanceEthRes.body)['priceChangePercent']);

      currentUsdRate = usdTry;

      double goldTlChange =
          (((1 + (goldOnsChange / 100)) * (1 + (usdChange / 100))) - 1) * 100;
      double rawHasAltinTL = (goldOns / 31.1035) * usdTry;
      double silverBaseTL = rawHasAltinTL / 66.0;

      Map<String, double> basePrices = {
        "has": rawHasAltinTL,
        "gram": rawHasAltinTL,
        "ceyrek": rawHasAltinTL * 1.605,
        "yarim": rawHasAltinTL * 3.210,
        "tam": rawHasAltinTL * 6.420,
        "ata": rawHasAltinTL * 6.610,
        "gremse": rawHasAltinTL * 16.050,
        "resat": rawHasAltinTL * 6.610,
        "hamit": rawHasAltinTL * 6.610,
        "gram22": rawHasAltinTL * 0.916,
        "yarim_gram22": (rawHasAltinTL * 0.916) / 2,
        "bilezik14": rawHasAltinTL * 0.585,
        "silver": silverBaseTL,
        "usd": usdTry,
        "eur": eurTry,
        "gbp": usdTry * 1.26,
        "ons": goldOns * usdTry,
        "btc": btcUsd * usdTry,
        "eth": ethUsd * usdTry,
      };

      Map<String, double> usdPrices = {
        "ons": goldOns,
        "btc": btcUsd,
        "eth": ethUsd
      };
      Map<String, double> changeRates = {
        "usd": usdChange,
        "eur": eurChange,
        "gbp": usdChange,
        "ons": goldOnsChange,
        "btc": btcChange,
        "eth": ethChange,
      };

      for (var asset in market) {
        double baseP = basePrices[asset.id] ?? 0;
        double usdP = usdPrices[asset.id] ?? 0;
        double cRate = changeRates[asset.id] ?? 0;

        if (baseP > 0) {
          if (asset.category == 'gold' || asset.category == 'silver') {
            double haremSellPrice = baseP * asset.sellMarkup;
            double haremBuyPrice = baseP * asset.buyMarkup;

            double dynamicMargin = 0;
            if (asset.category == 'gold') dynamicMargin = baseP * 0.01;

            double finalSellPrice = haremSellPrice + dynamicMargin;
            double finalBuyPrice = haremBuyPrice;

            double assetChange =
                asset.category == 'gold' ? goldTlChange : goldTlChange * 0.5;

            double oldRawP = baseP / (1 + (assetChange / 100));
            double rawPremium = baseP * (asset.sellMarkup - 1.0);
            double oldSellPrice = oldRawP +
                rawPremium +
                (asset.category == 'gold' ? (oldRawP * 0.01) : 0);
            double customRate = oldSellPrice != 0
                ? ((finalSellPrice / oldSellPrice) - 1) * 100
                : assetChange;

            asset.applyNewPrices(finalSellPrice, finalBuyPrice, customRate,
                nUsd: usdP > 0 ? usdP : (baseP / usdTry));
          } else {
            asset.applyNewPrices(
                baseP * asset.sellMarkup, baseP * asset.buyMarkup, cRate,
                nUsd: usdP > 0 ? usdP : (baseP / usdTry));
          }
        }
      }

      _syncCustomAssets();
      updateDailyHistory();
      saveMarketCache();
      return true;
    } catch (e) {
      return false;
    }
  }

  // ------------------------------------------------------------------
  // İKİNCİ MOTOR: TRUNCGIL (Tamamen Bağımsız)
  // ------------------------------------------------------------------
  Future<bool> _fetchFromTruncgilEngine() async {
    try {
      final response = await http.get(
          Uri.parse('https://finans.truncgil.com/v4/today.json'),
          headers: {"User-Agent": "Mozilla/5.0"});
      if (response.statusCode != 200) return false;

      Map<String, dynamic> data = json.decode(response.body);
      double gramFiyat = 0, usdFiyat = 0;

      double hasAltinTL = _safeDouble(data['HAS ALTIN']['Selling']);
      if (hasAltinTL == 0)
        hasAltinTL = _safeDouble(data['GRAM ALTIN']['Selling']);
      if (hasAltinTL == 0) return false;

      // Truncgil'den gelen fiyat Harem kârlı olabilir, ham base fiyata çevir
      double rawHasAltinTL = hasAltinTL / 1.0767;

      double usdTry = _safeDouble(data['USD']['Selling']);
      if (usdTry == 0) usdTry = currentUsdRate;

      for (var asset in market) {
        dynamic apiItem;
        for (String key in asset.jsonKeys) {
          if (data.containsKey(key)) {
            apiItem = data[key];
            break;
          }
        }

        if (asset.category == 'gold' || asset.category == 'silver') {
          double weight = 1.0;
          if (asset.id == "ceyrek")
            weight = 1.605;
          else if (asset.id == "yarim")
            weight = 3.210;
          else if (asset.id == "tam")
            weight = 6.420;
          else if (asset.id == "ata" ||
              asset.id == "resat" ||
              asset.id == "hamit")
            weight = 6.610;
          else if (asset.id == "gremse")
            weight = 16.050;
          else if (asset.id == "gram22")
            weight = 0.916;
          else if (asset.id == "yarim_gram22")
            weight = 0.458;
          else if (asset.id == "bilezik14")
            weight = 0.585;
          else if (asset.id == "silver") weight = 1 / 66.0;

          double baseP = rawHasAltinTL * weight;
          double rawChangeRate = _safeDouble(data['HAS ALTIN']['Change']);

          double haremSellPrice = baseP * asset.sellMarkup;
          double haremBuyPrice = baseP * asset.buyMarkup;

          double dynamicMargin = 0;
          if (asset.category == 'gold') dynamicMargin = baseP * 0.01;

          double finalSellPrice = haremSellPrice + dynamicMargin;
          double finalBuyPrice = haremBuyPrice;

          double rawPremium = baseP * (asset.sellMarkup - 1.0);
          double oldRawP = baseP / (1 + (rawChangeRate / 100));
          double oldSellPrice = oldRawP +
              rawPremium +
              (asset.category == 'gold' ? (oldRawP * 0.01) : 0);
          double customRate = oldSellPrice != 0
              ? ((finalSellPrice / oldSellPrice) - 1) * 100
              : rawChangeRate;

          asset.applyNewPrices(finalSellPrice, finalBuyPrice, customRate);

          if (asset.id == "gram") gramFiyat = baseP;
        } else if (apiItem != null && apiItem is Map) {
          if (asset.category == 'crypto') {
            double usdP = _safeDouble(apiItem['USD_Price']);
            double tryP =
                _safeDouble(apiItem['TRY_Price'] ?? apiItem['Selling']);
            double cRate = _safeDouble(apiItem['Change']);

            if (usdP > 0 && tryP > 0) {
              asset.applyNewPrices(
                  tryP * asset.sellMarkup, tryP * asset.buyMarkup, cRate,
                  nUsd: usdP);
            } else if (tryP > 0) {
              asset.applyNewPrices(
                  tryP * asset.sellMarkup, tryP * asset.buyMarkup, cRate,
                  nUsd: tryP / (currentUsdRate > 0 ? currentUsdRate : 34.0));
            }
          } else {
            double rawSell = _safeDouble(apiItem['Selling']);
            double rawBuy = _safeDouble(apiItem['Buying']);
            if (rawBuy <= 0) rawBuy = rawSell;

            if (asset.id == "usd") {
              usdFiyat = rawSell;
              currentUsdRate = rawSell;
            }
            asset.applyNewPrices(rawSell * asset.sellMarkup,
                rawBuy * asset.buyMarkup, _safeDouble(apiItem['Change']));
          }
        }
      }

      if (gramFiyat > 0 && usdFiyat > 0) {
        int onsIndex = market.indexWhere((e) => e.id == "ons");
        if (onsIndex != -1) {
          double onsUsd = (gramFiyat / usdFiyat) * 31.1035;
          double onsTL = gramFiyat * 31.1035;
          market[onsIndex].applyNewPrices(
              onsTL, onsTL, market[onsIndex].changeRate,
              nUsd: onsUsd);
        }
      }

      _syncCustomAssets();
      updateDailyHistory();
      saveMarketCache();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _fetchCryptoFromBinance() async {
    try {
      List<String> symbolsToFetch = ["BTCUSDT", "ETHUSDT"];
      for (String sym in symbolsToFetch) {
        final uri = Uri.parse(
            'https://data-api.binance.vision/api/v3/ticker/24hr?symbol=$sym');
        final response = await http.get(uri, headers: {
          "User-Agent": "Mozilla/5.0",
          "Accept": "application/json"
        });
        if (response.statusCode == 200) {
          Map<String, dynamic> item = json.decode(response.body);
          double lastPrice =
              double.tryParse(item['lastPrice'].toString()) ?? 0.0;
          double change =
              double.tryParse(item['priceChangePercent'].toString()) ?? 0.0;
          String assetId = sym == "BTCUSDT" ? "btc" : "eth";
          var asset = market.firstWhere((e) => e.id == assetId,
              orElse: () => market.first);

          if (asset.id != market.first.id) {
            double usdRateToUse = currentUsdRate > 0 ? currentUsdRate : 44.0;
            double tryPrice = lastPrice * usdRateToUse;
            asset.baseSellPrice = tryPrice * asset.sellMarkup;
            asset.baseBuyPrice = tryPrice * asset.buyMarkup;
            asset.sellPrice = tryPrice * asset.sellMarkup;
            asset.buyPrice = tryPrice * asset.buyMarkup;
            asset.changeRate = change;
            asset.usdPrice = lastPrice;
            asset.baseUsdPrice = lastPrice;
          }
        }
      }
    } catch (e) {}
  }

  // ------------------------------------------------------------------
  // ÜÇÜNCÜ MOTOR: TCMB (Döviz Kurları - API Key Gerektirmez)
  // ------------------------------------------------------------------
  Future<bool> _fetchFromTcmbEngine() async {
    try {
      final response = await http.get(
          Uri.parse('https://www.tcmb.gov.tr/kurlar/today.xml'),
          headers: {"User-Agent": "Mozilla/5.0"});
      if (response.statusCode != 200) return false;

      String body = response.body;

      double usdSelling = _extractTcmbRate(body, 'USD', 'ForexSelling');
      double usdBuying = _extractTcmbRate(body, 'USD', 'ForexBuying');
      double eurSelling = _extractTcmbRate(body, 'EUR', 'ForexSelling');
      double eurBuying = _extractTcmbRate(body, 'EUR', 'ForexBuying');
      double gbpSelling = _extractTcmbRate(body, 'GBP', 'ForexSelling');
      double gbpBuying = _extractTcmbRate(body, 'GBP', 'ForexBuying');

      if (usdSelling <= 0) return false;

      currentUsdRate = usdSelling;

      for (var asset in market) {
        if (asset.id == 'usd') {
          asset.applyNewPrices(usdSelling, usdBuying, asset.changeRate);
        } else if (asset.id == 'eur') {
          asset.applyNewPrices(eurSelling, eurBuying, asset.changeRate);
        } else if (asset.id == 'gbp') {
          asset.applyNewPrices(gbpSelling, gbpBuying, asset.changeRate);
        }
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  double _extractTcmbRate(String xml, String currencyCode, String field) {
    RegExp currencyRegex = RegExp(
        'CurrencyCode="$currencyCode"[^>]*>([\\s\\S]*?)</Currency>',
        multiLine: true);
    Match? currencyMatch = currencyRegex.firstMatch(xml);
    if (currencyMatch == null) return 0.0;

    String currencyBlock = currencyMatch.group(1) ?? '';
    RegExp fieldRegex = RegExp('<$field>([^<]+)</$field>');
    Match? fieldMatch = fieldRegex.firstMatch(currencyBlock);
    if (fieldMatch == null) return 0.0;

    return double.tryParse(fieldMatch.group(1)?.trim() ?? '') ?? 0.0;
  }

  // ------------------------------------------------------------------
  // GEÇMİŞ VERİ BOŞLUKLARINI DOLDUR (Binance Klines + TCMB)
  // ------------------------------------------------------------------
  Future<void> fillHistoricalGaps() async {
    try {
      // Hardcoded verilerdeki en son tarihi bul
      List<String> allDates = assetHistory.keys.toList()..sort();
      if (allDates.isEmpty) return;

      String lastDateStr = allDates.last;
      DateTime lastDate = DateTime.parse(lastDateStr);
      DateTime today = DateTime.now();
      int gapDays = today.difference(lastDate).inDays;

      // 2 günden az boşluk varsa gerek yok
      if (gapDays < 2) return;

      // Zaten doldurulmuş mu kontrol et
      final prefs = await SharedPreferences.getInstance();
      String? lastFillDate = prefs.getString('last_gap_fill_date');
      String todayKey = DateFormat('yyyy-MM-dd').format(today);
      if (lastFillDate == todayKey) return;

      // Binance'den günlük kapanış fiyatları çek (max 365 gün)
      int limit = gapDays > 365 ? 365 : gapDays + 1;
      int startTime = lastDate.millisecondsSinceEpoch;

      // 5 paralel istek: USDTTRY, EURUSDT, PAXGUSDT, BTCUSDT, ETHUSDT
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

      // Her gün için fiyatları hesapla
      Set<String> allNewDates = {
        ...usdRates.keys,
        ...goldOnsUsd.keys,
        ...btcUsd.keys
      };

      for (String dateKey in allNewDates) {
        // Zaten varsa atla
        if (assetHistory.containsKey(dateKey)) continue;

        double usdTry = usdRates[dateKey] ?? currentUsdRate;
        if (usdTry <= 0) continue;

        double eurUsd = eurUsdRates[dateKey] ?? 1.08;
        double paxgUsd = goldOnsUsd[dateKey] ?? 0;
        double btc = btcUsd[dateKey] ?? 0;
        double eth = ethUsd[dateKey] ?? 0;

        // Altın gram bazı hesapla (ons -> gram)
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
        double gbpTry = usdTry * 1.26;

        dPrices["silver"] = silverBaseTL * 1.0957;
        dPrices["usd"] = usdTry * 1.004;
        dPrices["eur"] = eurTry * 1.004;
        dPrices["gbp"] = gbpTry * 1.004;
        dPrices["ons"] = paxgUsd * usdTry;
        dPrices["btc"] = btc * usdTry;
        dPrices["eth"] = eth * usdTry;

        assetHistory[dateKey] = dPrices;
      }

      // Kaydet
      await prefs.setString('asset_history_v2', jsonEncode(assetHistory));
      await prefs.setString('last_gap_fill_date', todayKey);
    } catch (e) {
      // Sessizce devam et, kritik değil
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
        // kline[0] = openTime (ms), kline[4] = close price
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

  double _safeDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      String c = value.replaceAll('\$', '').replaceAll('%', '').trim();
      if (c.contains('.') && c.contains(','))
        c = c.replaceAll('.', '').replaceAll(',', '.');
      else if (c.contains(',')) c = c.replaceAll(',', '.');
      return double.tryParse(c) ?? 0.0;
    }
    return 0.0;
  }

  void _initializeMarketSkeleton() {
    market = [
      AssetType(
          "has", ["HAS", "GRAMHASALTIN"], "Has", "Has Altın", 0, 0, "gold",
          sellMarkup: 1.0767, buyMarkup: 1.0385),
      AssetType(
          "gram", ["GRA", "GRAMALTIN"], "G", "24 Ayar Altın", 0, 0, "gold",
          sellMarkup: 1.0821, buyMarkup: 1.0333),
      AssetType("ceyrek", ["CEYREKALTIN"], "Ç", "Çeyrek Altın", 0, 0, "gold",
          sellMarkup: 1.1040, buyMarkup: 1.0547),
      AssetType("yarim", ["YARIMALTIN"], "Y", "Yarım Altın", 0, 0, "gold",
          sellMarkup: 1.1006, buyMarkup: 1.0547),
      AssetType("tam", ["TAMALTIN"], "T", "Tam Altın", 0, 0, "gold",
          sellMarkup: 1.0964, buyMarkup: 1.0514),
      AssetType("ata", ["ATAALTIN"], "A", "Ata Altın", 0, 0, "gold",
          sellMarkup: 1.0934, buyMarkup: 1.0495),
      AssetType("gremse", ["GREMSEALTIN"], "Grm", "Gremse", 0, 0, "gold",
          sellMarkup: 1.0939, buyMarkup: 1.0482),
      AssetType("resat", ["RESATALTIN"], "R", "Reşat Altın", 0, 0, "gold",
          sellMarkup: 1.0934, buyMarkup: 1.0495),
      AssetType("hamit", ["HAMITALTIN"], "H", "Hamit Altın", 0, 0, "gold",
          sellMarkup: 1.0934, buyMarkup: 1.0495),
      AssetType("gram22", ["YIA", "22AYARBILEZIK"], "22K", "22 Ayar Gram", 0, 0,
          "gold",
          manualInput: false, sellMarkup: 1.1134, buyMarkup: 1.0314),
      AssetType("yarim_gram22", [], "0.5", "0.5 Gram (22K)", 0, 0, "gold",
          manualInput: false, sellMarkup: 1.1134, buyMarkup: 1.0314),
      AssetType(
          "bilezik14", ["14AYARALTIN"], "14K", "14 Ayar Gram", 0, 0, "gold",
          manualInput: false, sellMarkup: 1.3242, buyMarkup: 0.9711),
      AssetType("silver", ["GUMUS"], "Ag", "Gümüş (TL)", 0, 0, "silver",
          manualInput: true, sellMarkup: 1.0957, buyMarkup: 1.0115),
      AssetType("usd", ["USD"], "\$", "ABD Doları", 0, 0, "currency",
          manualInput: true, sellMarkup: 1.004, buyMarkup: 0.996),
      AssetType("eur", ["EUR"], "€", "Euro", 0, 0, "currency",
          manualInput: true, sellMarkup: 1.004, buyMarkup: 0.996),
      AssetType("gbp", ["GBP"], "£", "Sterlin", 0, 0, "currency",
          manualInput: true, sellMarkup: 1.004, buyMarkup: 0.996),
      AssetType("ons", ["ONS"], "ONS", "Altın / ONS", 0, 0, "ons",
          sellMarkup: 1.000, buyMarkup: 1.000, isDollarBase: true),
      AssetType("btc", ["BTC"], "₿", "Bitcoin", 0, 0, "crypto",
          manualInput: false,
          sellMarkup: 1.000,
          buyMarkup: 1.000,
          isDollarBase: true),
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
          String? closestDate;
          for (var d in sortedBtcDates) {
            if (DateTime.parse(d).isAfter(targetDate)) {
              closestDate = d;
              break;
            }
          }
          if (closestDate != null &&
              DateTime.parse(closestDate).difference(targetDate).inDays.abs() <
                  7) {
            btcUsd = realBtcHistory[closestDate]!;
          } else {
            int daysSince2015 =
                targetDate.difference(DateTime(2015, 1, 1)).inDays;
            if (daysSince2015 < 0) daysSince2015 = 0;
            btcUsd = 300.0 * pow(1.00147, daysSince2015);
            if (btcUsd > 120000) btcUsd = 120000.0;
          }
        }

        double eurTry = usdTry * 1.08;
        double gbpTry = usdTry * 1.26;
        double ethUsd = btcUsd * 0.05;
        double goldOns = (rawBase / usdTry) * 31.1035;

        // Gümüş: Gerçek veri varsa kullan, yoksa altından tahmin et
        double silverPrice = 0.0;
        if (realSilverHistory.containsKey(dateKey)) {
          silverPrice = realSilverHistory[dateKey]!;
        } else {
          List<String> sortedSilverDates = realSilverHistory.keys.toList()..sort();
          String? closestDate;
          for (var d in sortedSilverDates) {
            if (DateTime.parse(d).isAfter(targetDate)) {
              closestDate = d;
              break;
            }
          }
          if (closestDate != null &&
              DateTime.parse(closestDate).difference(targetDate).inDays.abs() < 7) {
            silverPrice = realSilverHistory[closestDate]!;
          } else {
            double silverBaseTL = rawBase / 66.0;
            silverPrice = silverBaseTL * 1.0957;
          }
        }

        dPrices["silver"] = silverPrice;
        dPrices["usd"] = usdTry * 1.004;
        dPrices["eur"] = eurTry * 1.004;
        dPrices["gbp"] = gbpTry * 1.004;
        dPrices["ons"] = goldOns * usdTry;
        dPrices["btc"] = btcUsd * usdTry;
        dPrices["eth"] = ethUsd * usdTry;

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
    // Her bölüm için emtia notlarını ayrı kaydet
    List<String> walletNotes = [];
    wallet.assets.forEach((assetId, qty) {
      try {
        var asset = market.firstWhere((e) => e.id == assetId);
        walletNotes.add("${formatNumber(qty)} ${asset.name}");
      } catch (e) {}
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
