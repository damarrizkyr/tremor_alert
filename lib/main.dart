import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'services/nearby_service.dart';
import 'services/permission_service.dart';
import 'services/supabase_service.dart';
import 'services/tremor_sensor_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inisialisasi Supabase (dapat diisi dengan kredensial Anda)
  await SupabaseService.initialize();

  runApp(const TremorAlertApp());
}

class TremorAlertApp extends StatelessWidget {
  const TremorAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tremor Alert',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.dark,
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final TremorSensorService _sensorService;
  late final NearbyService _nearbyService;

  bool _hasPermissions = false;
  Position? _currentPosition;
  final List<String> _alertLogs = [];

  @override
  void initState() {
    super.initState();

    // 1. Inisialisasi Nearby Service
    final deviceId = Platform.isAndroid ? 'Android-${DateTime.now().millisecond}' : 'Device';
    _nearbyService = NearbyService(
      deviceName: deviceId,
      onAlertReceived: _handleIncomingNearbyAlert,
    );

    // 2. Inisialisasi Sensor Guncangan
    _sensorService = TremorSensorService(
      tremorThreshold: 14.0,
      onTremorDetected: _handleTremorDetected,
    );
    _sensorService.startListening();

    // 3. Cek Izin Awal
    _checkInitialPermissions();
  }

  Future<void> _checkInitialPermissions() async {
    final granted = await PermissionService.hasRequiredPermissions();
    if (mounted) {
      setState(() {
        _hasPermissions = granted;
      });
      if (granted) {
        _updateLocation();
      }
    }
  }

