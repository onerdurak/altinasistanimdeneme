import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../modeller.dart';

class InteractiveChart extends StatefulWidget {
  final List<Map<String, dynamic>> data;
  final Color color;
  final NumberFormat formatter;

  const InteractiveChart(
      {super.key,
      required this.data,
      required this.color,
      required this.formatter});

  @override
  State<InteractiveChart> createState() => _InteractiveChartState();
}

class _InteractiveChartState extends State<InteractiveChart> {
  int? touchedIndex;

  void _updateTouch(double dx, double width) {
    if (widget.data.isEmpty) return;
    double stepX =
        width / (widget.data.length > 1 ? widget.data.length - 1 : 1);
    int index = (dx / stepX).round();
    index = index.clamp(0, widget.data.length - 1);
    if (touchedIndex != index) {
      setState(() => touchedIndex = index);
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return GestureDetector(
        onPanStart: (d) =>
            _updateTouch(d.localPosition.dx, constraints.maxWidth),
        onPanUpdate: (d) =>
            _updateTouch(d.localPosition.dx, constraints.maxWidth),
        onTapDown: (d) =>
            _updateTouch(d.localPosition.dx, constraints.maxWidth),
        onPanEnd: (_) => setState(() => touchedIndex = null),
        onTapUp: (_) => setState(() => touchedIndex = null),
        child: CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: NodeChartPainter(
              data: widget.data,
              color: widget.color,
              formatter: widget.formatter,
              touchedIndex: touchedIndex),
        ),
      );
    });
  }
}

class NodeChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final Color color;
  final NumberFormat formatter;
  final int? touchedIndex;

  NodeChartPainter(
      {required this.data,
      required this.color,
      required this.formatter,
      this.touchedIndex});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    double bottomMargin = 25.0;
    double chartHeight = size.height - bottomMargin;
    List<double> values = data.map((e) => e['val'] as double).toList();
    double minVal = values.reduce(min);
    double maxVal = values.reduce(max);

    double diff = maxVal - minVal;
    if (diff == 0) diff = 1;
    minVal = minVal - (diff * 0.15);
    maxVal = maxVal + (diff * 0.15);
    diff = maxVal - minVal;

    double stepX = size.width / (values.length > 1 ? values.length - 1 : 1);

    // Kılavuz çizgileri
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;
    for (int i = 0; i < 4; i++) {
      double y = chartHeight * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Ana çizgi ve yansıma (Glow)
    final path = Path();
    if (values.length > 1) {
      path.moveTo(
          0, chartHeight - (((values[0] - minVal) / diff) * chartHeight));
      for (int i = 0; i < values.length - 1; i++) {
        double x1 = i * stepX;
        double y1 = chartHeight - (((values[i] - minVal) / diff) * chartHeight);
        double x2 = (i + 1) * stepX;
        double y2 =
            chartHeight - (((values[i + 1] - minVal) / diff) * chartHeight);
        path.cubicTo(x1 + (x2 - x1) / 2, y1, x1 + (x2 - x1) / 2, y2, x2, y2);
      }
    } else {
      path.moveTo(
          0, chartHeight - (((values[0] - minVal) / diff) * chartHeight));
      path.lineTo(size.width,
          chartHeight - (((values[0] - minVal) / diff) * chartHeight));
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final shadowPath = Path.from(path)
      ..lineTo(size.width, chartHeight)
      ..lineTo(0, chartHeight)
      ..close();
    final shadowPaint = Paint()
      ..shader = LinearGradient(
              colors: [color.withOpacity(0.3), color.withOpacity(0.0)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter)
          .createShader(Rect.fromLTWH(0, 0, size.width, chartHeight))
      ..style = PaintingStyle.fill;

    canvas.drawPath(shadowPath, shadowPaint);
    canvas.drawPath(path, linePaint);

    // DÜĞÜMLER (NODES)
    final nodeFill = Paint()
      ..color = AppTheme.bg
      ..style = PaintingStyle.fill;
    final nodeBorder = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < values.length; i++) {
      if (touchedIndex == i) continue;
      double x = i * stepX;
      double y = chartHeight - (((values[i] - minVal) / diff) * chartHeight);
      canvas.drawCircle(Offset(x, y), 3, nodeFill);
      canvas.drawCircle(Offset(x, y), 3, nodeBorder);
    }

    // ALTA YAZILACAK TARİHLER (Seyrek)
    int labelCount = min(5, data.length);
    for (int i = 0; i < labelCount; i++) {
      int index =
          (data.length - 1) * i ~/ (labelCount > 1 ? labelCount - 1 : 1);
      String label = data[index]['label'];
      double x = index * stepX;
      final textSpan = TextSpan(
          text: label,
          style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.bold));
      final textPainter =
          TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      textPainter.layout();
      double textX = x - (textPainter.width / 2);
      if (textX < 0) textX = 0;
      if (textX + textPainter.width > size.width)
        textX = size.width - textPainter.width;
      textPainter.paint(canvas, Offset(textX, chartHeight + 10));
    }

    // SEÇİLEN DÜĞÜM (TOOLTIP)
    if (touchedIndex != null && touchedIndex! < data.length) {
      double tX = touchedIndex! * stepX;
      double tY = chartHeight -
          (((values[touchedIndex!] - minVal) / diff) * chartHeight);

      canvas.drawLine(
          Offset(tX, 0),
          Offset(tX, chartHeight),
          Paint()
            ..color = Colors.white24
            ..strokeWidth = 1.0
            ..style = PaintingStyle.stroke);
      canvas.drawCircle(Offset(tX, tY), 5, Paint()..color = color);
      canvas.drawCircle(Offset(tX, tY), 2, nodeFill);

      String priceText = formatter.format(values[touchedIndex!]);
      String dateText = data[touchedIndex!]['dateStr'];

      final tp = TextPainter(
        text: TextSpan(children: [
          TextSpan(
              text: "$dateText\n",
              style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  height: 1.5)),
          TextSpan(
              text: priceText,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900)),
        ]),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      tp.layout();
      double boxWidth = tp.width + 20;
      double boxHeight = tp.height + 12;
      double boxX = tX - (boxWidth / 2);
      double boxY = tY - boxHeight - 15;

      if (boxX < 0) boxX = 0;
      if (boxX + boxWidth > size.width) boxX = size.width - boxWidth;
      if (boxY < 0) boxY = tY + 20;

      final RRect tooltipRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(boxX, boxY, boxWidth, boxHeight),
          const Radius.circular(8));
      canvas.drawRRect(tooltipRect, Paint()..color = AppTheme.card);
      canvas.drawRRect(
          tooltipRect,
          Paint()
            ..color = Colors.white12
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke);
      tp.paint(canvas, Offset(boxX + 10, boxY + 6));
    }
  }

  @override
  bool shouldRepaint(covariant NodeChartPainter oldDelegate) {
    return oldDelegate.touchedIndex != touchedIndex || oldDelegate.data != data;
  }
}

