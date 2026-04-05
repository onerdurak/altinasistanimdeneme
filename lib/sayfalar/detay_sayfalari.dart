import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../modeller.dart';
import '../bilesenler/grafikler.dart';
import '../bilesenler/ortak_araclar.dart';

class FullScreenAssetPage extends StatefulWidget {
  final AssetType asset;
  final Map<String, Map<String, dynamic>> history;
  final List<Map<String, dynamic>> intraDayHistory;

  const FullScreenAssetPage(
      {super.key,
      required this.asset,
      required this.history,
      required this.intraDayHistory});

  @override
  State<FullScreenAssetPage> createState() => _FullScreenAssetPageState();
}

class _FullScreenAssetPageState extends State<FullScreenAssetPage>
    with SingleTickerProviderStateMixin {
  String _selectedPeriod = '1A';
  bool _showHistory = false;
  List<Map<String, dynamic>>? _cachedChartData;
  String? _cachedPeriod;

  // --- Canlı fiyat simülasyonu ---
  late double _liveSellPrice;
  late double _liveBuyPrice;
  late double _liveUsdPrice;
  Timer? _liveTimer;
  final Random _random = Random();

  // Nabız animasyonu için
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _liveSellPrice = widget.asset.sellPrice;
    _liveBuyPrice = widget.asset.buyPrice;
    _liveUsdPrice = widget.asset.usdPrice > 0
        ? widget.asset.usdPrice
        : widget.asset.sellPrice;

    // Nabız animasyonu
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulseAnim =
        Tween<double>(begin: 0.3, end: 1.0).animate(_pulseController);

    // Canlı ticker başlat
    _liveTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;

    final baseRef = widget.asset.isDollarBase
        ? widget.asset.baseUsdPrice
        : widget.asset.baseSellPrice;
    if (baseRef <= 0) return;

    final currentBase =
        widget.asset.isDollarBase ? _liveUsdPrice : _liveSellPrice;

    final maxStep = baseRef * 0.0003;
    final step = (_random.nextDouble() - 0.5) * 2.0 * maxStep;
    final maxDev = min(10.0, baseRef * 0.003);
    final newBase =
        (currentBase + step).clamp(baseRef - maxDev, baseRef + maxDev);
    final r = baseRef > 0 ? (newBase - baseRef) / baseRef : 0.0;

    setState(() {
      if (widget.asset.isDollarBase) {
        _liveUsdPrice = newBase;
        _liveSellPrice = widget.asset.baseSellPrice > 0
            ? widget.asset.baseSellPrice * (1 + r)
            : _liveSellPrice;
        _liveBuyPrice = widget.asset.baseBuyPrice > 0
            ? widget.asset.baseBuyPrice * (1 + r)
            : _liveBuyPrice;
      } else {
        _liveSellPrice = newBase;
        _liveBuyPrice = widget.asset.baseBuyPrice > 0
            ? widget.asset.baseBuyPrice * (newBase / baseRef)
            : _liveBuyPrice;
      }

      // Grafiğin son noktasını canlı güncelle (tüm periyotlar)
      if (_cachedChartData != null && _cachedChartData!.isNotEmpty) {
        final displayPrice =
            widget.asset.isDollarBase ? _liveUsdPrice : _liveSellPrice;
        _cachedChartData!.last['val'] = displayPrice;

        // 1G periyodunda her tick'te yeni zaman etiketi de güncelle
        if (_selectedPeriod == '1G') {
          final now = DateTime.now();
          _cachedChartData!.last['label'] =
              DateFormat('HH:mm').format(now);
          _cachedChartData!.last['dateStr'] =
              DateFormat('dd.MM.yyyy HH:mm').format(now);
        }
      }
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _generateChartData(String period) {
    List<Map<String, dynamic>> result = [];
    DateTime now = DateTime.now();

    // Canlı fiyatı kullan
    double currentPrice = widget.asset.isDollarBase
        ? (_liveUsdPrice > 0 ? _liveUsdPrice : widget.asset.usdPrice)
        : (_liveSellPrice > 0 ? _liveSellPrice : widget.asset.sellPrice);
    if (currentPrice <= 0) currentPrice = 1;

    if (period == '1G') {
      if (widget.intraDayHistory.isEmpty) {
        // Gerçek veri yokken dalgalı saatlik simülasyon
        final random = Random();
        for (int h = 23; h >= 0; h--) {
          DateTime t = now.subtract(Duration(hours: h));
          double wave =
              currentPrice * (1 + (random.nextDouble() - 0.5) * 0.006);
          result.add({
            'val': wave,
            'label': DateFormat('HH:mm').format(t),
            'dateStr': DateFormat('dd.MM.yyyy HH:mm').format(t)
          });
        }
        result.last['val'] = currentPrice;
      } else {
        DateTime yesterday = now.subtract(const Duration(hours: 24));
        for (var log in widget.intraDayHistory) {
          DateTime logTime =
              DateFormat('yyyy-MM-dd HH:mm').parse(log["time"]);
          if (logTime.isAfter(yesterday)) {
            double p =
                (log["prices"][widget.asset.id] as num?)?.toDouble() ??
                    currentPrice;
            result.add({
              'val': p,
              'label': DateFormat('HH:mm').format(logTime),
              'dateStr': DateFormat('dd.MM.yyyy HH:mm').format(logTime)
            });
          }
        }
        if (result.isEmpty ||
            result.last['label'] != DateFormat('HH:mm').format(now)) {
          result.add({
            'val': currentPrice,
            'label': DateFormat('HH:mm').format(now),
            'dateStr': DateFormat('dd.MM.yyyy HH:mm').format(now)
          });
        } else {
          result.last['val'] = currentPrice;
        }
      }
      return result;
    }

    List<String> sortedDates = widget.history.keys.toList()..sort();
    if (sortedDates.isEmpty) return result;

    if (period == '1A') {
      int daysToTake = 30;
      if (daysToTake < sortedDates.length)
        sortedDates =
            sortedDates.sublist(sortedDates.length - daysToTake);
    } else if (period == '1Y') {
      int daysToTake = 365;
      if (daysToTake < sortedDates.length)
        sortedDates =
            sortedDates.sublist(sortedDates.length - daysToTake);
      sortedDates =
          sortedDates.where((d) => d.endsWith('-01')).toList();
    }

    for (String dateKey in sortedDates) {
      double p =
          (widget.history[dateKey]?[widget.asset.id] as num?)?.toDouble() ??
              currentPrice;
      DateTime dt = DateTime.parse(dateKey);
      String labelStr = period == '1A'
          ? DateFormat('dd MMM', 'tr_TR').format(dt)
          : DateFormat('MMM yy', 'tr_TR').format(dt);
      result.add({
        'val': p,
        'label': labelStr,
        'dateStr': DateFormat('dd.MM.yyyy').format(dt)
      });
    }

    String todayLabel = period == '1A'
        ? DateFormat('dd MMM', 'tr_TR').format(now)
        : DateFormat('MMM yy', 'tr_TR').format(now);
    String todayFullStr = DateFormat('dd.MM.yyyy').format(now);

    if (result.isEmpty || result.last['dateStr'] != todayFullStr) {
      result.add({
        'val': currentPrice,
        'label': todayLabel,
        'dateStr': todayFullStr
      });
    } else {
      result.last['val'] = currentPrice;
    }

    return result;
  }

  Widget _buildPeriodButton(String title, String value) {
    bool isSelected = _selectedPeriod == value;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          _selectedPeriod = value;
          // Periyot değişince cache temizle, yeni data üretilsin
          _cachedChartData = null;
          _cachedPeriod = null;
        });
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
            color: isSelected
                ? const Color(0x14FFFFFF)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color:
                    isSelected ? Colors.white10 : Colors.transparent)),
        child: Text(title,
            style: TextStyle(
                color: isSelected ? Colors.white : Colors.white38,
                fontWeight: isSelected
                    ? FontWeight.bold
                    : FontWeight.normal,
                fontSize: 13,
                letterSpacing: 1.1)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String symbol = widget.asset.isDollarBase ? "\$" : "₺";
    String locale = widget.asset.isDollarBase ? "en_US" : "tr_TR";
    int decimals = widget.asset.category == 'currency' ||
            (widget.asset.isDollarBase && _liveUsdPrice < 1000)
        ? 2
        : 0;
    final format = NumberFormat.currency(
        locale: locale, symbol: symbol, decimalDigits: decimals);

    // Canlı fiyatları göster
    String sellStr = format.format(
        widget.asset.isDollarBase ? _liveUsdPrice : _liveSellPrice);
    String buyStr = format.format(
        widget.asset.isDollarBase ? _liveUsdPrice : _liveBuyPrice);

    if (_cachedPeriod != _selectedPeriod || _cachedChartData == null) {
      _cachedChartData = _generateChartData(_selectedPeriod);
      _cachedPeriod = _selectedPeriod;
    }
    final chartData = _cachedChartData!;

    return Container(
      height: _showHistory
          ? MediaQuery.of(context).size.height * 0.85
          : MediaQuery.of(context).size.height * 0.55,
      decoration: const BoxDecoration(
          color: AppTheme.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10))),
          Padding(
            padding: const EdgeInsets.only(
                left: 20, right: 10, top: 10, bottom: 5),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    AssetCoin(type: widget.asset, size: 36),
                    const SizedBox(width: 12),
                    Text(widget.asset.name,
                        style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.5))
                  ]),
                  Row(children: [
                    // Canlı nabız göstergesi
                    FadeTransition(
                      opacity: _pulseAnim,
                      child: Row(children: [
                        Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                                color: AppTheme.neonGreen,
                                shape: BoxShape.circle)),
                        const SizedBox(width: 5),
                        const Text("CANLI",
                            style: TextStyle(
                                color: AppTheme.neonGreen,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white54, size: 28),
                        onPressed: () => Navigator.pop(context)),
                  ]),
                ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    child: Column(
                      children: [
                        Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceEvenly,
                            children: [
                              Column(children: [
                                const Text("ALIŞ",
                                    style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 11,
                                        letterSpacing: 1.2)),
                                const SizedBox(height: 5),
                                // AnimatedSwitcher ile fiyat değişimi vurgusu
                                AnimatedSwitcher(
                                  duration:
                                      const Duration(milliseconds: 400),
                                  transitionBuilder: (child, anim) =>
                                      FadeTransition(
                                          opacity: anim, child: child),
                                  child: Text(buyStr,
                                      key: ValueKey(buyStr),
                                      style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF00E676))),
                                ),
                              ]),
                              Container(
                                  width: 1,
                                  height: 35,
                                  color: Colors.white10),
                              Column(children: [
                                const Text("SATIŞ",
                                    style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 11,
                                        letterSpacing: 1.2)),
                                const SizedBox(height: 5),
                                AnimatedSwitcher(
                                  duration:
                                      const Duration(milliseconds: 400),
                                  transitionBuilder: (child, anim) =>
                                      FadeTransition(
                                          opacity: anim, child: child),
                                  child: Text(sellStr,
                                      key: ValueKey(sellStr),
                                      style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.goldMain)),
                                ),
                              ]),
                            ]),
                        const SizedBox(height: 20),
                        Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                                color: AppTheme.card,
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: Colors.white10)),
                            child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildPeriodButton("1G", "1G"),
                                  _buildPeriodButton("1A", "1A"),
                                  _buildPeriodButton("1Y", "1Y"),
                                ])),
                        const SizedBox(height: 15),
                        Container(
                            height: 160,
                            padding: const EdgeInsets.only(
                                top: 15,
                                right: 0,
                                left: 0,
                                bottom: 0),
                            width: double.infinity,
                            child: InteractiveChart(
                                data: chartData,
                                color: const Color(0xFF00E676),
                                formatter: format)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(
                          () => _showHistory = !_showHistory);
                    },
                    child: Container(
                      margin:
                          const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                          color: AppTheme.card,
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: Colors.white10)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.history_rounded,
                              color: AppTheme.goldMain, size: 20),
                          const SizedBox(width: 8),
                          const Text("GEÇMİŞ",
                              style: TextStyle(
                                  color: AppTheme.goldMain,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2)),
                          const SizedBox(width: 8),
                          Icon(
                              _showHistory
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons
                                      .keyboard_arrow_down_rounded,
                              color: AppTheme.goldMain,
                              size: 22),
                        ],
                      ),
                    ),
                  ),
                  if (_showHistory) ...[
                    const SizedBox(height: 10),
                    ListView.builder(
                      shrinkWrap: true,
                      physics:
                          const NeverScrollableScrollPhysics(),
                      itemCount: chartData.length,
                      itemBuilder: (c, i) {
                        int index = chartData.length - 1 - i;
                        var item = chartData[index];
                        return ListTile(
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(
                                  horizontal: 20),
                          leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                  color: const Color(0x0AFFFFFF),
                                  shape: BoxShape.circle),
                              child: const Icon(
                                  Icons.history_rounded,
                                  color: Colors.grey,
                                  size: 18)),
                          title: Text(item['dateStr'],
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14)),
                          trailing: Text(
                              format.format(item['val']),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Colors.white)),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