  Future<void> _requestPermissions() async {
    final granted = await PermissionService.requestAllPermissions();
    if (mounted) {
      setState(() {
        _hasPermissions = granted;
      });
      if (granted) {
        _updateLocation();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Semua izin berhasil diberikan!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Beberapa izin belum diizinkan atau GPS belum aktif.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _updateLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      if (mounted) {
        setState(() {
          _currentPosition = pos;
        });
      }
    } catch (e) {
      debugPrint('Gagal mendapatkan lokasi: $e');
    }
  }

  void _handleTremorDetected(double intensity) async {
    final timestamp = TimeOfDay.now().format(context);
    final logText = '[$timestamp] ⚠️ Guncangan Terdeteksi! (${intensity.toStringAsFixed(1)} m/s²)';

    if (mounted) {
      setState(() {
        _alertLogs.insert(0, logText);
      });
    }

    // 1. Kirim alert ke cloud database jika online
    await SupabaseService.saveTremorLog(
      intensity: intensity,
      latitude: _currentPosition?.latitude,
      longitude: _currentPosition?.longitude,
      deviceName: _nearbyService.deviceName,
    );

    // 2. Broadcast secara offline ke perangkat sekitar melalui Nearby Connections
    final sentCount = await _nearbyService.broadcastTremorAlert(
      intensity: intensity,
      latitude: _currentPosition?.latitude,
      longitude: _currentPosition?.longitude,
    );

    if (sentCount > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Peringatan gempa terkirim ke $sentCount perangkat sekitar!'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _handleIncomingNearbyAlert(String sender, Map<String, dynamic> data) {
    final intensity = data['intensity'] ?? 0.0;
    final timestamp = TimeOfDay.now().format(context);
    final logText = '[$timestamp] 📡 Peringatan dari $sender! (Intensitas: $intensity)';

    if (mounted) {
      setState(() {
        _alertLogs.insert(0, logText);
      });

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 48),
          title: const Text('PERINGATAN GETARAN SEKITAR!'),
          content: Text(
            'Perangkat sekitar ($sender) mendeteksi guncangan dengan intensitas $intensity m/s².',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    _sensorService.dispose();
    _nearbyService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tremor Alert Dashboard'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Perbarui Lokasi',
            onPressed: _updateLocation,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Banner Izin Akses (Permissions)
            _buildPermissionCard(colorScheme),
            const SizedBox(height: 16),

            // 2. Sensor Monitor Guncangan Realtime
            _buildSensorCard(colorScheme),
            const SizedBox(height: 16),

            // 3. Nearby Connections (P2P Offline)
            _buildNearbyCard(colorScheme),
            const SizedBox(height: 16),

            // 4. Log Aktivitas & Peringatan
            _buildLogCard(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionCard(ColorScheme colorScheme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: _hasPermissions ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _hasPermissions ? Icons.check_circle : Icons.warning,
                  color: _hasPermissions ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  _hasPermissions ? 'Izin Akses Lengkap' : 'Izin Akses Diperlukan',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _hasPermissions
                  ? 'Bluetooth, Wi-Fi, dan Lokasi telah diizinkan. Sistem siap mendeteksi getaran & menyebarkan peringatan.'
                  : 'Aplikasi memerlukan izin Lokasi, Bluetooth, dan Wi-Fi untuk fitur Nearby Connections dan deteksi gempa.',
              style: const TextStyle(fontSize: 13),
            ),
            if (!_hasPermissions) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _requestPermissions,
                icon: const Icon(Icons.security),
                label: const Text('Izinkan Semua Akses'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
            if (_currentPosition != null) ...[
              const Divider(height: 24),
              Row(
                children: [
                  const Icon(Icons.my_location, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    'Koordinat: ${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSensorCard(ColorScheme colorScheme) {
    return ValueListenableBuilder<bool>(
      valueListenable: _sensorService.isAlertTriggered,
      builder: (context, isAlert, child) {
        return Card(
          elevation: isAlert ? 8 : 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: isAlert ? const BorderSide(color: Colors.red, width: 2) : BorderSide.none,
          ),
          color: isAlert ? Colors.red.withOpacity(0.15) : null,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.vibration, color: Colors.deepOrange),
                        SizedBox(width: 8),
                        Text(
                          'Sensor Guncangan (Accelerometer)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    if (isAlert)
                      const Chip(
                        label: Text('GEMPA!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        backgroundColor: Colors.red,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<double>(
                  valueListenable: _sensorService.currentIntensity,
                  builder: (context, intensity, child) {
                    final ratio = (intensity / 30.0).clamp(0.0, 1.0);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Intensitas Getaran: ${intensity.toStringAsFixed(2)} m/s²',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isAlert ? Colors.red : colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: ratio,
                          minHeight: 12,
                          borderRadius: BorderRadius.circular(6),
                          color: isAlert ? Colors.red : Colors.deepOrange,
                          backgroundColor: Colors.grey.withOpacity(0.2),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Ambang Batas Alarm: ${_sensorService.tremorThreshold.toStringAsFixed(1)} m/s²',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _handleTremorDetected(16.5),
                  icon: const Icon(Icons.flash_on),
                  label: const Text('Simulasi Pemicu Gempa'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNearbyCard(ColorScheme colorScheme) {
    if (!Platform.isAndroid) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Nearby Connections hanya didukung di platform Android.',
            style: TextStyle(color: colorScheme.error),
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.wifi_tethering, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Nearby Connections (P2P Offline)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Perangkat: ${_nearbyService.deviceName}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _nearbyService.isAdvertising,
                    builder: (context, isAdv, _) {
                      return ElevatedButton.icon(
                        onPressed: () {
                          if (isAdv) {
                            _nearbyService.stopAdvertising();
                          } else {
                            _nearbyService.startAdvertising();
                          }
                        },
                        icon: Icon(isAdv ? Icons.stop : Icons.sensors),
                        label: Text(isAdv ? 'Stop Siaran' : 'Mulai Siaran'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isAdv ? Colors.red : Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _nearbyService.isDiscovering,
                    builder: (context, isDisc, _) {
                      return ElevatedButton.icon(
                        onPressed: () {
                          if (isDisc) {
                            _nearbyService.stopDiscovery();
                          } else {
                            _nearbyService.startDiscovery();
                          }
                        },
                        icon: Icon(isDisc ? Icons.stop : Icons.search),
                        label: Text(isDisc ? 'Stop Cari' : 'Cari Sekitar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDisc ? Colors.red : Colors.teal,
                          foregroundColor: Colors.white,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<List<String>>(
              valueListenable: _nearbyService.connectedEndpoints,
              builder: (context, connected, _) {
                return Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: connected.isNotEmpty ? Colors.green : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Perangkat Terhubung: ${connected.length}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogCard(ColorScheme colorScheme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.history, color: Colors.grey),
                    SizedBox(width: 8),
                    Text(
                      'Riwayat Peringatan',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                if (_alertLogs.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _alertLogs.clear()),
                    child: const Text('Bersihkan'),
                  ),
              ],
            ),
            const Divider(),
            if (_alertLogs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'Belum ada peringatan getaran tercatat.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _alertLogs.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Text(
                      _alertLogs[index],
                      style: const TextStyle(fontSize: 13),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
