import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../modeller.dart';
import '../bilesenler/ortak_araclar.dart';

class ListingPage extends StatefulWidget {
  final List<PortfolioItem> items;
  final List<AssetType> market;
  final List<AssetType> borsaMarket;
  final bool isCredit;
  final Function(PortfolioItem) onTap;
  final Function(PortfolioItem) onDelete;
  final Future<void> Function() onRefresh;

  const ListingPage(
      {super.key,
      required this.items,
      required this.market,
      this.borsaMarket = const [],
      required this.isCredit,
      required this.onTap,
      required this.onDelete,
      required this.onRefresh});

  @override
  State<ListingPage> createState() => _ListingPageState();
}

class _ListingPageState extends State<ListingPage> {
  static final _currency =
      NumberFormat.currency(locale: "tr_TR", symbol: "₺", decimalDigits: 0);
  String? _editingItemId;
  final Set<String> _collapsedItems = {};

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return RefreshIndicator(
        color: AppTheme.goldMain,
        backgroundColor: AppTheme.card,
        onRefresh: widget.onRefresh,
        child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Container(
                height: 500,
                alignment: Alignment.center,
                child: const Text("Kayıt Bulunamadı",
                    style: TextStyle(color: Colors.white24)))),
      );
    }
    final allMarket = [...widget.market, ...widget.borsaMarket];
    final marketMap = {for (var a in allMarket) a.id: a};
    return GestureDetector(
      onTap: () => setState(() => _editingItemId = null),
      child: RefreshIndicator(
        color: AppTheme.goldMain,
        backgroundColor: AppTheme.card,
        onRefresh: widget.onRefresh,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: widget.items.length,
          itemBuilder: (c, i) {
            var item = widget.items[i];
            double val = item.getTotalValue(allMarket);
            bool isEditing = _editingItemId == item.id;
            bool isExpanded = !_collapsedItems.contains(item.id);

            return GestureDetector(
                onLongPress: () {
                  HapticFeedback.heavyImpact();
                  setState(() => _editingItemId = item.id);
                },
                onTap: () {
                  if (isEditing) {
                    setState(() => _editingItemId = null);
                  } else {
                    widget.onTap(item);
                  }
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                          color: AppTheme.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border(
                              left: BorderSide(
                                  color: widget.isCredit
                                      ? AppTheme.neonGreen
                                      : AppTheme.neonRed,
                                  width: 3))),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: widget.isCredit
                                  ? const Color(0xFF122A15)
                                  : const Color(0xFF2A1215),
                              borderRadius: const BorderRadius.only(
                                topRight: Radius.circular(16),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(item.personName,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis),
                                    ])),
                                const SizedBox(width: 10),
                                Text(_currency.format(val),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      if (isExpanded) {
                                        _collapsedItems.add(item.id);
                                      } else {
                                        _collapsedItems.remove(item.id);
                                      }
                                    });
                                  },
                                  child: Icon(
                                    isExpanded
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    color: Colors.white38,
                                    size: 22,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isExpanded && item.assets.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                  left: 16, right: 16, bottom: 14),
                              child: Builder(builder: (context) {
                                final assetEntries = item.assets.entries.toList();
                                return Column(
                                children: List.generate(assetEntries.length, (idx) {
                                  final entry = assetEntries[idx];
                                  final assetId = entry.key;
                                  final qty = entry.value;
                                  final asset = marketMap[assetId];
                                  if (asset == null) return const SizedBox.shrink();
                                  final assetVal = asset.sellPrice * qty;
                                  final isLast = idx == item.assets.length - 1;
                                  return Column(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        child: Row(
                                          children: [
                                            AssetCoin(type: asset, size: 30),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(asset.name,
                                                      style: const TextStyle(
                                                          color: Colors.white70,
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.w500)),
                                                  const SizedBox(height: 2),
                                                  Text("x ${formatNumber(qty)} adet",
                                                      style: TextStyle(
                                                          color: const Color(0x59FFFFFF),
                                                          fontSize: 11)),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Text(_currency.format(assetVal),
                                                style: TextStyle(
                                                    color: widget.isCredit
                                                        ? const Color(0xFF66BB6A)
                                                        : const Color(0xFFEF5350),
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600)),
                                          ],
                                        ),
                                      ),
                                      if (!isLast)
                                        Divider(
                                          color: const Color(0x0FFFFFFF),
                                          height: 1,
                                          thickness: 0.5,
                                        ),
                                    ],
                                  );
                                }),
                              );
                              }),
                            ),
                        ],
                      ),
                    ),
                    if (isEditing)
                      Positioned(
                          top: -10,
                          right: -5,
                          child: GestureDetector(
                              onTap: () => widget.onDelete(item),
                              child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                      color: AppTheme.neonRed,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white, width: 2)),
                                  child: const Icon(Icons.delete_forever,
                                      color: Colors.white, size: 20)))),
                  ],
                ),
            );
          },
        ),
      ),
    );
  }
}

