
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wifi_scan/wifi_scan.dart';

/// A small lookup table for Organizationally Unique Identifiers (OUIs) to manufacturer names.
/// This is not an exhaustive list.
const Map<String, String> _ouiToManufacturer = {
  // Google
  '00:1a:11': 'Google',
  '3c:5a:b4': 'Google',
  'f8:8f:ca': 'Google',
  // TP-Link
  '14:cf:92': 'TP-Link',
  'c0:4a:00': 'TP-Link',
  // Netgear
  '00:0f:b5': 'Netgear',
  '08:02:8e': 'Netgear',
  // ASUS
  '08:60:6e': 'ASUS',
  'bc:ee:7b': 'ASUS',
  // Ubiquiti
  '04:18:d6': 'Ubiquiti',
  '24:a4:3c': 'Ubiquiti',
  'fc:ec:da': 'Ubiquiti',
  // Cisco Meraki
  '88:15:44': 'Meraki',
  'e0:55:3d': 'Meraki',
  // Cisco
  '00:40:96': 'Cisco',
  // Apple
  '70:ca:9b': 'Apple',
  '88:6b:6e': 'Apple',
  'a8:86:dd': 'Apple',
  // Samsung
  '00:16:32': 'Samsung',
  '00:1d:c9': 'Samsung',
  // Intel
  '00:1c:c0': 'Intel',
  '9c:d2:1e': 'Intel',
  // Linksys
  '00:25:9c': 'Linksys',
  'c8:d7:19': 'Linksys',
};

String _getManufacturer(String bssid) {
  if (bssid.length >= 8) {
    final oui = bssid.substring(0, 8).toLowerCase();
    return _ouiToManufacturer[oui] ?? 'Unknown';
  }
  return 'Unknown';
}

String _getSignalStrengthDescription(int level) {
  if (level >= -60) {
    return 'Excellent';
  }
  if (level >= -70) {
    return 'Good';
  }
  if (level >= -80) {
    return 'Fair';
  }
  return 'Poor';
}

Color _getSignalStrengthColor(int level) {
  if (level >= -70) {
    return Colors.green;
  }
  if (level >= -80) {
    return Colors.yellow;
  }
  return Colors.red;
}

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
  final TransformationController _transformationController = TransformationController();
  double _sensitivityValue = -100.0;
  bool _isRotationPaused = false;
  bool _isUnsupportedPlatform = false;

  @override
  void initState() {
    super.initState();
    final platform = defaultTargetPlatform;
    if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) {
      _animationController = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 5),
      )..repeat();
      _startScan();
      _listenToScannedResults();
    } else {
      _isUnsupportedPlatform = true;
      _animationController = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 5),
      ); // Initialized but not started
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _animationController.dispose();
    _transformationController.dispose();
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

  void _handleTap(Offset tapPosition, Size size, List<WiFiAccessPoint> accessPoints) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;

    for (final ap in accessPoints) {
      final signalStrength = (ap.level + 100).clamp(0, 100) / 100.0;
      final baseDotRadius = 2 + (signalStrength * 8);

      final random = Random(ap.bssid.hashCode);
      final r = radius * sqrt(random.nextDouble());
      final theta = random.nextDouble() * 2 * pi;
      final x = center.dx + r * cos(theta);
      final y = center.dy + r * sin(theta);
      final dotCenter = Offset(x, y);

      final rotationAngle = _animationController.value * 2 * pi;
      
      double angleDiff = (rotationAngle - theta) % (2 * pi);
      if (angleDiff < 0) angleDiff += 2 * pi;

      double expansion = 0;
      const armWidth = pi / 4;
      if (angleDiff > armWidth && angleDiff < 2 * armWidth) {
        final normalizedAngle = (angleDiff - armWidth) / armWidth * pi;
        expansion = sin(normalizedAngle) * 3;
      }
      final dotRadius = baseDotRadius + expansion;

      if ((tapPosition - dotCenter).distance <= dotRadius) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => SignalLocatorPage(accessPoint: ap),
        ));
        return; 
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi Scanner'),
        actions: [
          if (!_isUnsupportedPlatform)
            Row(
              children: [
                const Text("Scan"),
                Switch(
                  value: !_isRotationPaused,
                  onChanged: (value) {
                    setState(() {
                      _isRotationPaused = !value;
                      if (_isRotationPaused) {
                        _animationController.stop();
                      } else {
                        _animationController.repeat();
                      }
                    });
                  },
                ),
                const SizedBox(width: 16),
              ],
            )
        ],
      ),
      body: _isUnsupportedPlatform
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  'WiFi scanning is only available on Android and iOS devices.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18),
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(constraints.maxWidth, constraints.maxHeight);
                      final filteredAccessPoints = _accessPoints.where((ap) => ap.level >= _sensitivityValue).toList();
                      return GestureDetector(
                        onTapUp: (details) {
                          final sceneOffset = _transformationController.toScene(details.localPosition);
                          _handleTap(sceneOffset, size, filteredAccessPoints);
                        },
                        child: InteractiveViewer(
                          transformationController: _transformationController,
                          minScale: 0.5,
                          maxScale: 4.0,
                          child: AnimatedBuilder(
                            animation: _animationController,
                            builder: (context, child) {
                              return CustomPaint(
                                size: size,
                                painter: RadarPainter(filteredAccessPoints, _animationController.value, isPaused: _isRotationPaused),
                                child: Container(),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Filter by Signal Strength: ${_sensitivityValue.toInt()} dBm'),
                      Slider(
                        value: _sensitivityValue,
                        min: -100,
                        max: -30,
                        divisions: 70,
                        label: '${_sensitivityValue.toInt()} dBm',
                        onChanged: (value) {
                          setState(() {
                            _sensitivityValue = value;
                          });
                        },
                      ),
                    ],
                  ),
                )
              ],
            ),
    );
  }
}

