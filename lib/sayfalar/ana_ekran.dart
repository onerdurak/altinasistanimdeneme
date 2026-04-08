import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';

import '../modeller.dart';
import '../bilesenler/ortak_araclar.dart';
import '../bilesenler/grafikler.dart';

class DashboardPage extends StatefulWidget {
  final double netWorth;
  final double wallet, credit, debt;
  final List<AssetType> market;
  final bool isAppLocked;
  final VoidCallback onToggleLock;
  final VoidCallback onMoreTap;
  final Function(AssetType) onAssetTap;
  final Function(String, String, Color) onStatTap;
  final Future<void> Function() onRefresh;
  final bool isPrimaryEngineActive;
  final bool isConnected;

  const DashboardPage(
      {super.key,
      required this.netWorth,
      required this.market,
      required this.wallet,
      required this.credit,
      required this.debt,
      required this.isAppLocked,
      required this.onToggleLock,
      required this.onMoreTap,
      required this.onAssetTap,
      required this.onStatTap,
      required this.isPrimaryEngineActive,
      required this.isConnected,
      required this.onRefresh});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  static final _currency =
      NumberFormat.currency(locale: "tr_TR", symbol: "₺", decimalDigits: 0);
  bool _isObscured = false;
  bool _isLoadingPrefs = true;

  @override
  void initState() {
    super.initState();
    _loadObscuredState();
  }

  Future<void> _loadObscuredState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isObscured = prefs.getBool('is_obscured') ?? false;
      _isLoadingPrefs = false;
    });
  }

  Future<void> _toggleObscure() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _isObscured = !_isObscured);
    await prefs.setBool('is_obscured', _isObscured);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingPrefs)
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.goldMain));
    return RefreshIndicator(
      color: AppTheme.goldMain,
      backgroundColor: AppTheme.card,
      onRefresh: widget.onRefresh,
      child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            if (!widget.isConnected)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                decoration: BoxDecoration(
                    color: const Color(0xFF3E2723),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withAlpha(80))),
                child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off, color: Colors.orange, size: 16),
                      SizedBox(width: 8),
                      Text("İnternet bağlantısı yok",
                          style: TextStyle(color: Colors.orange, fontSize: 12)),
                    ])),
            Stack(children: [
              GestureDetector(
                  onTap: () {
                    if (!widget.isAppLocked)
                      widget.onStatTap(
                          "NET FİNANSAL DURUM", "net", Colors.white);
                  },
                  child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Color(0xFF2E2E2E), Color(0xFF111111)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(color: Colors.white12),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x80000000),
                                blurRadius: 15,
                                offset: Offset(0, 10))
                          ]),
                      child: widget.isAppLocked
                          ? GestureDetector(
                              onTap: widget.onToggleLock,
                              behavior: HitTestBehavior.opaque,
                              child: const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 40),
                                  child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.lock,
                                            color: AppTheme.goldMain, size: 36),
                                        SizedBox(height: 10),
                                        Text("KİLİTLİ",
                                            style: TextStyle(
                                                color: AppTheme.goldMain,
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 2)),
                                        SizedBox(height: 5),
                                        Text("Açmak için dokunun",
                                            style: TextStyle(
                                                color: Colors.white54,
                                                fontSize: 12))
                                      ])))
                          : Column(children: [
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text("NET FİNANSAL DURUM",
                                        style: TextStyle(
                                            color: Color(0xFF9E9E9E),
                                            letterSpacing: 1.2,
                                            fontSize: 12)),
                                    const SizedBox(width: 6),
                                    IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: Icon(
                                            _isObscured
                                                ? Icons.visibility_off
                                                : Icons.visibility,
                                            color: Colors.grey,
                                            size: 18),
                                        onPressed: _toggleObscure),
                                  ]),
                              const SizedBox(height: 4),
                              Text(
                                  _isObscured
                                      ? "₺ ***"
                                      : _currency.format(widget.netWorth),
                                  style: const TextStyle(
                                      color: Color(0xFFEDEDED),
                                      fontSize: 32,
                                      fontWeight: FontWeight.w900)),
                              const Divider(color: Colors.white10, height: 24),
                              Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => widget.onStatTap(
                                            "KASA GEÇMİŞİ",
                                            "wallet",
                                            AppTheme.goldMain),
                                        child: MiniStat("Kasa", widget.wallet,
                                            AppTheme.goldMain,
                                            isObscured: _isObscured)),
                                    GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => widget.onStatTap(
                                            "ALACAK GEÇMİŞİ",
                                            "credit",
                                            AppTheme.neonGreen),
                                        child: MiniStat("Alacak", widget.credit,
                                            AppTheme.neonGreen,
                                            isObscured: _isObscured)),
                                    GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => widget.onStatTap(
                                            "BORÇ GEÇMİŞİ",
                                            "debt",
                                            AppTheme.neonRed),
                                        child: MiniStat("Borç", widget.debt,
                                            AppTheme.neonRed,
                                            isObscured: _isObscured))
                                  ])
                            ]))),
              Positioned(
                  top: 10,
                  right: 10,
                  child: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                          widget.isAppLocked
                              ? Icons.lock
                              : Icons.lock_open_rounded,
                          color: widget.isAppLocked
                              ? AppTheme.neonRed
                              : AppTheme.goldMain,
                          size: 20),
                      onPressed: widget.onToggleLock))
            ]),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                  onPressed: widget.onMoreTap,
                  child: Text(
                      widget.isPrimaryEngineActive
                          ? "Tüm Piyasa >>"
                          : "Tüm Piyasa >",
                      style:
                          const TextStyle(color: AppTheme.goldMain, fontSize: 12)))
            ]),
            QuickAccessGrid(
                market: widget.market, onAssetTap: widget.onAssetTap),
            Container(
                margin: const EdgeInsets.only(top: 30, bottom: 20),
                alignment: Alignment.center,
                child: const Text(
                    "Piyasa verileri ve grafikler temsilidir, sadece bilgi amaçlı sunulmaktadır.",
                    style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.w400),
                    textAlign: TextAlign.center)),
            const SizedBox(height: 50)
          ])),
    );
  }
}

