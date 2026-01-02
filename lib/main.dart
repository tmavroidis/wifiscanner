
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]).then((_) {
    runApp(const MyApp());
  });
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
      debugShowCheckedModeBanner: false,
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
  bool _isListVisible = false;

  // State for the new device list
  final Map<String, WiFiAccessPoint> _listedDevices = {};
  final Map<String, DateTime> _firstSeenTimestamps = {};
  Timer? _colorUpdateTimer;

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

      // Timer to update the colors of the device list
      _colorUpdateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (mounted) {
          setState(() {});
        }
      });
    } else if (kIsWeb) {
      _animationController = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 5),
      )..repeat();
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
    _colorUpdateTimer?.cancel();
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
        final currentBssids = results.map((ap) => ap.bssid).toSet();
        for (final ap in results) {
          if (!_listedDevices.containsKey(ap.bssid)) {
            _showNewDevicePopup(ap);
          }
        }
        setState(() {
          _accessPoints = results;

          // Remove devices from our list that are no longer visible
          _listedDevices.removeWhere((bssid, _) => !currentBssids.contains(bssid));
          _firstSeenTimestamps.removeWhere((bssid, _) => !currentBssids.contains(bssid));

          // Add new devices to our list
          for (final ap in results) {
            if (!_listedDevices.containsKey(ap.bssid)) {
              _listedDevices[ap.bssid] = ap;
              _firstSeenTimestamps[ap.bssid] = DateTime.now();
            }
          }
        });
      }
    });
  }

  void _showNewDevicePopup(WiFiAccessPoint ap) {
    // Close any existing dialog first
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    showDialog(
      context: context,
      builder: (context) {
        // Automatically close the dialog after 15 seconds
        Timer(const Duration(seconds: 15), () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });

        return AlertDialog(
          title: const Text('New Signal Detected'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("SSID: ${ap.ssid.isNotEmpty ? ap.ssid : 'N/A'}"),
              Text("BSSID: ${ap.bssid}"),
              Text("Strength: ${ap.level} dBm"),
              Text("Manufacturer: ${_getManufacturer(ap.bssid)}"),
              Text("Frequency: ${ap.frequency} MHz"),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
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

  Color _getDeviceColor(DateTime discoveryTime) {
    final duration = DateTime.now().difference(discoveryTime);
    if (duration.inMinutes < 1) {
      return Colors.red;
    } else if (duration.inMinutes < 2) {
      return Colors.yellow;
    } else {
      return Colors.green;
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
                const SizedBox(width: 8),
                const Text("List"),
                Switch(
                  value: _isListVisible,
                  onChanged: (value) {
                    setState(() {
                      _isListVisible = value;
                    });
                  },
                ),
              ],
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'about') {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => const AboutPage(),
                ));
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'about',
                child: Text('About'),
              ),
            ],
          ),
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
          : Row(
              children: [
                if (_isListVisible)
                  Container(
                    width: 200,
                    decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey[800]!))),
                    child: ListView.builder(
                      itemCount: _listedDevices.length,
                      itemBuilder: (context, index) {
                        final bssid = _listedDevices.keys.elementAt(index);
                        final ap = _listedDevices[bssid]!;
                        final discoveryTime = _firstSeenTimestamps[bssid]!;
                        final color = _getDeviceColor(discoveryTime);
                        String label = ap.ssid.isNotEmpty ? ap.ssid : ap.bssid;
                        return InkWell(
                          onTap: () {
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (context) => SignalLocatorPage(accessPoint: ap),
                            ));
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                            child: Text(
                              label,
                              style: TextStyle(color: color),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                Expanded(
                  child: Column(
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
                ),
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

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
      ),
      body: const Padding(
        padding: EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'WiFi Scanner',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 24),
            Text('Released under a GPL-3.0 licence:'),
            SizedBox(height: 8),
            SelectableText(
              'https://github.com/tmavroidis/wifiscanner?tab=GPL-3.0-1-ov-file#',
              style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
            ),
            SizedBox(height: 24),
            Text('Source available at:'),
            SizedBox(height: 8),
            SelectableText(
              'https://github.com/tmavroidis/wifiscanner/tree/master',
              style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
            ),
          ],
        ),
      ),
    );
  }
}