class PortfolioCreator extends StatefulWidget {
  final bool isCredit;
  final List<AssetType> market;
  final List<AssetType> borsaMarket;
  final bool isPremium;
  final Function(PortfolioItem) onSave;

  const PortfolioCreator(
      {super.key,
      required this.isCredit,
      required this.market,
      this.borsaMarket = const [],
      this.isPremium = false,
      required this.onSave});

  @override
  State<PortfolioCreator> createState() => _PortfolioCreatorState();
}

class _PortfolioCreatorState extends State<PortfolioCreator> {
  static final _currency =
      NumberFormat.currency(locale: "tr_TR", symbol: "₺", decimalDigits: 0);
  final _nameCtrl = TextEditingController();
  final Map<String, double> _liveAssets = {};

  void _updateQuantity(AssetType asset) {
    if (asset.manualInput) {
      showDialog(
        context: context,
        builder: (c) {
          TextEditingController qtyCtrl = TextEditingController();
          return AlertDialog(
            backgroundColor: AppTheme.card,
            title: Text("${asset.name} Miktarı",
                style: const TextStyle(color: Colors.white)),
            content: TextField(
                controller: qtyCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                    hintText: "Miktar giriniz...",
                    hintStyle: TextStyle(color: Colors.grey))),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text("İPTAL")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.goldMain,
                    foregroundColor: Colors.black),
                onPressed: () {
                  double? val =
                      double.tryParse(qtyCtrl.text.replaceAll(',', '.'));
                  if (val != null && val > 0) {
                    setState(() => _liveAssets[asset.id] = val);
                  }
                  Navigator.pop(c);
                },
                child: const Text("EKLE"),
              )
            ],
          );
        },
      );
    } else {
      setState(() => _liveAssets[asset.id] = (_liveAssets[asset.id] ?? 0) + 1);
    }
  }

  void _save() {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Lütfen bir isim giriniz!"),
          backgroundColor: AppTheme.neonRed));
      return;
    }
    if (_liveAssets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Lütfen en az bir varlık seçiniz."),
          backgroundColor: Colors.grey));
      return;
    }
    widget.onSave(PortfolioItem(
        id: DateTime.now().toString(),
        personName: _nameCtrl.text,
        isCredit: widget.isCredit,
        assets: _liveAssets,
        date: DateTime.now()));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final allMarket = [...widget.market, ...widget.borsaMarket];
    final marketMap = {for (var a in allMarket) a.id: a};
    double liveTotal = 0;
    _liveAssets.forEach((k, v) {
      var asset = marketMap[k];
      if (asset != null) liveTotal += asset.sellPrice * v;
    });

    return Scaffold(
      appBar: AppBar(
          title: Text(widget.isCredit ? "ALACAK OLUŞTUR" : "BORÇ OLUŞTUR")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
                controller: _nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                    labelText: "Kişi/Kurum Adı (Zorunlu)",
                    labelStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: AppTheme.card,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none))),
          ),
          SizedBox(
            height: 72,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: widget.market.length,
              itemBuilder: (c, i) {
                var asset = widget.market[i];
                if (asset.sellPrice <= 0 && !asset.isDollarBase)
                  return const SizedBox.shrink();
                return GestureDetector(
                  onTap: () => _updateQuantity(asset),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 64,
                    decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10)),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AssetCoin(type: asset, size: 26),
                        const SizedBox(height: 4),
                        Text(asset.label,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11)),
                        Text(asset.name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 7),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.arrow_forward_ios_rounded,
                    color: Colors.white24, size: 12),
                SizedBox(width: 2),
                Text("kaydır",
                    style: TextStyle(color: Colors.white24, fontSize: 10)),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 30),
          Expanded(
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              itemCount: _liveAssets.length,
              itemBuilder: (c, i) {
                String id = _liveAssets.keys.elementAt(i);
                double qty = _liveAssets[id]!;
                var asset = marketMap[id];
                if (asset == null) return const SizedBox.shrink();
                return Container(
                  margin:
                      const EdgeInsets.only(bottom: 10, left: 16, right: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                      color: AppTheme.card,
                      borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      AssetCoin(type: asset, size: 40),
                      const SizedBox(width: 15),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(asset.name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(_currency.format(qty * asset.sellPrice),
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 13))
                          ])),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                              iconSize: 20,
                              icon: const Icon(Icons.remove_circle_outline,
                                  color: AppTheme.neonRed),
                              onPressed: () {
                                setState(() {
                                  if (qty > 1) {
                                    _liveAssets[id] = qty - 1;
                                  } else {
                                    _liveAssets.remove(id);
                                  }
                                });
                              }),
                          const SizedBox(width: 8),
                          GestureDetector(
                              onTap: () => _updateQuantity(asset),
                              child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: Colors.black45,
                                      borderRadius: BorderRadius.circular(6)),
                                  child: Text(formatNumber(qty),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold)))),
                          const SizedBox(width: 8),
                          IconButton(
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                              iconSize: 20,
                              icon: const Icon(Icons.add_circle_outline,
                                  color: AppTheme.neonGreen),
                              onPressed: () {
                                setState(() {
                                  _liveAssets[id] = qty + 1;
                                });
                              }),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(20),
            color: AppTheme.card,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text("TOPLAM DEĞER",
                      style: TextStyle(color: Colors.grey, fontSize: 10)),
                  Text(_currency.format(liveTotal),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold))
                ]),
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.goldMain,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12)),
                    onPressed: _save,
                    child: const Text("KAYDET",
                        style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

class PortfolioDetail extends StatefulWidget {
  final PortfolioItem item;
  final List<AssetType> market;
  final List<AssetType> borsaMarket;
  final bool isPremium;
  final VoidCallback onUpdate;
  final bool isWallet;
  final Future<void> Function() onRefresh;
  final Function(AssetType) onAssetTap;

  const PortfolioDetail(
      {super.key,
      required this.item,
      required this.market,
      this.borsaMarket = const [],
      this.isPremium = false,
      required this.onUpdate,
      this.isWallet = false,
      required this.onRefresh,
      required this.onAssetTap});

  @override
  State<PortfolioDetail> createState() => _PortfolioDetailState();
}

class _PortfolioDetailState extends State<PortfolioDetail> {
  static final _currency =
      NumberFormat.currency(locale: "tr_TR", symbol: "₺", decimalDigits: 0);
  String? _deletingAssetId;

  void _addAssetDialog(AssetType asset) {
    if (asset.manualInput) {
      showDialog(
        context: context,
        builder: (c) {
          TextEditingController qtyCtrl = TextEditingController();
          return AlertDialog(
            backgroundColor: AppTheme.card,
            title: Text("${asset.name} Ekle",
                style: const TextStyle(color: Colors.white)),
            content: TextField(
                controller: qtyCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(hintText: "Miktar")),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text("İPTAL")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.goldMain,
                    foregroundColor: Colors.black),
                onPressed: () {
                  double? val =
                      double.tryParse(qtyCtrl.text.replaceAll(',', '.'));
                  if (val != null) {
                    setState(() => widget.item.assets[asset.id] =
                        (widget.item.assets[asset.id] ?? 0) + val);
                    widget.onUpdate();
                  }
                  Navigator.pop(c);
                  Navigator.pop(context);
                },
                child: const Text("EKLE"),
              )
            ],
          );
        },
      );
    } else {
      setState(() => widget.item.assets[asset.id] =
          (widget.item.assets[asset.id] ?? 0) + 1);
      widget.onUpdate();
      Navigator.pop(context);
    }
  }

  Widget _buildAssetTile(AssetType g) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
                color: Color(0x66000000),
                blurRadius: 10,
                offset: Offset(0, 5))
          ]),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: AssetCoin(type: g, size: 40),
        title: Text(g.name,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        subtitle: Text(
            "Canlı: ${NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0).format(g.sellPrice)}",
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
        trailing: Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
                color: Color(0x26FFD700), shape: BoxShape.circle),
            child: const Icon(Icons.add,
                color: AppTheme.goldMain, size: 22)),
        onTap: () => _addAssetDialog(g),
      ),
    );
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (c) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
            color: AppTheme.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
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
            const Text("KASAYA VARLIK EKLE",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2)),
            const SizedBox(height: 20),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                physics: const BouncingScrollPhysics(),
                children: [
                  // ── Standart varlıklar ──
                  ...widget.market.map((g) => _buildAssetTile(g)),

                  // ── Borsa hisseleri bölümü ──
                  if (widget.borsaMarket.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Divider(color: Colors.white10),
                    const SizedBox(height: 10),
                    Row(children: [
                      Container(
                          width: 3, height: 20, color: AppTheme.goldMain),
                      const SizedBox(width: 8),
                      const Text("BORSA HİSSELERİ",
                          style: TextStyle(
                              color: AppTheme.goldMain,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1)),
                      if (!widget.isPremium) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: Color(0x33FFD700),
                              borderRadius: BorderRadius.circular(4)),
                          child: const Text("PREMIUM",
                              style: TextStyle(
                                  color: AppTheme.goldMain,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 12),
                    if (widget.isPremium)
                      ...widget.borsaMarket
                          .where((g) => g.sellPrice > 0)
                          .map((g) => _buildAssetTile(g))
                    else
                      // Bulanık kilitli önizleme
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          height: 200,
                          child: Stack(children: [
                            Positioned.fill(
                              child: ImageFiltered(
                                imageFilter:
                                    ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                                child: Column(
                                  children: List.generate(
                                      3,
                                      (i) => Container(
                                            margin: const EdgeInsets.only(
                                                bottom: 8),
                                            height: 56,
                                            decoration: BoxDecoration(
                                                color: AppTheme.card,
                                                borderRadius:
                                                    BorderRadius.circular(12)),
                                          )),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(16)),
                                child: const Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.lock_outline,
                                          color: AppTheme.goldMain, size: 32),
                                      SizedBox(height: 8),
                                      Text("Premium Abonelik Gerekli",
                                          style: TextStyle(
                                              color: AppTheme.goldMain,
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteAsset(String assetId) {
    HapticFeedback.heavyImpact();
    setState(() => _deletingAssetId = assetId);
  }

  void _editQuantity(String assetId, double currentQty) {
    TextEditingController qtyCtrl =
        TextEditingController(text: formatNumber(currentQty));
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: const Text("Miktarı Düzenle",
            style: TextStyle(color: Colors.white)),
        content: TextField(
            controller: qtyCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(hintText: "Yeni miktar")),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.goldMain,
                foregroundColor: Colors.black),
            onPressed: () {
              double? val = double.tryParse(qtyCtrl.text.replaceAll(',', '.'));
              if (val != null) {
                setState(() => widget.item.assets[assetId] = val);
                widget.onUpdate();
              }
              Navigator.pop(c);
            },
            child: const Text("KAYDET"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allMarket = [...widget.market, ...widget.borsaMarket];
    final marketMap = {for (var a in allMarket) a.id: a};
    double total = widget.item.getTotalValue(allMarket);

    return Scaffold(
      appBar:
          widget.isWallet ? null : AppBar(title: Text(widget.item.personName)),
      body: RefreshIndicator(
        color: AppTheme.goldMain,
        backgroundColor: AppTheme.card,
        onRefresh: widget.onRefresh,
        child: Column(
          children: [
            if (widget.isWallet) const SizedBox(height: 10),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [AppTheme.goldMain, AppTheme.goldDim]),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0x66FFA000),
                        blurRadius: 20)
                  ]),
              child: Column(children: [
                Text(widget.isWallet ? "MEVCUT VARLIK" : "GÜNCEL DEĞER",
                    style: const TextStyle(
                        color: Colors.black54, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text(_currency.format(total),
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 36,
                        fontWeight: FontWeight.w900))
              ]),
            ),
            Expanded(
              child: ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: widget.item.assets.length,
                itemBuilder: (c, i) {
                  String id = widget.item.assets.keys.elementAt(i);
                  double qty = widget.item.assets[id]!;
                  var asset = marketMap[id] ??
                      AssetType("0", [], "?", "?", 0.0, 0.0, "gold");
                  // Kasa: kuyumcu alış (sende varsa satarsın), Borç/Alacak: kuyumcu satış
                  double itemPrice =
                      widget.isWallet ? asset.buyPrice : asset.sellPrice;

                  bool isDeleting = _deletingAssetId == id;

                  Widget assetTile = GestureDetector(
                    onLongPress: () => _confirmDeleteAsset(id),
                    onTap: () {
                      if (isDeleting) {
                        setState(() => _deletingAssetId = null);
                      }
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14),
                          decoration: BoxDecoration(
                              color: AppTheme.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: const Color(0x0AFFFFFF))),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () => widget.onAssetTap(asset),
                                child: Row(children: [
                                  AssetCoin(type: asset),
                                  const SizedBox(width: 15),
                                  Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(asset.name,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 3),
                                        Text(
                                            _currency.format(qty * itemPrice),
                                            style: TextStyle(
                                                color: widget.isWallet
                                                    ? Colors.grey
                                                    : (widget.item.isCredit
                                                        ? const Color(0xFF66BB6A)
                                                        : const Color(0xFFEF5350)),
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500)),
                                      ])
                                ]),
                              ),
                              const Spacer(),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                      constraints: const BoxConstraints(),
                                      padding: EdgeInsets.zero,
                                      iconSize: 20,
                                      icon: const Icon(
                                          Icons.remove_circle_outline,
                                          color: AppTheme.neonRed),
                                      onPressed: () {
                                        setState(() {
                                          if (qty > 1) {
                                            widget.item.assets[id] = qty - 1;
                                          } else {
                                            widget.item.assets.remove(id);
                                          }
                                        });
                                        widget.onUpdate();
                                      }),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                      onTap: () => _editQuantity(id, qty),
                                      child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                              color: Colors.black45,
                                              borderRadius:
                                                  BorderRadius.circular(6)),
                                          child: Text(formatNumber(qty),
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight:
                                                      FontWeight.bold)))),
                                  const SizedBox(width: 8),
                                  IconButton(
                                      constraints: const BoxConstraints(),
                                      padding: EdgeInsets.zero,
                                      iconSize: 20,
                                      icon: const Icon(
                                          Icons.add_circle_outline,
                                          color: AppTheme.neonGreen),
                                      onPressed: () {
                                        setState(() {
                                          widget.item.assets[id] = qty + 1;
                                        });
                                        widget.onUpdate();
                                      }),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (isDeleting)
                          Positioned(
                              top: -8,
                              right: -5,
                              child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _deletingAssetId = null;
                                      widget.item.assets.remove(id);
                                    });
                                    widget.onUpdate();
                                  },
                                  child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                          color: AppTheme.neonRed,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: Colors.white, width: 2)),
                                      child: const Icon(Icons.delete_forever,
                                          color: Colors.white, size: 18)))),
                      ],
                    ),
                  );

                  // Kasa (wallet) PageView içinde: sadece long-press ile sil
                  // Alacak/Borç detayı: swipe da kalsın
                  if (widget.isWallet) {
                    return assetTile;
                  }
                  return Dismissible(
                    key: Key(id),
                    direction: DismissDirection.startToEnd,
                    background: Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(left: 20),
                        decoration: BoxDecoration(
                            color: AppTheme.neonRed,
                            borderRadius: BorderRadius.circular(12)),
                        child:
                            const Icon(Icons.delete, color: Colors.white)),
                    onDismissed: (d) {
                      setState(() => widget.item.assets.remove(id));
                      widget.onUpdate();
                    },
                    child: assetTile,
                  );
                },
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
          backgroundColor: AppTheme.card,
          onPressed: _showAddMenu,
          child: const Icon(Icons.add, color: AppTheme.goldMain)),
    );
  }
}
