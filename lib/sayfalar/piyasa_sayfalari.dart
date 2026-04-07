import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../modeller.dart';
import '../bilesenler/ortak_araclar.dart';

class FullMarketPage extends StatefulWidget {
  final List<AssetType> market;
  final Function(AssetType) onAssetTap;
  final Function(int, int) onReorder;

  const FullMarketPage(
      {super.key,
      required this.market,
      required this.onAssetTap,
      required this.onReorder});

  @override
  State<FullMarketPage> createState() => _FullMarketPageState();
}

class _FullMarketPageState extends State<FullMarketPage> {
  static final _fmtGold =
      NumberFormat.currency(locale: "tr_TR", symbol: "₺", decimalDigits: 0);
  static final _fmtCurrency =
      NumberFormat.currency(locale: "tr_TR", symbol: "₺", decimalDigits: 2);

  // Fiyat yönü takibi
  final Map<String, double> _prevPrices = {};
  final Map<String, int> _directions = {};
  final Map<String, Timer> _resetTimers = {};

  @override
  void didUpdateWidget(FullMarketPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final item in widget.market) {
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
    for (final t in _resetTimers.values) {
      t.cancel();
    }
    super.dispose();
  }

  Color _priceColor(int dir) {
    if (dir > 0) return AppTheme.neonGreen;
    if (dir < 0) return AppTheme.neonRed;
    return AppTheme.goldMain;
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
        appBar: AppBar(title: const Text("TÜM PİYASA")),
        body: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.all(16),
            physics: const BouncingScrollPhysics(),
            itemCount: widget.market.length,
            onReorder: widget.onReorder,
            itemBuilder: (c, i) {
              var item = widget.market[i];
              final int dir = _directions[item.id] ?? 0;
              String priceStr;
              String buyStr;

              if (item.category == 'crypto' && item.usdPrice > 0) {
                priceStr = NumberFormat.currency(
                        locale: "en_US",
                        symbol: "\$",
                        decimalDigits: item.usdPrice > 1000 ? 0 : 2)
                    .format(item.usdPrice);
                buyStr = priceStr;
              } else if (item.id == 'ons' && item.usdPrice > 0) {
                priceStr = NumberFormat.currency(
                        locale: "en_US", symbol: "\$", decimalDigits: 2)
                    .format(item.usdPrice);
                buyStr = priceStr;
              } else if (item.category == 'currency') {
                priceStr = _fmtCurrency.format(item.sellPrice);
                buyStr = _fmtCurrency.format(item.buyPrice);
              } else {
                priceStr = _fmtGold.format(item.sellPrice);
                buyStr = _fmtGold.format(item.buyPrice);
              }

              return GestureDetector(
                key: Key(item.id),
                onTap: () => widget.onAssetTap(item),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: AppTheme.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10)),
                  child: Row(
                    children: [
                      AssetCoin(type: item),
                      const SizedBox(width: 15),
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15)),
                          const SizedBox(height: 4),
                          Row(children: [
                            if (item.changeRate > 0)
                              const Icon(Icons.arrow_drop_up,
                                  color: AppTheme.neonGreen, size: 18)
                            else if (item.changeRate < 0)
                              const Icon(Icons.arrow_drop_down,
                                  color: AppTheme.neonRed, size: 18),
                            Text("%${item.changeRate.abs().toStringAsFixed(2)}",
                                style: TextStyle(
                                    color: item.changeRate >= 0
                                        ? AppTheme.neonGreen
                                        : AppTheme.neonRed,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold))
                          ])
                        ],
                      )),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 300),
                                style: TextStyle(
                                    color: _priceColor(dir),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15),
                                child: Text(priceStr)),
                            const SizedBox(height: 2),
                            Text("Alış: $buyStr",
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 11))
                          ]),
                      const SizedBox(width: 15),
                      ReorderableDragStartListener(
                          index: i,
                          child: const Icon(Icons.swap_vert,
                              color: Colors.white38, size: 22)),
                    ],
                  ),
                ),
              );
            }));
  }
}
