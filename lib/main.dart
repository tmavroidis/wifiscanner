
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:wifi_scan/wifi_scan.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WiFi Scanner',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      darkTheme: ThemeData.dark(),
      themeMode: ThemeMode.dark,
      home: const WiFiScannerPage(),
    );
  }
}

class WiFiScannerPage extends StatefulWidget {
  const WiFiScannerPage({super.key});

  @override
  State<WiFiScannerPage> createState() => _WiFiScannerPageState();
}

class _WiFiScannerPageState extends State<WiFiScannerPage> with SingleTickerProviderStateMixin {
  List<WiFiAccessPoint> _accessPoints = <WiFiAccessPoint>[];
  StreamSubscription<List<WiFiAccessPoint>>? _subscription;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
    _startScan();
    _listenToScannedResults();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _startScan() async {
    final canScan = await WiFiScan.instance.canStartScan(askPermissions: true);
    if (canScan != CanStartScan.yes) {
      return;
    }
    await WiFiScan.instance.startScan();
  }

  void _listenToScannedResults() async {
    final canGetResults = await WiFiScan.instance.canGetScannedResults(askPermissions: true);
    if (canGetResults != CanGetScannedResults.yes) {
      return;
    }
    _subscription = WiFiScan.instance.onScannedResultsAvailable.listen((results) {
      if (mounted) {
        setState(() {
          _accessPoints = results;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi Scanner'),
      ),
      body: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return CustomPaint(
            painter: RadarPainter(_accessPoints, _animationController.value),
            child: Container(),
          );
        },
      ),
    );
  }
}

class RadarPainter extends CustomPainter {
  final List<WiFiAccessPoint> accessPoints;
  final double rotation;

  RadarPainter(this.accessPoints, this.rotation);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;

    final paint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(center, radius * 0.75, paint);
    canvas.drawCircle(center, radius * 0.5, paint);
    canvas.drawCircle(center, radius * 0.25, paint);

    final rotationAngle = rotation * 2 * pi;
    final armPaint = Paint()
      ..color = Colors.blue.withOpacity(0.5)
      ..style = PaintingStyle.fill;
    canvas.drawPath(
      Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(Rect.fromCircle(center: center, radius: radius), rotationAngle - pi / 4, pi / 4, false)
        ..close(),
      armPaint,
    );

    for (var ap in accessPoints) {
      // Normalize signal strength to a value between 0 and 1
      final signalStrength = (ap.level + 100).clamp(0, 100) / 100.0;
      final baseDotRadius = 2 + (signalStrength * 8);

      // Distribute points randomly within the circle
      final random = Random(ap.bssid.hashCode);
      final r = radius * sqrt(random.nextDouble());
      final theta = random.nextDouble() * 2 * pi;
      final x = center.dx + r * cos(theta);
      final y = center.dy + r * sin(theta);
      final dotCenter = Offset(x, y);

      double angleDiff = (theta - rotationAngle) % (2 * pi);
      if (angleDiff < 0) angleDiff += 2 * pi;

      double expansion = 0;
      if (angleDiff > 0 && angleDiff < pi / 4) {
        expansion = sin(angleDiff * 4) * 3;
      }

      final dotRadius = baseDotRadius + expansion;

      final dotPaint = Paint()..color = Colors.red;
      canvas.drawCircle(dotCenter, dotRadius, dotPaint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: ap.ssid,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, dotCenter + Offset(-textPainter.width / 2, -dotRadius - 12));
    }
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) {
    return accessPoints != oldDelegate.accessPoints || rotation != oldDelegate.rotation;
  }
}
