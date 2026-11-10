import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static bool _isInitialized = false;

  /// Inisialisasi Supabase dengan URL dan Anon Key Anda.
  /// Ganti placeholder dengan kredensial project Supabase Anda.
  static Future<bool> initialize({
    String? url,
    String? anonKey,
  }) async {
    final supabaseUrl = url ?? 'https://xyzcompany.supabase.co';
    final supabaseAnonKey = anonKey ?? 'public-anon-key';

    // Hindari inisialisasi jika kredensial masih default placeholder
    if (supabaseUrl.contains('xyzcompany') || supabaseAnonKey.contains('public-anon-key')) {
      debugPrint('[SupabaseService] Belum dikonfigurasi dengan URL & Key asli. Mode offline aktif.');
      return false;
    }

    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );
      _isInitialized = true;
      debugPrint('[SupabaseService] Berhasil terhubung ke Supabase');
      return true;
    } catch (e) {
      debugPrint('[SupabaseService] Gagal inisialisasi Supabase: $e');
      _isInitialized = false;
      return false;
    }
  }

  static bool get isInitialized => _isInitialized;

  /// Menyimpan log guncangan gempa ke Supabase (Cloud Database)
  static Future<bool> saveTremorLog({
    required double intensity,
    required double? latitude,
    required double? longitude,
    String? deviceName,
  }) async {
    if (!_isInitialized) {
      debugPrint('[SupabaseService] Supabase belum aktif. Log disimpan secara lokal.');
      return false;
    }

    try {
      final client = Supabase.instance.client;
      await client.from('tremor_reports').insert({
        'intensity': intensity,
        'latitude': latitude,
        'longitude': longitude,
        'device_name': deviceName ?? 'Unknown Device',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      debugPrint('[SupabaseService] Berhasil mengirim log gempa ke cloud!');
      return true;
    } catch (e) {
      debugPrint('[SupabaseService] Gagal menyimpan log ke cloud: $e');
      return false;
    }
  }
}