class QuickAccessGrid extends StatefulWidget {
  final List<AssetType> market;
  final Function(AssetType) onAssetTap;
  const QuickAccessGrid(
      {super.key, required this.market, required this.onAssetTap});
  @override
  State<QuickAccessGrid> createState() => _QuickAccessGridState();
}

class _QuickAccessGridState extends State<QuickAccessGrid> {
  List<String?> slots = List.filled(16, null);
  bool isEditing = false;
  static final _currency0 =
      NumberFormat.currency(locale: "tr_TR", symbol: "₺", decimalDigits: 0);
  static final _currency2 =
      NumberFormat.currency(locale: "tr_TR", symbol: "₺", decimalDigits: 2);
  static final _cryptoFmt =
      NumberFormat.currency(locale: "en_US", symbol: "\$", decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  Future<void> _loadSlots() async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? saved = prefs.getStringList('quick_slots');
    if (saved != null) {
      setState(() {
        slots = saved.map((e) => e == "null" ? null : e).toList();
        while (slots.length < 16) slots.add(null);
      });
    } else {
      setState(() {
        const defaultSlots = [
          "gram", "gram22", "usd", "ceyrek",
          "ons", "btc", null, null,
          null, null, null, null,
          null, null, null, null,
        ];
        for (int j = 0; j < defaultSlots.length && j < 16; j++) {
          slots[j] = defaultSlots[j];
        }
      });
    }
  }

  Future<void> _saveSlots() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> toSave = slots.map((e) => e ?? "null").toList();
    await prefs.setStringList('quick_slots', toSave);
  }

  void _onSlotTap(int index) {
    if (isEditing) {
      setState(() => isEditing = false);
      return;
    }
    if (slots[index] == null) {
      showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (c) => Container(
                height: MediaQuery.of(context).size.height * 0.7,
                decoration: const BoxDecoration(
                    color: AppTheme.bg,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(25))),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(10))),
                    const SizedBox(height: 20),
                    const Text("HIZLI ERİŞİME EKLE",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2)),
                    const SizedBox(height: 15),
                    Expanded(
                      child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: widget.market.length,
                          itemBuilder: (c, i) {
                            var item = widget.market[i];
                            if (item.id == 'tl') return const SizedBox.shrink();
                            if (item.sellPrice <= 0 && !item.isDollarBase)
                              return const SizedBox.shrink();
                            if (slots.contains(item.id))
                              return const SizedBox.shrink();

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                  color: AppTheme.card,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white10),
                                  boxShadow: [
                                    BoxShadow(
                                        color: const Color(0x33000000),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4))
                                  ]),
                              child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 4),
                                  leading: AssetCoin(type: item, size: 40),
                                  title: Text(item.name,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                  subtitle: Text(item.category.toUpperCase(),
                                      style: const TextStyle(
                                          color: Colors.grey, fontSize: 11)),
                                  trailing: const Icon(Icons.add_circle_outline,
                                      color: AppTheme.goldMain),
                                  onTap: () {
                                    setState(() => slots[index] = item.id);
                                    _saveSlots();
                                    Navigator.pop(c);
                                  }),
                            );
                          }),
                    ),
                  ],
                ),
              ));
    } else {
      var asset = widget.market.firstWhere((e) => e.id == slots[index],
          orElse: () => widget.market[0]);
      widget.onAssetTap(asset);
    }
  }

  void _onLongPress(int index) {
    if (slots[index] != null) {
      HapticFeedback.heavyImpact();
      setState(() => isEditing = true);
    }
  }

  void _removeItem(int index) {
    setState(() => slots[index] = null);
    _saveSlots();
  }

  @override
  Widget build(BuildContext context) {
    final marketMap = {for (var a in widget.market) a.id: a};
    return GestureDetector(
        onTap: () {
          if (isEditing) setState(() => isEditing = false);
        },
        child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 16,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 2.2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10),
            itemBuilder: (c, i) {
              String? assetId = slots[i];
              AssetType? asset = assetId != null ? marketMap[assetId] : null;
              bool isDollar = asset?.isDollarBase ?? false;

              return RepaintBoundary(
                child: GestureDetector(
                  onTap: () => _onSlotTap(i),
                  onLongPress: () => _onLongPress(i),
                  child: Stack(clipBehavior: Clip.none, children: [
                    // Sabit altın çerçeve, fiyat yazısı renklenir
                    Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                            color: AppTheme.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: const Color(0x26FFD700),
                                width: 1.0),
                            boxShadow: [
                              BoxShadow(
                                  color: const Color(0x0FFFD700),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 2)),
                            ]),
                        child: assetId == null
                            ? const Center(
                                child: Icon(Icons.add,
                                    color: Colors.grey, size: 30))
                            : Row(children: [
                                AssetCoin(type: asset!, size: 32),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(asset.name,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 2),
                                      Row(children: [
                                        Text(
                                              asset.sellPrice > 0
                                                  ? (isDollar
                                                      ? _cryptoFmt.format(
                                                          asset.usdPrice > 0
                                                              ? asset.usdPrice
                                                              : asset.sellPrice)
                                                      : (asset.category ==
                                                              'currency'
                                                          ? _currency2.format(
                                                              asset.sellPrice)
                                                          : _currency0.format(
                                                              asset.sellPrice)))
                                                  : "-",
                                              style: const TextStyle(
                                                  color: AppTheme.goldMain,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold)),
                                        const SizedBox(width: 4),
                                        if (asset.changeRate > 0)
                                          const Icon(Icons.arrow_drop_up,
                                              color: AppTheme.neonGreen,
                                              size: 18)
                                        else if (asset.changeRate < 0)
                                          const Icon(Icons.arrow_drop_down,
                                              color: AppTheme.neonRed, size: 18)
                                      ])
                                    ]))
                              ])),
                    if (isEditing && assetId != null)
                      Positioned(
                          top: -5,
                          right: -5,
                          child: GestureDetector(
                              onTap: () => _removeItem(i),
                              child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                      color: AppTheme.neonRed,
                                      shape: BoxShape.circle),
                                  child: const Icon(Icons.remove,
                                      color: Colors.white, size: 16))))
                  ]),
                ),
              );
            }));
  }
}

