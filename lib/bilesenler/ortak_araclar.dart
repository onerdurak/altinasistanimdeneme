import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../modeller.dart';

/// Altın kategorileri klasik stil, diğerleri yeni şık stil.
class AssetCoin extends StatelessWidget {
  final AssetType type;
  final double size;
  const AssetCoin({super.key, required this.type, this.size = 28});

  bool get _useClassic =>
      type.category == 'gold' ||
      type.category == 'bracelet' ||
      type.category == 'ons';

  @override
  Widget build(BuildContext context) {
    if (_useClassic) return _buildClassic();
    return _buildModern();
  }

  Widget _buildClassic() {
    final colors = (type.category == 'ons')
        ? [const Color(0xFFFFCC80), AppTheme.btcColor]
        : [const Color(0xFFFFF59D), const Color(0xFFFBC02D)];
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
            border:
                Border.all(color: Colors.white.withOpacity(0.4), width: 1)),
        alignment: Alignment.center,
        child: Text(type.label,
            style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize:
                    type.label.length > 2 ? size * 0.32 : size * 0.45)));
  }

  Widget _buildModern() {
    final config = _iconConfig(type);
    return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
                colors: [config.inner, config.outer],
                center: const Alignment(-0.3, -0.3),
                radius: 1.2),
            boxShadow: [
              BoxShadow(
                  color: config.outer.withOpacity(0.45),
                  blurRadius: 6,
                  spreadRadius: 0.5,
                  offset: const Offset(1, 2)),
              BoxShadow(
                  color: config.inner.withOpacity(0.25),
                  blurRadius: 10,
                  spreadRadius: -1,
                  offset: const Offset(-1, -1)),
            ],
            border: Border.all(
                color: Colors.white.withOpacity(0.35), width: 0.8)),
        alignment: Alignment.center,
        child: Text(config.symbol,
            style: TextStyle(
                color: config.textColor,
                fontWeight: FontWeight.w900,
                fontSize: config.symbol.length > 2
                    ? size * 0.30
                    : size * 0.42,
                letterSpacing: -0.5,
                shadows: [
                  Shadow(
                      color: config.outer.withOpacity(0.3),
                      blurRadius: 2,
                      offset: const Offset(0, 1))
                ])));
  }

  static _CoinStyle _iconConfig(AssetType type) {
    switch (type.category) {
      case 'silver':
        return _CoinStyle(
            const Color(0xFF90A4AE), const Color(0xFF37474F),
            Colors.white, type.label);
      case 'currency':
        if (type.id == 'usd') {
          return _CoinStyle(
              const Color(0xFF43A047), const Color(0xFF1B5E20),
              Colors.white, '\$');
        } else if (type.id == 'gbp') {
          return _CoinStyle(
              const Color(0xFF8E24AA), const Color(0xFF4A148C),
              Colors.white, '£');
        }
        return _CoinStyle(
            const Color(0xFF1E88E5), const Color(0xFF0D47A1),
            Colors.white, '€');
      case 'crypto':
        if (type.id == 'btc') {
          return _CoinStyle(
              const Color(0xFFF7931A), const Color(0xFFB5690A),
              Colors.white, '₿');
        }
        return _CoinStyle(
            const Color(0xFF546E7A), const Color(0xFF263238),
            Colors.white, 'Ξ');
      default:
        return _CoinStyle(
            const Color(0xFFE65100), const Color(0xFF8B3000),
            Colors.white, type.label);
    }
  }
}

class _CoinStyle {
  final Color inner;
  final Color outer;
  final Color textColor;
  final String symbol;
  const _CoinStyle(this.inner, this.outer, this.textColor, this.symbol);
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
