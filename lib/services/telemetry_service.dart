import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../models/telemetry_model.dart';

class TelemetryService {
  static final TelemetryService _instance = TelemetryService._internal();
  factory TelemetryService() => _instance;
  TelemetryService._internal();

  io.Socket? _socket;
  String _serverUrl = kIsWeb
      ? 'http://localhost:3000'
      : (defaultTargetPlatform == TargetPlatform.android
          ? 'http://10.0.2.2:3000'
          : 'http://localhost:3000');

  String get serverUrl => _serverUrl;

  // Stream Controllers
  final _connectionController = StreamController<bool>.broadcast();
  final _vehiclesController = StreamController<List<VehicleTelemetry>>.broadcast();
  final _alertController = StreamController<CollisionAlert?>.broadcast();
  final _blindSpotsController = StreamController<List<BlindSpotZone>>.broadcast();
  final _latencyController = StreamController<int>.broadcast();

  // Streams
  Stream<bool> get onConnectionChanged => _connectionController.stream;
  Stream<List<VehicleTelemetry>> get onVehiclesUpdated => _vehiclesController.stream;
  Stream<CollisionAlert?> get onCollisionAlert => _alertController.stream;
  Stream<List<BlindSpotZone>> get onBlindSpotsUpdated => _blindSpotsController.stream;
  Stream<int> get onLatencyChanged => _latencyController.stream;

  // Cached state
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  List<VehicleTelemetry> _currentVehicles = [];
  List<VehicleTelemetry> get currentVehicles => _currentVehicles;
  CollisionAlert? _activeAlert;
  CollisionAlert? get activeAlert => _activeAlert;
  List<BlindSpotZone> _blindSpots = [];
  List<BlindSpotZone> get blindSpots => _blindSpots;

  Timer? _pingTimer;

  void initialize({String? customUrl}) {
    if (customUrl != null && customUrl.isNotEmpty) {
      _serverUrl = customUrl;
    }
    _initSocket();
  }

  void updateServerUrl(String newUrl) {
    if (_serverUrl == newUrl) return;
    _serverUrl = newUrl;
    _socket?.disconnect();
    _socket?.dispose();
    _initSocket();
  }

  void _initSocket() {
    debugPrint('[Pahadi Telemetry] Connecting to $_serverUrl ...');
    
    try {
      _socket = io.io(
        _serverUrl,
        io.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .enableAutoConnect()
            .enableReconnection()
            .setReconnectionDelay(1000)
            .setReconnectionAttempts(999)
            .build(),
      );

      _socket?.onConnect((_) {
        debugPrint('[Pahadi Telemetry] Connected to backend: ${_socket?.id}');
        _isConnected = true;
        _connectionController.add(true);
        _startPingTimer();
      });

      _socket?.onDisconnect((_) {
        debugPrint('[Pahadi Telemetry] Disconnected from backend');
        _isConnected = false;
        _connectionController.add(false);
        _stopPingTimer();
      });

      _socket?.onConnectError((err) {
        debugPrint('[Pahadi Telemetry] Connection Error: $err');
        _isConnected = false;
        _connectionController.add(false);
      });

      // Initial state received on handshake
      _socket?.on('init_state', (data) {
        if (data is Map) {
          if (data['blindSpots'] is List) {
            _blindSpots = (data['blindSpots'] as List)
                .map((b) => BlindSpotZone.fromJson(Map<String, dynamic>.from(b)))
                .toList();
            _blindSpotsController.add(_blindSpots);
          }
          if (data['vehicles'] is List) {
            _currentVehicles = (data['vehicles'] as List)
                .map((v) => VehicleTelemetry.fromJson(Map<String, dynamic>.from(v)))
                .toList();
            _vehiclesController.add(_currentVehicles);
          }
          if (data['alerts'] is List && (data['alerts'] as List).isNotEmpty) {
            _activeAlert = CollisionAlert.fromJson(
                Map<String, dynamic>.from((data['alerts'] as List).first));
            _alertController.add(_activeAlert);
          }
        }
      });

      // High-frequency telemetry stream
      _socket?.on('telemetry_stream', (data) {
        if (data is Map && data['vehicles'] is List) {
          _currentVehicles = (data['vehicles'] as List)
              .map((v) => VehicleTelemetry.fromJson(Map<String, dynamic>.from(v)))
              .toList();
          _vehiclesController.add(_currentVehicles);
        }
      });

      // Predictive collision alert
      _socket?.on('collision_alert', (data) {
        if (data is Map) {
          _activeAlert = CollisionAlert.fromJson(Map<String, dynamic>.from(data));
          _alertController.add(_activeAlert);
        }
      });

      // Hazard cleared / vehicles diverged
      _socket?.on('collision_resolved', (data) {
        _activeAlert = null;
        _alertController.add(null);
      });

      // Vehicle cleared / reset
      _socket?.on('vehicles_cleared', (_) {
        _currentVehicles = [];
        _activeAlert = null;
        _vehiclesController.add([]);
        _alertController.add(null);
      });

    } catch (e) {
      debugPrint('[Pahadi Telemetry] Setup Exception: $e');
      _isConnected = false;
      _connectionController.add(false);
    }
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_isConnected && _socket != null) {
        final start = DateTime.now().millisecondsSinceEpoch;
        _socket?.emitWithAck('ping_test', {}, ack: (_) {
          final latency = DateTime.now().millisecondsSinceEpoch - start;
          _latencyController.add(latency);
        });
      }
    });
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// Transmit local vehicle telemetry to backend
  void sendTelemetry(VehicleTelemetry telemetry) {
    if (_isConnected && _socket != null) {
      _socket?.emit('telemetry', telemetry.toJson());
    }
  }

  /// Request backend to wipe active vehicles (for fresh demo restart)
  void clearVehicles() {
    if (_socket != null) {
      _socket?.emit('clear_vehicles');
    }
  }

  /// Dismiss active alert manually from client HUD
  void dismissAlert() {
    _activeAlert = null;
    _alertController.add(null);
  }

  void dispose() {
    _stopPingTimer();
    _socket?.disconnect();
    _socket?.dispose();
    _connectionController.close();
    _vehiclesController.close();
    _alertController.close();
    _blindSpotsController.close();
    _latencyController.close();
  }
}
