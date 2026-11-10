import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

typedef TremorCallback = void Function(double intensity);

class TremorSensorService {
  StreamSubscription<UserAccelerometerEvent>? _subscription;
  final ValueNotifier<double> currentIntensity = ValueNotifier<double>(0.0);
  final ValueNotifier<bool> isAlertTriggered = ValueNotifier<bool>(false);

  // Ambang batas guncangan (dalam m/s²) untuk deteksi gempa/tremor
  double tremorThreshold;
  
  // Cooldown agar tidak memicu alarm berulang-ulang dalam waktu singkat
  final Duration cooldownDuration;
  DateTime? _lastAlertTime;

  TremorCallback? onTremorDetected;

  TremorSensorService({
    this.tremorThreshold = 14.0,
    this.cooldownDuration = const Duration(seconds: 4),
    this.onTremorDetected,
  });

  /// Memulai pemantauan sensor accelerometer
  void startListening() {
    _subscription?.cancel();
    _subscription = userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      // Hitung besar vektor percepatan (magnitude)
      final magnitude = math.sqrt(
        (event.x * event.x) + (event.y * event.y) + (event.z * event.z),
      );

      currentIntensity.value = magnitude;

      // Evaluasi jika getaran melebihi batas ambang (threshold)
      if (magnitude >= tremorThreshold) {
        final now = DateTime.now();
        if (_lastAlertTime == null || now.difference(_lastAlertTime!) > cooldownDuration) {
          _lastAlertTime = now;
          isAlertTriggered.value = true;
          debugPrint('[TremorSensorService] Guncangan terdeteksi! Intensitas: ${magnitude.toStringAsFixed(2)} m/s²');
          
          onTremorDetected?.call(magnitude);

          // Kembalikan status visual alert setelah 2 detik
          Future.delayed(const Duration(seconds: 2), () {
            isAlertTriggered.value = false;
          });
        }
      }
    });
  }

  /// Menghentikan pemantauan sensor
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    currentIntensity.value = 0.0;
  }

  void dispose() {
    stopListening();
    currentIntensity.dispose();
    isAlertTriggered.dispose();
  }
}

