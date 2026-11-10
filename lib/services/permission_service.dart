import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  /// Meminta seluruh izin runtime yang diperlukan untuk
  /// Nearby Connections, Geolocator, dan Sensor.
  static Future<bool> requestAllPermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return true;
    }

    // 1. Pastikan layanan GPS (Location Service) aktif di perangkat
    final isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isLocationServiceEnabled) {
      debugPrint('[PermissionService] GPS belum aktif. Meminta pengguna mengaktifkan GPS...');
      // Mengarahkan pengguna ke pengaturan lokasi jika GPS belum ON
      await Geolocator.openLocationSettings();
    }

    List<Permission> permissionsToRequest = [];

    // Izin Lokasi (Diperlukan oleh geolocator & Nearby Connections)
    permissionsToRequest.add(Permission.location);

    if (Platform.isAndroid) {
      // Izin Bluetooth & Wi-Fi untuk Nearby Connections
      permissionsToRequest.addAll([
        Permission.bluetooth,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.nearbyWifiDevices,
      ]);
    }

    // Eksekusi permintaan izin runtime secara bersamaan
    Map<Permission, PermissionStatus> statuses = await permissionsToRequest.request();

    bool allGranted = true;
    statuses.forEach((permission, status) {
      debugPrint('[PermissionService] $permission: $status');
      if (!status.isGranted && !status.isLimited) {
        allGranted = false;
      }
    });

    return allGranted;
  }

  /// Cek apakah izin krusial sudah diberikan
  static Future<bool> hasRequiredPermissions() async {
    final locationGranted = await Permission.location.isGranted;
    if (Platform.isAndroid) {
      final bluetoothScan = await Permission.bluetoothScan.isGranted;
      final bluetoothConnect = await Permission.bluetoothConnect.isGranted;
      final bluetoothAdvertise = await Permission.bluetoothAdvertise.isGranted;
      return locationGranted && bluetoothScan && bluetoothConnect && bluetoothAdvertise;
    }
    return locationGranted;
  }
}