class RadarPainter extends CustomPainter {
  final List<WiFiAccessPoint> accessPoints;
  final double rotation;
  final bool isPaused;

  RadarPainter(this.accessPoints, this.rotation, {this.isPaused = false});

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
    
    if (!isPaused) {
      canvas.drawPath(
        Path()
          ..moveTo(center.dx, center.dy)
          ..arcTo(Rect.fromCircle(center: center, radius: radius), rotationAngle - pi / 4, pi / 4, false)
          ..close(),
        armPaint,
      );
    }

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

      double angleDiff = (rotationAngle - theta) % (2 * pi);
      if (angleDiff < 0) angleDiff += 2 * pi;

      double expansion = 0;
      if (!isPaused) {
        const armWidth = pi / 4;
        if (angleDiff > armWidth && angleDiff < 2 * armWidth) {
          final normalizedAngle = (angleDiff - armWidth) / armWidth * pi;
          expansion = sin(normalizedAngle) * 3;
        }
      }

      final dotRadius = baseDotRadius + expansion;

      final dotPaint = Paint()..color = _getSignalStrengthColor(ap.level);
      canvas.drawCircle(dotCenter, dotRadius, dotPaint);

      String label = ap.ssid;
      if (label.isEmpty) {
        final manufacturer = _getManufacturer(ap.bssid);
        label = manufacturer != 'Unknown' ? manufacturer : ap.bssid;
      }

      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
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
    return accessPoints != oldDelegate.accessPoints || rotation != oldDelegate.rotation || isPaused != oldDelegate.isPaused;
  }
}

class SignalLocatorPage extends StatefulWidget {
  final WiFiAccessPoint accessPoint;
  const SignalLocatorPage({super.key, required this.accessPoint});

  @override
  State<SignalLocatorPage> createState() => _SignalLocatorPageState();
}

class _SignalLocatorPageState extends State<SignalLocatorPage> {
  late WiFiAccessPoint _accessPoint;
  StreamSubscription<List<WiFiAccessPoint>>? _subscription;
  Timer? _scanTimer;

  @override
  void initState() {
    super.initState();
    _accessPoint = widget.accessPoint;
    _startPeriodicScan();
    _listenForUpdates();
  }

  void _startPeriodicScan() {
    _scanTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      final canScan = await WiFiScan.instance.canStartScan(askPermissions: false);
      if (canScan != CanStartScan.yes) {
        return;
      }
      await WiFiScan.instance.startScan();
    });
  }

  void _listenForUpdates() {
    _subscription = WiFiScan.instance.onScannedResultsAvailable.listen(
      (results) {
        try {
          final updatedAp = results.firstWhere((ap) => ap.bssid == _accessPoint.bssid);
          if (mounted) {
            setState(() {
              _accessPoint = updatedAp;
            });
          }
        } catch (e) {
          // AP is no longer in range, do nothing and keep last known value
        }
      },
    );
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_accessPoint.ssid.isNotEmpty ? _accessPoint.ssid : _accessPoint.bssid),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                child: CustomPaint(
                  painter: SignalLocatorPainter(level: _accessPoint.level),
                  child: const Center(),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Column(
                        children: [
                          Text(
                            '${_accessPoint.level} dBm',
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _getSignalStrengthDescription(_accessPoint.level),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text("BSSID: ${_accessPoint.bssid}"),
                    Text("Manufacturer: ${_getManufacturer(_accessPoint.bssid)}"),
                    Text("Frequency: ${_accessPoint.frequency} MHz"),
                    Text("Channel Width: ${_accessPoint.channelWidth?.toString() ?? 'N/A'}"),
                    Text("Standard: ${_accessPoint.standard.toString().split('.').last}"),
                    Text("Timestamp: ${DateTime.fromMillisecondsSinceEpoch(_accessPoint.timestamp!)}"),
                    if (_accessPoint.isPasspoint ?? false) const Text("Passpoint: Yes"),
                    if (_accessPoint.is80211mcResponder ?? false) const Text("802.11mc Responder: Yes"),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SignalLocatorPainter extends CustomPainter {
  final int level;

  SignalLocatorPainter({required this.level});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = min(size.width, size.height) / 2.5;

    final backgroundPaint = Paint()
      ..color = Colors.blue.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, maxRadius, backgroundPaint);
    canvas.drawCircle(center, maxRadius * 0.75, backgroundPaint);
    canvas.drawCircle(center, maxRadius * 0.5, backgroundPaint);
    canvas.drawCircle(center, maxRadius * 0.25, backgroundPaint);

    // Normalize level from -100 to -30 dBm
    final normalizedLevel = (level.clamp(-100, -30) + 100) / 70.0;

    // Radius shrinks as signal gets stronger (normalizedLevel -> 1.0)
    final radius = (1.0 - normalizedLevel) * maxRadius;
    final strokeWidth = 10 + (normalizedLevel * 40);

    final signalPaint = Paint()
      ..color = Color.lerp(Colors.red, Colors.green, normalizedLevel)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, signalPaint);
  }

  @override
  bool shouldRepaint(covariant SignalLocatorPainter oldDelegate) {
    return oldDelegate.level != level;
  }
}
