import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';

import '../modeller.dart';
import '../bilesenler/ortak_araclar.dart';

// ══════════════════════════════════════════════════════
//  BORSA SAYFASI — Premium kilidi + Canlı BIST 100
// ══════════════════════════════════════════════════════

class BorsaPage extends StatefulWidget {
  final List<AssetType> borsaMarket;
  final bool isPremium;
  final VoidCallback onPremiumTap;
  final Future<void> Function() onRefresh;
  final Function(AssetType) onAssetTap;
  final Function(int, int) onReorder;

  const BorsaPage({
    super.key,
    required this.borsaMarket,
    required this.isPremium,
    required this.onPremiumTap,
    required this.onRefresh,
    required this.onAssetTap,
    required this.onReorder,
  });

  @override
  State<BorsaPage> createState() => _BorsaPageState();
}

class _BorsaPageState extends State<BorsaPage> {
  @override
  Widget build(BuildContext context) {
    if (!widget.isPremium) {
      return _buildLockedView();
    }
    return _buildPremiumContent();
  }

  // ── Premium kilitli bulanık ekran ──
  Widget _buildLockedView() {
    return Stack(
      children: [
        // Arka planda bulanık önizleme
        Positioned.fill(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: _buildFakePreview(),
          ),
        ),
        // Kilit overlay
        Positioned.fill(
          child: Container(
            color: Colors.black.withOpacity(0.5),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black54,
                      border: Border.all(color: AppTheme.goldMain, width: 2),
                    ),
                    child: const Icon(Icons.lock_outline,
                        color: AppTheme.goldMain, size: 40),
                  ),
                  const SizedBox(height: 20),
                  const Text("BORSA",
                      style: TextStyle(
                          color: AppTheme.goldMain,
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text("Premium Abonelik Gerekli",
                      style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      "BIST 100 hisselerini takip etmek, portfoyunuze eklemek ve canli fiyatlari gormek icin Premium abonelik gereklidir.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: widget.onPremiumTap,
                    icon: const Icon(Icons.workspace_premium),
                    label: const Text("Premium Satin Al"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.goldMain,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Kilitli ekran arkasında gözüken sahte önizleme
  Widget _buildFakePreview() {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 15,
      itemBuilder: (c, i) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          height: 60,
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x26FFD700)),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              Container(
                width: 36, height: 36,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF0277BD),
                ),
              ),
              const SizedBox(width: 12),
              Container(width: 60, height: 14, color: Colors.white12),
              const Spacer(),
              Container(width: 50, height: 14, color: Colors.white12),
              const SizedBox(width: 12),
            ],
          ),
        );
      },
    );
  }

  // ── Premium acik icerik ──
  Widget _buildPremiumContent() {
    return RefreshIndicator(
      color: AppTheme.goldMain,
      onRefresh: widget.onRefresh,
      child: Column(
        children: [
          // Favoriler
          _BorsaQuickGrid(
            borsaMarket: widget.borsaMarket,
            onAssetTap: widget.onAssetTap,
          ),
          const SizedBox(height: 8),
          // Tam liste
          Expanded(
            child: _BorsaFullList(
              borsaMarket: widget.borsaMarket,
              onReorder: widget.onReorder,
              onAssetTap: widget.onAssetTap,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
//  BORSA FAVORİ GRİD (6 slot)
// ══════════════════════════════════════════════════════

class _BorsaQuickGrid extends StatefulWidget {
  final List<AssetType> borsaMarket;
  final Function(AssetType) onAssetTap;

  const _BorsaQuickGrid({required this.borsaMarket, required this.onAssetTap});

  @override
  State<_BorsaQuickGrid> createState() => _BorsaQuickGridState();
}

class _BorsaQuickGridState extends State<_BorsaQuickGrid> {
  List<String?> slots = List.filled(6, null);
  static final _fmt = NumberFormat.currency(
      locale: "tr_TR", symbol: "\u20BA", decimalDigits: 2);

  static const _defaultSlots = [
    'thyao', 'asels', 'garan', 'eregl', 'sise', 'froto'
  ];

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  Future<void> _loadSlots() async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? saved = prefs.getStringList('borsa_quick_slots');
    if (saved != null) {
      setState(() {
        slots = saved.map((e) => e == "null" ? null : e).toList();
        while (slots.length < 6) slots.add(null);
      });
    } else {
      setState(() {
        for (int i = 0; i < _defaultSlots.length && i < slots.length; i++) {
          slots[i] = _defaultSlots[i];
        }
      });
    }
  }

  Future<void> _saveSlots() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'borsa_quick_slots', slots.map((e) => e ?? "null").toList());
  }

  void _onSlotTap(int i) {
    if (slots[i] != null) {
      final asset = widget.borsaMarket
          .where((a) => a.id == slots[i])
          .firstOrNull;
      if (asset != null) widget.onAssetTap(asset);
    } else {
      _showPicker(i);
    }
  }

  void _onLongPress(int i) => _showPicker(i);

  void _showPicker(int slotIndex) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text("Hisse Sec",
                style: TextStyle(
                    color: AppTheme.goldMain,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            // Temizle butonu
            if (slots[slotIndex] != null)
              ListTile(
                leading: const Icon(Icons.clear, color: Colors.red),
                title: const Text("Kaldir",
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  setState(() => slots[slotIndex] = null);
                  _saveSlots();
                  Navigator.pop(ctx);
                },
              ),
            ...widget.borsaMarket.where((a) => a.sellPrice > 0).map((a) {
              return ListTile(
                leading: AssetCoin(type: a, size: 28),
                title: Text(a.name,
                    style: const TextStyle(color: Colors.white)),
                trailing: Text(_fmt.format(a.sellPrice),
                    style: const TextStyle(color: AppTheme.goldMain)),
                onTap: () {
                  setState(() => slots[slotIndex] = a.id);
                  _saveSlots();
                  Navigator.pop(ctx);
                },
              );
            }),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final marketMap = {for (var a in widget.borsaMarket) a.id: a};

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 6,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 2.0,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8),
        itemBuilder: (c, i) {
          String? assetId = slots[i];
          AssetType? asset = assetId != null ? marketMap[assetId] : null;

          return GestureDetector(
            onTap: () => _onSlotTap(i),
            onLongPress: () => _onLongPress(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x26FFD700), width: 1),
              ),
              child: assetId == null
                  ? const Center(
                      child: Icon(Icons.add, color: Colors.grey, size: 24))
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(asset?.name ?? assetId.toUpperCase(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(
                          asset != null && asset.sellPrice > 0
                              ? _fmt.format(asset.sellPrice)
                              : "-",
                          style: const TextStyle(
                              color: AppTheme.goldMain,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
//  BORSA TAM LİSTE (ReorderableListView)
// ══════════════════════════════════════════════════════

class _BorsaFullList extends StatefulWidget {
  final List<AssetType> borsaMarket;
  final Function(int, int) onReorder;
  final Function(AssetType) onAssetTap;

  const _BorsaFullList({
    required this.borsaMarket,
    required this.onReorder,
    required this.onAssetTap,
  });

  @override
  State<_BorsaFullList> createState() => _BorsaFullListState();
}

class _BorsaFullListState extends State<_BorsaFullList> {
  static final _fmt = NumberFormat.currency(
      locale: "tr_TR", symbol: "\u20BA", decimalDigits: 2);

  // Fiyat yonu takibi
  final Map<String, double> _prevPrices = {};
  final Map<String, int> _directions = {};
  final Map<String, Timer> _resetTimers = {};

  @override
  void didUpdateWidget(_BorsaFullList oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final item in widget.borsaMarket) {
      final prev = _prevPrices[item.id] ?? 0.0;
      final curr = item.sellPrice;
      if (prev > 0 && curr > 0 && (curr - prev).abs() > prev * 0.000001) {
        final dir = curr > prev ? 1 : -1;
        if (_directions[item.id] != dir) {
          setState(() => _directions[item.id] = dir);
          _resetTimers[item.id]?.cancel();
          _resetTimers[item.id] = Timer(const Duration(seconds: 2), () {
            if (mounted) setState(() => _directions.remove(item.id));
          });
        }
      }
      _prevPrices[item.id] = curr;
    }
  }

  @override
  void dispose() {
    for (final t in _resetTimers.values) t.cancel();
    super.dispose();
  }

  Color _priceColor(int dir) {
    if (dir > 0) return AppTheme.neonGreen;
    if (dir < 0) return AppTheme.neonRed;
    return AppTheme.goldMain;
  }

  @override
  Widget build(BuildContext context) {
    // Sadece fiyatı olan hisseleri goster
    final active = widget.borsaMarket.where((a) => a.sellPrice > 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text("Tum Borsa Listesi (${active.length})",
              style: const TextStyle(
                  color: AppTheme.goldMain,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: active.length,
            onReorder: (oldIdx, newIdx) {
              // global indeksleri bul
              int gOld = widget.borsaMarket.indexOf(active[oldIdx]);
              int gNew = widget.borsaMarket.indexOf(active[newIdx < active.length ? newIdx : active.length - 1]);
              widget.onReorder(gOld, gNew);
            },
            itemBuilder: (c, i) {
              final item = active[i];
              final int dir = _directions[item.id] ?? 0;
              final changeStr = item.changeRate != 0
                  ? "${item.changeRate > 0 ? '+' : ''}${item.changeRate.toStringAsFixed(2)}%"
                  : "";

              return Container(
                key: ValueKey(item.id),
                margin: const EdgeInsets.symmetric(vertical: 3),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x26FFD700)),
                ),
                child: Row(
                  children: [
                    AssetCoin(type: item, size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                          if (changeStr.isNotEmpty)
                            Text(changeStr,
                                style: TextStyle(
                                    color: item.changeRate > 0
                                        ? AppTheme.neonGreen
                                        : item.changeRate < 0
                                            ? AppTheme.neonRed
                                            : Colors.grey,
                                    fontSize: 11)),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => widget.onAssetTap(item),
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 300),
                        style: TextStyle(
                          color: _priceColor(dir),
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                        child: Text(_fmt.format(item.sellPrice)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ReorderableDragStartListener(
                      index: i,
                      child: const Icon(Icons.drag_handle,
                          color: Colors.grey, size: 20),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
