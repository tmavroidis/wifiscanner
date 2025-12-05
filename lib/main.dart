
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

class _WiFiScannerPageState extends State<WiFiScannerPage> {
  List<WiFiAccessPoint> _accessPoints = <WiFiAccessPoint>[];
  StreamSubscription<List<WiFiAccessPoint>>? _subscription;

  @override
  void initState() {
    super.initState();
    _startScan();
    _listenToScannedResults();
  }

  @override
  void dispose() {
    _subscription?.cancel();
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
      body: CustomPaint(
        painter: RadarPainter(_accessPoints),
        child: Container(),
      ),
    );
  }
}

class RadarPainter extends CustomPainter {
  final List<WiFiAccessPoint> accessPoints;

  RadarPainter(this.accessPoints);

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

    for (var ap in accessPoints) {
      // Normalize signal strength to a value between 0 and 1
      final signalStrength = (ap.level + 100).clamp(0, 100) / 100.0;
      final dotRadius = 2 + (signalStrength * 8);

      // Distribute points randomly within the circle
      final random = Random();
      final r = radius * sqrt(random.nextDouble());
      final theta = random.nextDouble() * 2 * pi;
      final x = center.dx + r * cos(theta);
      final y = center.dy + r * sin(theta);
      final dotCenter = Offset(x, y);

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
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