class InteractiveHistoryChart extends StatefulWidget {
  final List<Map<String, dynamic>> data;
  final String dataKey;
  final Color color;
  final NumberFormat formatter;
  const InteractiveHistoryChart(
      {super.key,
      required this.data,
      required this.dataKey,
      required this.color,
      required this.formatter});

  @override
  State<InteractiveHistoryChart> createState() =>
      _InteractiveHistoryChartState();
}

class _InteractiveHistoryChartState extends State<InteractiveHistoryChart> {
  int? touchedIndex;

  void _updateTouch(double dx, double width) {
    if (widget.data.isEmpty) return;
    double stepX =
        width / (widget.data.length > 1 ? widget.data.length - 1 : 1);
    int index = (dx / stepX).round();
    index = index.clamp(0, widget.data.length - 1);
    if (touchedIndex != index) {
      setState(() => touchedIndex = index);
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return GestureDetector(
        onPanStart: (d) =>
            _updateTouch(d.localPosition.dx, constraints.maxWidth),
        onPanUpdate: (d) =>
            _updateTouch(d.localPosition.dx, constraints.maxWidth),
        onTapDown: (d) =>
            _updateTouch(d.localPosition.dx, constraints.maxWidth),
        onPanEnd: (_) => setState(() => touchedIndex = null),
        onTapUp: (_) => setState(() => touchedIndex = null),
        child: CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: HistoryInteractivePainter(
              data: widget.data,
              dataKey: widget.dataKey,
              color: widget.color,
              formatter: widget.formatter,
              touchedIndex: touchedIndex),
        ),
      );
    });
  }
}

class HistoryInteractivePainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final String dataKey;
  final Color color;
  final NumberFormat formatter;
  final int? touchedIndex;

  HistoryInteractivePainter(
      {required this.data,
      required this.dataKey,
      required this.color,
      required this.formatter,
      this.touchedIndex});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    double bottomMargin = 25.0;
    double chartHeight = size.height - bottomMargin;

    List<double> values =
        data.map((e) => (e[dataKey] as num).toDouble()).toList();
    double minVal = values.reduce(min);
    double maxVal = values.reduce(max);

    double diff = maxVal - minVal;
    if (diff == 0) diff = 1;
    minVal = minVal - (diff * 0.15);
    maxVal = maxVal + (diff * 0.15);
    diff = maxVal - minVal;

    double stepX = size.width / (values.length > 1 ? values.length - 1 : 1);

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;
    for (int i = 0; i < 4; i++) {
      double y = chartHeight * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final path = Path();

    if (values.length > 1) {
      path.moveTo(
          0, chartHeight - (((values[0] - minVal) / diff) * chartHeight));
      for (int i = 0; i < values.length - 1; i++) {
        double x1 = i * stepX;
        double y1 = chartHeight - (((values[i] - minVal) / diff) * chartHeight);
        double x2 = (i + 1) * stepX;
        double y2 =
            chartHeight - (((values[i + 1] - minVal) / diff) * chartHeight);
        path.cubicTo(x1 + (x2 - x1) / 2, y1, x1 + (x2 - x1) / 2, y2, x2, y2);
      }
    } else {
      path.moveTo(
          0, chartHeight - (((values[0] - minVal) / diff) * chartHeight));
      path.lineTo(size.width,
          chartHeight - (((values[0] - minVal) / diff) * chartHeight));
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final shadowPath = Path.from(path)
      ..lineTo(size.width, chartHeight)
      ..lineTo(0, chartHeight)
      ..close();
    final shadowPaint = Paint()
      ..shader = LinearGradient(
              colors: [color.withOpacity(0.3), color.withOpacity(0.0)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter)
          .createShader(Rect.fromLTWH(0, 0, size.width, chartHeight))
      ..style = PaintingStyle.fill;

    canvas.drawPath(shadowPath, shadowPaint);
    canvas.drawPath(path, linePaint);

    final nodeFill = Paint()
      ..color = AppTheme.bg
      ..style = PaintingStyle.fill;
    final nodeBorder = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < values.length; i++) {
      if (touchedIndex == i) continue;
      double x = i * stepX;
      double y = chartHeight - (((values[i] - minVal) / diff) * chartHeight);
      canvas.drawCircle(Offset(x, y), 3, nodeFill);
      canvas.drawCircle(Offset(x, y), 3, nodeBorder);
    }

    int labelCount = min(4, data.length);
    for (int i = 0; i < labelCount; i++) {
      int index =
          (data.length - 1) * i ~/ (labelCount > 1 ? labelCount - 1 : 1);
      String rawDate = data[index]['date'].toString();
      String label = rawDate;
      try {
        DateTime d = DateTime.parse(rawDate);
        label =
            "${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}";
      } catch (e) {}
      final textSpan = TextSpan(
          text: label,
          style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.bold));
      final textPainter =
          TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      textPainter.layout();
      double textX = (index * stepX) - (textPainter.width / 2);
      if (textX < 0) textX = 0;
      if (textX + textPainter.width > size.width)
        textX = size.width - textPainter.width;
      textPainter.paint(canvas, Offset(textX, chartHeight + 10));
    }

    if (touchedIndex != null && touchedIndex! < data.length) {
      double tX = touchedIndex! * stepX;
      double tY = chartHeight -
          (((values[touchedIndex!] - minVal) / diff) * chartHeight);

      canvas.drawLine(
          Offset(tX, 0),
          Offset(tX, chartHeight),
          Paint()
            ..color = Colors.white24
            ..strokeWidth = 1.0
            ..style = PaintingStyle.stroke);
      canvas.drawCircle(Offset(tX, tY), 5, Paint()..color = color);
      canvas.drawCircle(Offset(tX, tY), 2, nodeFill);

      String priceText = formatter.format(values[touchedIndex!]);
      String rawDate = data[touchedIndex!]['date'].toString();
      String dateText = rawDate;
      try {
        DateTime d = DateTime.parse(rawDate);
        dateText =
            "${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}";
      } catch (e) {}

      final tp = TextPainter(
        text: TextSpan(children: [
          TextSpan(
              text: "$dateText\n",
              style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  height: 1.5)),
          TextSpan(
              text: priceText,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900)),
        ]),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      tp.layout();
      double boxWidth = tp.width + 20;
      double boxHeight = tp.height + 12;
      double boxX = tX - (boxWidth / 2);
      double boxY = tY - boxHeight - 15;

      if (boxX < 0) boxX = 0;
      if (boxX + boxWidth > size.width) boxX = size.width - boxWidth;
      if (boxY < 0) boxY = tY + 20;

      final RRect tooltipRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(boxX, boxY, boxWidth, boxHeight),
          const Radius.circular(8));
      canvas.drawRRect(tooltipRect, Paint()..color = AppTheme.card);
      canvas.drawRRect(
          tooltipRect,
          Paint()
            ..color = Colors.white12
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke);
      tp.paint(canvas, Offset(boxX + 10, boxY + 6));
    }
  }

  @override
  bool shouldRepaint(covariant HistoryInteractivePainter oldDelegate) {
    return oldDelegate.touchedIndex != touchedIndex || oldDelegate.data != data;
  }
}
