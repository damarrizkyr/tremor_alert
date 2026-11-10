import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';

typedef AlertReceivedCallback = void Function(String senderName, Map<String, dynamic> data);

class NearbyService {
  final Nearby _nearby = Nearby();
  static const String serviceId = 'com.example.tremor_alert';
  static const Strategy strategy = Strategy.P2P_CLUSTER;

  final ValueNotifier<bool> isAdvertising = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isDiscovering = ValueNotifier<bool>(false);
  final ValueNotifier<List<String>> connectedEndpoints = ValueNotifier<List<String>>([]);
  final ValueNotifier<List<Map<String, String>>> discoveredDevices = ValueNotifier<List<Map<String, String>>>([]);

  AlertReceivedCallback? onAlertReceived;
  final String deviceName;

  NearbyService({
    required this.deviceName,
    this.onAlertReceived,
  });

  bool get isSupported => Platform.isAndroid;

  /// Mulai mode Iklan (Advertising) agar perangkat bisa ditemukan perangkat lain
  Future<bool> startAdvertising() async {
    if (!isSupported) {
      debugPrint('[NearbyService] Nearby Connections hanya didukung di Android');
      return false;
    }

    try {
      bool success = await _nearby.startAdvertising(
        deviceName,
        strategy,
        onConnectionInitiated: (String endpointId, ConnectionInfo info) async {
          debugPrint('[NearbyService] Koneksi diinisiasi dari: ${info.endpointName} ($endpointId)');
          // Otomatis terima koneksi agar pertukaran alert darurat instan
          await _acceptConnection(endpointId);
        },
        onConnectionResult: (String endpointId, Status status) {
          debugPrint('[NearbyService] Status koneksi $endpointId: $status');
          if (status == Status.CONNECTED) {
            _addConnectedEndpoint(endpointId);
          } else {
            _removeConnectedEndpoint(endpointId);
          }
        },
        onDisconnected: (String endpointId) {
          debugPrint('[NearbyService] Perangkat terputus: $endpointId');
          _removeConnectedEndpoint(endpointId);
        },
        serviceId: serviceId,
      );

      isAdvertising.value = success;
      return success;
    } catch (e) {
      debugPrint('[NearbyService] Gagal start advertising: $e');
      isAdvertising.value = false;
      return false;
    }
  }

  /// Hentikan Advertising
  Future<void> stopAdvertising() async {
    if (!isSupported) return;
    try {
      await _nearby.stopAdvertising();
      isAdvertising.value = false;
    } catch (e) {
      debugPrint('[NearbyService] Error stopAdvertising: $e');
    }
  }

  /// Mulai mode Discovery untuk mencari perangkat sekitar
  Future<bool> startDiscovery() async {
    if (!isSupported) return false;

    try {
      bool success = await _nearby.startDiscovery(
        deviceName,
        strategy,
        onEndpointFound: (String endpointId, String endpointName, String foundServiceId) async {
          debugPrint('[NearbyService] Perangkat ditemukan: $endpointName ($endpointId)');
          
          final current = List<Map<String, String>>.from(discoveredDevices.value);
          if (!current.any((d) => d['id'] == endpointId)) {
            current.add({'id': endpointId, 'name': endpointName});
            discoveredDevices.value = current;
          }

          // Otomatis ajukan koneksi ke perangkat yang ditemukan
          try {
            await _nearby.requestConnection(
              deviceName,
              endpointId,
              onConnectionInitiated: (id, info) async {
                await _acceptConnection(id);
              },
              onConnectionResult: (id, status) {
                if (status == Status.CONNECTED) {
                  _addConnectedEndpoint(id);
                } else {
                  _removeConnectedEndpoint(id);
                }
              },
              onDisconnected: (id) {
                _removeConnectedEndpoint(id);
              },
            );
          } catch (e) {
            debugPrint('[NearbyService] Gagal requestConnection: $e');
          }
        },
        onEndpointLost: (String? endpointId) {
          debugPrint('[NearbyService] Perangkat hilang: $endpointId');
          if (endpointId != null) {
            final current = List<Map<String, String>>.from(discoveredDevices.value);
            current.removeWhere((d) => d['id'] == endpointId);
            discoveredDevices.value = current;
          }
        },
        serviceId: serviceId,
      );

      isDiscovering.value = success;
      return success;
    } catch (e) {
      debugPrint('[NearbyService] Gagal start discovery: $e');
      isDiscovering.value = false;
      return false;
    }
  }

  /// Hentikan Discovery
  Future<void> stopDiscovery() async {
    if (!isSupported) return;
    try {
      await _nearby.stopDiscovery();
      isDiscovering.value = false;
    } catch (e) {
      debugPrint('[NearbyService] Error stopDiscovery: $e');
    }
  }

  /// Terima koneksi masuk & siapkan pendengar payload pesan
  Future<void> _acceptConnection(String endpointId) async {
    await _nearby.acceptConnection(
      endpointId,
      onPayLoadRecieved: (String id, Payload payload) {
        if (payload.type == PayloadType.BYTES && payload.bytes != null) {
          try {
            final messageString = utf8.decode(payload.bytes!);
            final data = jsonDecode(messageString) as Map<String, dynamic>;
            final sender = data['sender'] ?? 'Perangkat Sekitar';
            debugPrint('[NearbyService] Pesan diterima dari $sender: $messageString');
            onAlertReceived?.call(sender, data);
          } catch (e) {
            debugPrint('[NearbyService] Gagal decode payload: $e');
          }
        }
      },
      onPayloadTransferUpdate: (String id, PayloadTransferUpdate update) {
        // Pembaruan transfer payload (jika diperlukan)
      },
    );
  }

  /// Kirim pesan peringatan guncangan (Broadcast) ke seluruh perangkat terhubung secara offline
  Future<int> broadcastTremorAlert({
    required double intensity,
    required double? latitude,
    required double? longitude,
  }) async {
    if (!isSupported || connectedEndpoints.value.isEmpty) {
      return 0;
    }

    final payloadData = {
      'type': 'TREMOR_ALERT',
      'sender': deviceName,
      'intensity': intensity,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': DateTime.now().toIso8601String(),
    };

    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payloadData)));
    int sentCount = 0;

    for (String endpointId in connectedEndpoints.value) {
      try {
        await _nearby.sendBytesPayload(endpointId, bytes);
        sentCount++;
      } catch (e) {
        debugPrint('[NearbyService] Gagal kirim payload ke $endpointId: $e');
      }
    }

    return sentCount;
  }

  void _addConnectedEndpoint(String endpointId) {
    final current = List<String>.from(connectedEndpoints.value);
    if (!current.contains(endpointId)) {
      current.add(endpointId);
      connectedEndpoints.value = current;
    }
  }

  void _removeConnectedEndpoint(String endpointId) {
    final current = List<String>.from(connectedEndpoints.value);
    current.remove(endpointId);
    connectedEndpoints.value = current;
  }

  /// Hentikan semua koneksi
  Future<void> stopAll() async {
    if (!isSupported) return;
    try {
      await stopAdvertising();
      await stopDiscovery();
      await _nearby.stopAllEndpoints();
      connectedEndpoints.value = [];
      discoveredDevices.value = [];
    } catch (e) {
      debugPrint('[NearbyService] Error stopAll: $e');
    }
  }

  void dispose() {
    stopAll();
    isAdvertising.dispose();
    isDiscovering.dispose();
    connectedEndpoints.dispose();
    discoveredDevices.dispose();
  }
}