// Grafik Sayfası
class HistoryChartPage extends StatefulWidget {
  final String title;
  final String dataKey;
  final List<Map<String, dynamic>> historyData;
  final Color color;

  const HistoryChartPage(
      {super.key,
      required this.title,
      required this.dataKey,
      required this.historyData,
      required this.color});

  @override
  State<HistoryChartPage> createState() => _HistoryChartPageState();
}

class _HistoryChartPageState extends State<HistoryChartPage> {
  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    if (widget.historyData.isEmpty) {
      return Scaffold(
          appBar: AppBar(title: Text(widget.title)),
          body: const Center(
              child: Text("Henüz yeterli veri oluşmadı.",
                  style: TextStyle(color: Colors.grey))));
    }
    final currency =
        NumberFormat.currency(locale: "tr_TR", symbol: "₺", decimalDigits: 0);

    return Scaffold(
        appBar: AppBar(
            title: Text(widget.title, style: TextStyle(color: widget.color))),
        body: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Container(
                  height: 250,
                  padding: const EdgeInsets.only(
                      top: 20, right: 10, left: 10, bottom: 10),
                  width: double.infinity,
                  decoration: BoxDecoration(
                      color: AppTheme.card,
                      borderRadius: BorderRadius.circular(20)),
                  child: InteractiveHistoryChart(
                      data: widget.historyData,
                      dataKey: widget.dataKey,
                      color: widget.color,
                      formatter: currency)),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _showHistory = !_showHistory);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                      color: AppTheme.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10)),
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
                              : Icons.keyboard_arrow_down_rounded,
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
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: widget.historyData.length,
                    itemBuilder: (c, i) {
                      int reverseIndex = widget.historyData.length - 1 - i;
                      var entry = widget.historyData[reverseIndex];
                      String rawDate = entry['date'].toString();
                      String displayDate = rawDate;
                      try {
                        DateTime d = DateTime.parse(rawDate);
                        displayDate =
                            "${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}";
                      } catch (e) {}

                      String noteKey = '${widget.dataKey}_note';
                      String note =
                          (entry[noteKey] ?? entry['note'] ?? '').toString();

                      return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: AppTheme.card,
                              borderRadius: BorderRadius.circular(12)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(children: [
                                        Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                                color: Colors.white
                                                    .withOpacity(0.05),
                                                shape: BoxShape.circle),
                                            child: const Icon(
                                                Icons.calendar_month_rounded,
                                                color: Colors.grey,
                                                size: 16)),
                                        const SizedBox(width: 8),
                                        Text(displayDate,
                                            style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 14)),
                                      ]),
                                      Text(
                                          currency.format(entry[widget.dataKey]),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15)),
                                    ]),
                                if (note.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  const Divider(
                                      color: Colors.white10, height: 1),
                                  const SizedBox(height: 8),
                                  ...note.split('\n').map((line) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 3),
                                      child: Text(line,
                                          style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 12),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 2))),
                                ],
                              ]));
                    }),
              ],
              const SizedBox(height: 20),
            ])));
  }
}
