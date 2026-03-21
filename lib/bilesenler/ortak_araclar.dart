import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../modeller.dart';

class AssetCoin extends StatelessWidget {
  final AssetType type;
  final double size;
  const AssetCoin({super.key, required this.type, this.size = 28});

  @override
  Widget build(BuildContext context) {
    List<Color> colors;
    Color textColor;
    if (type.category == 'silver') {
      colors = [AppTheme.silverLight, AppTheme.silverDark];
      textColor = Colors.black87;
    } else if (type.category == 'currency') {
      if (type.id == 'usd') {
        colors = [const Color(0xFFB9F6CA), const Color(0xFF00C853)];
      } else if (type.id == 'gbp') {
        colors = [const Color(0xFFE1BEE7), const Color(0xFF8E24AA)];
      } else {
        colors = [const Color(0xFF82B1FF), const Color(0xFF2962FF)];
      }
      textColor = Colors.black87;
    } else if (type.category == 'crypto' || type.category == 'ons') {
      colors = [const Color(0xFFFFCC80), AppTheme.btcColor];
      textColor = Colors.black;
    } else if (type.category == 'bracelet' || type.category == 'gold') {
      colors = [const Color(0xFFFFF59D), const Color(0xFFFBC02D)];
      textColor = Colors.black;
    } else {
      colors = [const Color(0xFFFFECB3), const Color(0xFFFF6F00)];
      textColor = Colors.brown[900]!;
    }
    return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
                colors: colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            boxShadow: [
              BoxShadow(
                  color: colors.last.withOpacity(0.4),
                  blurRadius: 4,
                  offset: const Offset(1, 1))
            ],
            border: Border.all(color: Colors.white.withOpacity(0.4), width: 1)),
        alignment: Alignment.center,
        child: Text(type.label,
            style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w900,
                fontSize: type.label.length > 2 ? size * 0.32 : size * 0.45)));
  }
}

class MiniStat extends StatelessWidget {
  final String label;
  final double val;
  final Color color;
  final bool isObscured;

  const MiniStat(this.label, this.val, this.color,
      {super.key, this.isObscured = false});
  @override
  Widget build(BuildContext context) {
    final f = NumberFormat.compact();
    return Column(children: [
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
      Text(isObscured ? "***" : f.format(val),
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 15))
    ]);
  }
}
