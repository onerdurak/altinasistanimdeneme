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
  Timer? _uiTimer;

  @override
  void initState() {
    super.initState();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fmtGold =
        NumberFormat.currency(locale: "tr_TR", symbol: "₺", decimalDigits: 0);
    final fmtCurrency =
        NumberFormat.currency(locale: "tr_TR", symbol: "₺", decimalDigits: 2);

    return Scaffold(
        appBar: AppBar(title: const Text("TÜM PİYASA")),
        body: ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            physics: const BouncingScrollPhysics(),
            itemCount: widget.market.length,
            onReorder: widget.onReorder,
            itemBuilder: (c, i) {
              var item = widget.market[i];
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
                priceStr = fmtCurrency.format(item.sellPrice);
                buyStr = fmtCurrency.format(item.buyPrice);
              } else {
                priceStr = fmtGold.format(item.sellPrice);
                buyStr = fmtGold.format(item.buyPrice);
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
                            Text(priceStr,
                                style: const TextStyle(
                                    color: AppTheme.goldMain,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15)),
                            const SizedBox(height: 2),
                            Text("Alış: $buyStr",
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 11))
                          ]),
                      const SizedBox(width: 15),
                      ReorderableDragStartListener(
                          index: i,
                          child: const Icon(Icons.drag_indicator,
                              color: Colors.white24, size: 24)),
                    ],
                  ),
                ),
              );
            }));
  }
}
