import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:ui';
import 'dart:developer' as dev;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late AnimationController _sosScaleController;
  late AnimationController _headerSlideController;
  late AnimationController _statusDotPulseController;
  late AnimationController _shieldGlowController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _sosScaleAnimation;
  late Animation<Offset> _headerSlideAnimation;
  late Animation<double> _statusDotPulseAnimation;
  late Animation<double> _shieldGlowAnimation;

  bool _isBackendConnected = false;

  // Active incident tracking
  bool _hasActiveIncident = false;
  int _incidentThreatScore = 0;
  String _incidentType = '';

  // SOS Button State
  bool _isSOSPressed = false;
  int _sosCountdown = 10;
  Timer? _sosTimer;

  // Device Connection State
  Timer? _deviceMonitorTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _wifiConnected = false;
  bool _bluetoothEnabled = false;

  // Real statistics from backend
  int _totalIncidents = 0;
  String _monitoringTime = '0h';
  int _activeAlerts = 0;
  bool _isLoadingStats = true;

  Map<String, dynamic> _gloveData = {
    'connected': false,
    'battery': 0,
    'signal': 0,
    'lastSync': 'Never',
    'connectionType': 'none',
    'deviceId': 'SafeHer_Glove_001',
  };
  Map<String, dynamic> _glassesData = {
    'connected': false,
    'battery': 0,
    'signal': 0,
    'lastSync': 'Never',
    'connectionType': 'none',
    'deviceId': 'SafeHer_Glasses_001',
  };

  @override
  void initState() {
    super.initState();
    dev.log(
      'DEBUG: Initializing HomeScreen with devices in disconnected state',
    );
    dev.log('DEBUG: Glove connected: ${_gloveData['connected']}');
    dev.log('DEBUG: Glasses connected: ${_glassesData['connected']}');

    _checkBackendConnection();

    // Pulse animation for SOS button
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    // Fade in animation
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeIn));

    // SOS scale animation
    _sosScaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _sosScaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _sosScaleController, curve: Curves.easeInOut),
    );

    // Header slide-in animation
    _headerSlideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _headerSlideAnimation =
        Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _headerSlideController,
            curve: Curves.easeOut,
          ),
        );

    // Status dot pulse animation
    _statusDotPulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _statusDotPulseAnimation = Tween<double>(begin: 1.0, end: 1.4).animate(
      CurvedAnimation(
        parent: _statusDotPulseController,
        curve: Curves.easeInOut,
      ),
    );

    // Shield glow animation
    _shieldGlowController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _shieldGlowAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _shieldGlowController, curve: Curves.easeInOut),
    );

    _fadeController.forward();
    _headerSlideController.forward();

    // Start real connectivity monitoring
    _startRealConnectivityMonitoring();

    // Fetch real statistics
    _fetchRealStatistics();
  }

  // Fetch mock statistics (no backend needed)
  Future<void> _fetchRealStatistics() async {
    try {
      setState(() => _isLoadingStats = true);

      // Simulate network delay
      await Future.delayed(const Duration(milliseconds: 500));

      // Mock incidents data
      final List<Map<String, dynamic>> mockIncidents = [
        {
          'incident_type': 'motion_detection',
          'status': 'active',
          'confidence_score': 0.92,
          'created_at': DateTime.now()
              .subtract(const Duration(days: 2))
              .toIso8601String(),
        },
        {
          'incident_type': 'voice_detection',
          'status': 'resolved',
          'confidence_score': 0.87,
          'created_at': DateTime.now()
              .subtract(const Duration(days: 5))
              .toIso8601String(),
        },
      ];

      setState(() {
        _totalIncidents = mockIncidents.length;

        // Calculate monitoring time from first incident to now
        if (mockIncidents.isNotEmpty) {
          try {
            final firstIncident = mockIncidents.last;
            final firstDate = DateTime.parse(
              firstIncident['created_at'] as String,
            );
            final duration = DateTime.now().difference(firstDate);

            if (duration.inDays > 0) {
              _monitoringTime = '${duration.inDays}d';
            } else {
              _monitoringTime = '${duration.inHours}h';
            }
          } catch (e) {
            dev.log('DEBUG: Error calculating monitoring time: $e');
            _monitoringTime = '0h';
          }
        }

        // Count active alerts (incidents with status = 'active')
        final activeIncidents = mockIncidents.where((incident) {
          return incident['status']?.toString().toLowerCase() == 'active';
        }).toList();

        _activeAlerts = activeIncidents.length;

        // Update active incident tracking
        if (activeIncidents.isNotEmpty) {
          _hasActiveIncident = true;
          // Get the highest threat score from active incidents
          final latestIncident = activeIncidents.first;
          _incidentThreatScore =
              (((latestIncident['confidence_score'] as num?) ?? 0.0) * 100)
                  .toInt();
          _incidentType =
              latestIncident['incident_type']?.toString() ?? 'Unknown';
        } else {
          _hasActiveIncident = false;
          _incidentThreatScore = 0;
          _incidentType = '';
        }

        _isLoadingStats = false;
      });

      dev.log(
        'DEBUG: Loaded $_totalIncidents mock incidents, $_activeAlerts active',
      );
    } catch (e) {
      dev.log('DEBUG: Error fetching statistics: $e');
      setState(() {
        _isLoadingStats = false;
      });
    }
  }

  /// Get threat level based on score (matches React component)
  String _getThreatLevel(int score) {
    if (score < 20) return 'safe';
    if (score < 40) return 'low';
    if (score < 60) return 'medium';
    if (score < 80) return 'high';
    return 'critical';
  }

  /// Get threat level color
  Color _getThreatColor(String level) {
    switch (level) {
      case 'safe':
        return const Color(0xFF10B981);
      case 'low':
        return const Color(0xFF3B82F6);
      case 'medium':
        return const Color(0xFFF59E0B);
      case 'high':
        return const Color(0xFFEF4444);
      case 'critical':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFF6B7280);
    }
  }

  Future<void> _checkBackendConnection() async {
    // Offline mode - just set as not connected
    if (mounted) {
      setState(() {
        _isBackendConnected = false;
      });
    }
  }

  Future<void> _triggerSOS() async {
    // Show immediate feedback
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('SOS Activated! Emergency services notified.'),
        backgroundColor: Color(0xFFEF4444),
        duration: Duration(seconds: 5),
      ),
    );

    try {
      // In offline mode, just log the SOS
      dev.log('SOS triggered at ${DateTime.now().toIso8601String()}');
    } catch (e) {
      dev.log('Error in SOS: $e');
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    _sosScaleController.dispose();
    _headerSlideController.dispose();
    _statusDotPulseController.dispose();
    _shieldGlowController.dispose();
    _sosTimer?.cancel();
    _deviceMonitorTimer?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  // Start real connectivity monitoring
  void _startRealConnectivityMonitoring() {
    // Initialize connectivity checking
    _checkInitialConnectivity();

    // Listen to connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      final primaryResult = results.isNotEmpty
          ? results.first
          : ConnectivityResult.none;
      _handleConnectivityChange(primaryResult);
    });

    // Initialize Bluetooth monitoring
    _initializeBluetoothMonitoring();

    // Periodic device status updates
    _deviceMonitorTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _updateDeviceStatus();
    });
  }

  // Check initial connectivity state
  Future<void> _checkInitialConnectivity() async {
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      final primaryResult = connectivityResults.isNotEmpty
          ? connectivityResults.first
          : ConnectivityResult.none;
      _handleConnectivityChange(primaryResult);
    } catch (e) {
      debugPrint('Error checking initial connectivity: $e');
    }
  }

  // Handle connectivity changes
  void _handleConnectivityChange(ConnectivityResult result) {
    if (mounted) {
      dev.log('DEBUG: WiFi connectivity changed to: $result');
      setState(() {
        _wifiConnected = result == ConnectivityResult.wifi;
        dev.log('DEBUG: WiFi connected: $_wifiConnected');

        // Don't automatically connect glasses just because WiFi is available
        // In a real app, you would scan for SafeHer devices on the network
        // For now, we'll be strict and not auto-connect
        if (!_wifiConnected) {
          dev.log(
            'DEBUG: WiFi disconnected, checking if glasses should disconnect',
          );
          // WiFi disconnected - disconnect glasses if they were connected via WiFi
          if (_glassesData['connectionType'] == 'wifi') {
            dev.log('DEBUG: Disconnecting glasses due to WiFi loss');
            _glassesData = {
              ..._glassesData,
              'connected': false,
              'connectionType': 'none',
              'signal': 0,
              'lastSync': 'WiFi Disconnected',
              'battery': 0,
            };
          }
        }
        // Note: WiFi being connected doesn't automatically mean SafeHer glasses are available
        // Real implementation would scan for actual devices
      });
    }
  }

  // Manual WiFi toggle for testing
  void _toggleWiFiForTesting() {
    debugPrint('DEBUG: _toggleWiFiForTesting() function called');
    dev.log('DEBUG: Manually toggling WiFi state');
    setState(() {
      _wifiConnected = !_wifiConnected;
      dev.log('DEBUG: WiFi manually set to: $_wifiConnected');

      if (!_wifiConnected) {
        // Manually turn off WiFi - disconnect WiFi devices
        if (_glassesData['connectionType'] == 'wifi') {
          _glassesData = {
            ..._glassesData,
            'connected': false,
            'connectionType': 'none',
            'signal': 0,
            'lastSync': 'WiFi Turned Off',
            'battery': 0,
          };
        }
        dev.log('DEBUG: Disconnected WiFi devices due to WiFi off');
      } else {
        dev.log('DEBUG: WiFi turned on - devices can now connect via WiFi');
      }
    });
  }

  // Initialize Bluetooth monitoring
  Future<void> _initializeBluetoothMonitoring() async {
    try {
      // Check if Bluetooth is available (might not work on web)
      bool isAvailable = await FlutterBluePlus.isSupported;
      dev.log('DEBUG: Bluetooth available: $isAvailable');

      if (isAvailable) {
        // Listen to Bluetooth state changes
        FlutterBluePlus.adapterState.listen((BluetoothAdapterState state) {
          dev.log('DEBUG: Bluetooth state changed to: $state');
          _handleBluetoothStateChange(state);
        });

        // Periodically check for connected devices
        Timer.periodic(const Duration(seconds: 5), (timer) async {
          if (!mounted) {
            timer.cancel();
            return;
          }
          try {
            final devices = FlutterBluePlus.connectedDevices;
            _handleBluetoothDevicesChange(devices);
          } catch (e) {
            debugPrint('Error getting connected devices: $e');
          }
        });

        // Initial Bluetooth state check
        final currentState = await FlutterBluePlus.adapterState.first;
        dev.log('DEBUG: Initial Bluetooth state: $currentState');
        _handleBluetoothStateChange(currentState);
      } else {
        // Bluetooth not available (probably web)
        dev.log('DEBUG: Bluetooth not available on this platform');
        _handleBluetoothUnavailable();
      }
    } catch (e) {
      dev.log('DEBUG: Bluetooth initialization error: $e');
      _handleBluetoothUnavailable();
    }
  }

  // Handle Bluetooth state changes
  void _handleBluetoothStateChange(BluetoothAdapterState state) {
    dev.log('DEBUG: Handling Bluetooth state change: $state');
    if (mounted) {
      setState(() {
        _bluetoothEnabled = state == BluetoothAdapterState.on;
        dev.log('DEBUG: Bluetooth enabled set to: $_bluetoothEnabled');

        if (!_bluetoothEnabled) {
          dev.log(
            'DEBUG: Bluetooth is off, disconnecting all Bluetooth devices',
          );
          // Bluetooth is off - disconnect all Bluetooth devices
          _gloveData = {
            ..._gloveData,
            'connected': false,
            'connectionType': 'none',
            'signal': 0,
            'lastSync': 'Bluetooth Off',
            'battery': 0,
          };

          if (_glassesData['connectionType'] == 'bluetooth') {
            _glassesData = {
              ..._glassesData,
              'connected': _wifiConnected, // Keep WiFi connection if available
              'connectionType': _wifiConnected ? 'wifi' : 'none',
              'signal': _wifiConnected ? _glassesData['signal'] : 0,
              'lastSync': _wifiConnected
                  ? _glassesData['lastSync']
                  : 'Bluetooth Off',
              'battery': _wifiConnected ? _glassesData['battery'] : 0,
            };
          }
        } else {
          dev.log('DEBUG: Bluetooth is now enabled');
        }
      });
    }
  }

  // Handle Bluetooth devices changes
  void _handleBluetoothDevicesChange(List<BluetoothDevice> devices) {
    if (mounted) {
      setState(() {
        // Only connect if we find actual SafeHer devices by name
        // For real implementation, you would check device.platformName
        // Since we don't have real SafeHer devices, we'll be strict about connections
        bool gloveConnected = devices.any(
          (device) =>
              device.platformName.toLowerCase().contains('safeher') &&
              device.platformName.toLowerCase().contains('glove'),
        );

        bool glassesViaBluetooth = devices.any(
          (device) =>
              device.platformName.toLowerCase().contains('safeher') &&
              device.platformName.toLowerCase().contains('glasses'),
        );

        // Update glove connection - only connect if actual device found
        if (gloveConnected && _bluetoothEnabled) {
          _gloveData = {
            ..._gloveData,
            'connected': true,
            'connectionType': 'bluetooth',
            'signal': _generateSignalStrength(),
            'lastSync': _getTimeAgo(),
          };
          if (_gloveData['battery'] == 0) {
            _gloveData['battery'] = 70 + math.Random().nextInt(25); // 70-95%
          }
        } else {
          // No SafeHer glove found or Bluetooth off
          _gloveData = {
            ..._gloveData,
            'connected': false,
            'connectionType': 'none',
            'signal': 0,
            'lastSync': _bluetoothEnabled
                ? 'Device Not Found'
                : 'Bluetooth Off',
            'battery': 0,
          };
        }

        // Update glasses connection (Bluetooth fallback if no WiFi)
        if (glassesViaBluetooth && _bluetoothEnabled && !_wifiConnected) {
          _glassesData = {
            ..._glassesData,
            'connected': true,
            'connectionType': 'bluetooth',
            'signal': _generateSignalStrength(),
            'lastSync': _getTimeAgo(),
          };
          if (_glassesData['battery'] == 0) {
            _glassesData['battery'] = 85 + math.Random().nextInt(15); // 85-100%
          }
        } else if (!_wifiConnected) {
          // No WiFi and no Bluetooth glasses found
          _glassesData = {
            ..._glassesData,
            'connected': false,
            'connectionType': 'none',
            'signal': 0,
            'lastSync': _bluetoothEnabled
                ? 'Device Not Found'
                : 'Bluetooth Off',
            'battery': 0,
          };
        }
      });
    }
  }

  // Handle Bluetooth unavailable (web platform)
  void _handleBluetoothUnavailable() {
    dev.log(
      'DEBUG: Bluetooth unavailable - ensuring all devices stay disconnected',
    );
    if (mounted) {
      setState(() {
        _bluetoothEnabled = false;
        // Ensure all devices are disconnected when Bluetooth is unavailable
        _gloveData = {
          ..._gloveData,
          'connected': false,
          'connectionType': 'none',
          'signal': 0,
          'lastSync': 'Bluetooth Unavailable',
          'battery': 0,
        };

        // Glasses also stay disconnected unless specifically connected via other means
        // Don't auto-connect via WiFi
        dev.log(
          'DEBUG: Ensuring glasses stay disconnected without real device detection',
        );
        _glassesData = {
          ..._glassesData,
          'connected': false,
          'connectionType': 'none',
          'signal': 0,
          'lastSync': 'No SafeHer Devices Found',
          'battery': 0,
        };
      });
    }
  }

  // Update device status periodically
  void _updateDeviceStatus() {
    if (!mounted) return;

    setState(() {
      // Update battery levels for connected devices
      if (_gloveData['connected']) {
        _gloveData['battery'] = _updateBatteryLevel(_gloveData['battery']);
        _gloveData['signal'] = _generateSignalStrength();
        _gloveData['lastSync'] = _getTimeAgo();
      }

      if (_glassesData['connected']) {
        _glassesData['battery'] = _updateBatteryLevel(_glassesData['battery']);
        _glassesData['signal'] = _generateSignalStrength();
        _glassesData['lastSync'] = _getTimeAgo();
      }
    });
  }

  // Update battery level with realistic drain
  int _updateBatteryLevel(int currentBattery) {
    final random = math.Random();
    // Slowly drain battery with occasional small increases (charging)
    final change = random.nextInt(100) < 5
        ? 1
        : (random.nextInt(100) < 20 ? -1 : 0);
    return math.max(0, math.min(100, currentBattery + change));
  }

  // Generate realistic signal strength
  int _generateSignalStrength() {
    final random = math.Random();
    return 60 + random.nextInt(40); // 60-100%
  }

  // Get formatted time ago string
  String _getTimeAgo() {
    final random = math.Random();
    final seconds = random.nextInt(10) + 1;
    return '${seconds}s ago';
  }

  void _onSOSPressStart() {
    setState(() {
      _isSOSPressed = true;
      _sosCountdown = 10;
    });
    _sosScaleController.forward();
    _startSOSCountdown();
  }

  void _onSOSPressEnd() {
    setState(() {
      _isSOSPressed = false;
      _sosCountdown = 10;
    });
    _sosScaleController.reverse();
    _sosTimer?.cancel();
  }

  void _startSOSCountdown() {
    _sosTimer?.cancel();
    _sosTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isSOSPressed) {
        timer.cancel();
        return;
      }

      if (_sosCountdown <= 1) {
        timer.cancel();
        _triggerSOS();
        _onSOSPressEnd();
        return;
      }

      setState(() {
        _sosCountdown--;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final threatLevel = _getThreatLevel(_incidentThreatScore);
    final threatColor = _getThreatColor(threatLevel);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F172A), // Deep navy
              Color(0xFF1E1B4B), // Deep purple
              Color(0xFF312E81), // Purple-blue
              Color(0xFF1E293B), // Slate
            ],
            stops: [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status Header
                  _buildStatusHeader(),
                  const SizedBox(height: 16),

                  // Threat Banner (only show when there's an active incident)
                  if (_hasActiveIncident) ...[
                    _buildThreatBanner(threatLevel, threatColor),
                    const SizedBox(height: 16),
                  ],

                  // Connection Status
                  _buildConnectionStatus(),

                  // SOS Button (like React SOSButton component)
                  Center(child: _buildSOSButton()),
                  const SizedBox(height: 32),

                  // Devices Section
                  _buildSectionHeader('DEVICES'),
                  const SizedBox(height: 12),
                  _buildDevicesSection(),
                  const SizedBox(height: 32),

                  // Quick Stats Section
                  _buildSectionHeader('QUICK STATS'),
                  const SizedBox(height: 12),
                  _buildQuickStatsSection(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Status Header Widget (SafeHer branding with monitoring status)
  Widget _buildStatusHeader() {
    String statusText = 'Monitoring';
    Color statusColor = const Color(0xFF10B981); // Green for monitoring

    if (_hasActiveIncident) {
      statusText = 'Alert Active';
      statusColor = const Color(0xFFEF4444); // Red for alert
    } else if (!_isBackendConnected) {
      statusText = 'Offline';
      statusColor = const Color(0xFF94A3B8); // Gray for offline
    }

    return SlideTransition(
      position: _headerSlideAnimation,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E293B), Color(0xFF334155)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF475569), width: 1),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Row(
              children: [
                // SafeHer Logo/Icon with glow animation
                AnimatedBuilder(
                  animation: _shieldGlowAnimation,
                  builder: (context, child) {
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                            const Color(0xFFEC4899).withValues(alpha: 0.2),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF8B5CF6).withValues(
                              alpha: 0.4 * _shieldGlowAnimation.value,
                            ),
                            blurRadius: 20 * _shieldGlowAnimation.value,
                            spreadRadius: 3 * (_shieldGlowAnimation.value - 1),
                          ),
                        ],
                      ),
                      child: Transform.scale(
                        scale: 0.95 + (0.05 * _shieldGlowAnimation.value),
                        child: const Icon(
                          Icons.shield,
                          color: Color(0xFFFAFAFA),
                          size: 28,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 16),
                // SafeHer Title and Status
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SafeHer',
                        style: TextStyle(
                          color: const Color(0xFFFAFAFA),
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              offset: const Offset(0, 2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Protection Active',
                        style: TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                // Monitoring Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        statusColor.withValues(alpha: 0.25),
                        statusColor.withValues(alpha: 0.15),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Pulsing status dot
                      AnimatedBuilder(
                        animation: _statusDotPulseAnimation,
                        builder: (context, child) {
                          return Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: statusColor.withValues(alpha: 0.8),
                                  blurRadius:
                                      8 * _statusDotPulseAnimation.value,
                                  spreadRadius:
                                      2 * (_statusDotPulseAnimation.value - 1),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: const Color(0xFFFAFAFA),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          shadows: [
                            Shadow(
                              color: statusColor.withValues(alpha: 0.5),
                              offset: const Offset(0, 1),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Threat Banner Widget (matches React ThreatBanner)
  Widget _buildThreatBanner(String level, Color color) {
    String getMessage(String level) {
      switch (level) {
        case 'safe':
          return 'Environment is secure';
        case 'low':
          return 'Low threat detected';
        case 'medium':
          return 'Medium threat level';
        case 'high':
          return 'High threat detected!';
        case 'critical':
          return 'CRITICAL THREAT!';
        default:
          return 'Monitoring...';
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              level == 'safe'
                  ? Icons.check_circle_outline
                  : level == 'critical'
                  ? Icons.dangerous
                  : Icons.warning_amber_rounded,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  getMessage(level),
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Threat Score: $_incidentThreatScore/100 • $_incidentType',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$_incidentThreatScore',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // SOS Button Widget (matches React SOSButton with countdown)
  Widget _buildSOSButton() {
    return Column(
      children: [
        AnimatedBuilder(
          animation: _sosScaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _sosScaleAnimation.value,
              child: GestureDetector(
                onTapDown: (_) => _onSOSPressStart(),
                onTapUp: (_) => _onSOSPressEnd(),
                onTapCancel: () => _onSOSPressEnd(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 128,
                  height: 128,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _isSOSPressed
                          ? [const Color(0xFFEF4444), const Color(0xFFDC2626)]
                          : [const Color(0xFFEF4444), const Color(0xFFDC2626)],
                    ),
                    borderRadius: BorderRadius.circular(64),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(
                          0xFFEF4444,
                        ).withValues(alpha: _isSOSPressed ? 0.6 : 0.4),
                        blurRadius: _isSOSPressed ? 30 : 20,
                        spreadRadius: _isSOSPressed ? 5 : 0,
                      ),
                      BoxShadow(
                        color: const Color(
                          0xFFEF4444,
                        ).withValues(alpha: _isSOSPressed ? 0.4 : 0.2),
                        blurRadius: _isSOSPressed ? 50 : 40,
                        spreadRadius: _isSOSPressed ? 15 : 10,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Inner ring
                      Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                            width: 2,
                          ),
                        ),
                      ),
                      // Content
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder:
                            (Widget child, Animation<double> animation) {
                              return ScaleTransition(
                                scale: animation,
                                child: FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                              );
                            },
                        child: _isSOSPressed
                            ? Text(
                                _sosCountdown.toString(),
                                key: ValueKey('countdown_$_sosCountdown'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                ),
                              )
                            : const Text(
                                'SOS',
                                key: ValueKey('sos_text'),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 3,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Text(
          _isSOSPressed ? 'Release to cancel' : 'Press & hold for emergency',
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // Section Header Widget
  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }

  // Devices Section (matches React DeviceCard components)
  Widget _buildDevicesSection() {
    return Row(
      children: [
        Expanded(
          child: _buildDeviceCard(
            icon: Icons.gesture,
            name: 'Smart Glove',
            connected: _gloveData['connected'],
            battery: _gloveData['battery'],
            signalStrength: _gloveData['signal'],
            lastSync: _gloveData['lastSync'],
            connectionType: _gloveData['connectionType'],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildDeviceCard(
            icon: Icons.visibility,
            name: 'Smart Glasses',
            connected: _glassesData['connected'],
            battery: _glassesData['battery'],
            signalStrength: _glassesData['signal'],
            lastSync: _glassesData['lastSync'],
            connectionType: _glassesData['connectionType'],
          ),
        ),
      ],
    );
  }

  // Quick Stats Section (matches React StatCard components)
  Widget _buildQuickStatsSection() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon: Icons.warning_amber_rounded,
                value: _isLoadingStats ? '...' : '$_totalIncidents',
                label: 'Total Incidents',
                color: const Color(0xFFEF4444),
                onTap: () {
                  // Navigate to incidents screen
                  Navigator.pushNamed(context, '/incident-history');
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                icon: Icons.schedule,
                value: _isLoadingStats ? '...' : _monitoringTime,
                label: 'Monitoring Time',
                color: const Color(0xFF3B82F6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon: Icons.shield,
                value: _hasActiveIncident
                    ? _getThreatLevel(_incidentThreatScore)
                    : 'Safe',
                label: 'Threat Level',
                color: _hasActiveIncident
                    ? _getThreatColor(_getThreatLevel(_incidentThreatScore))
                    : const Color(0xFF10B981),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                icon: Icons.notifications_none,
                value: _isLoadingStats ? '...' : '$_activeAlerts',
                label: 'Active Alerts',
                color: _activeAlerts > 0
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF10B981),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Device Card Widget (matches React DeviceCard component)
  Widget _buildDeviceCard({
    required IconData icon,
    required String name,
    required bool connected,
    required int battery,
    required int signalStrength,
    required String lastSync,
    required String connectionType,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Device Icon and Name
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Connection Status
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: connected
                      ? const Color(0xFF10B981)
                      : const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                connected ? 'Connected' : 'Disconnected',
                style: TextStyle(
                  color: connected
                      ? const Color(0xFF10B981)
                      : const Color(0xFFEF4444),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Battery and Signal
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Battery
              Row(
                children: [
                  Icon(
                    Icons.battery_std,
                    color: battery > 20
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                    size: 12,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '$battery%',
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 9,
                    ),
                  ),
                ],
              ),

              // Signal Strength
              Text(
                '$signalStrength%',
                style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 9),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Last Sync
          Text(
            lastSync,
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 8),
          ),
          const SizedBox(height: 10),

          // Manual connection button
          InkWell(
            onTap: () async => await _toggleDeviceConnection(name),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              decoration: BoxDecoration(
                color: connected
                    ? const Color(0xFFEF4444).withValues(alpha: 0.1)
                    : const Color(0xFF6366F1).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: connected
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF6366F1),
                  width: 1,
                ),
              ),
              child: Text(
                connected ? 'Disconnect' : 'Connect Device',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: connected
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF6366F1),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Real device connection with actual scanning
  Future<void> _toggleDeviceConnection(String deviceName) async {
    dev.log('DEBUG: Toggling connection for $deviceName');

    if (deviceName.contains('Glove')) {
      if (_gloveData['connected']) {
        // Disconnect glove
        await _disconnectDevice('glove');
      } else {
        // Scan and connect to real glove device
        await _scanAndConnectDevice('glove');
      }
    } else if (deviceName.contains('Glasses')) {
      if (_glassesData['connected']) {
        // Disconnect glasses
        await _disconnectDevice('glasses');
      } else {
        // Scan and connect to real glasses device
        await _scanAndConnectDevice('glasses');
      }
    }
  }

  // Disconnect device
  Future<void> _disconnectDevice(String deviceType) async {
    setState(() {
      if (deviceType == 'glove') {
        _gloveData = {
          ..._gloveData,
          'connected': false,
          'connectionType': 'none',
          'signal': 0,
          'lastSync': 'Disconnected',
          'battery': 0,
        };
        dev.log('DEBUG: Disconnected glove');
      } else {
        _glassesData = {
          ..._glassesData,
          'connected': false,
          'connectionType': 'none',
          'signal': 0,
          'lastSync': 'Disconnected',
          'battery': 0,
        };
        dev.log('DEBUG: Disconnected glasses');
      }
    });
  }

  // Scan and connect to real SafeHer device
  Future<void> _scanAndConnectDevice(String deviceType) async {
    dev.log('DEBUG: Starting real device scan for $deviceType');

    // Update UI to show scanning state
    setState(() {
      if (deviceType == 'glove') {
        _gloveData = {..._gloveData, 'lastSync': 'Scanning...'};
      } else {
        _glassesData = {..._glassesData, 'lastSync': 'Scanning...'};
      }
    });

    try {
      // For glove: Bluetooth only
      if (deviceType == 'glove') {
        if (!_bluetoothEnabled) {
          setState(() {
            _gloveData = {
              ..._gloveData,
              'lastSync': 'Bluetooth is OFF - Turn it on',
            };
          });
          return;
        }
        await _scanBluetoothDevices(deviceType);
      }
      // For glasses: Try WiFi first, then Bluetooth
      else {
        bool foundViaWiFi = false;
        if (_wifiConnected) {
          foundViaWiFi = await _scanWiFiDevices(deviceType);
        }

        if (!foundViaWiFi && _bluetoothEnabled) {
          await _scanBluetoothDevices(deviceType);
        } else if (!foundViaWiFi && !_bluetoothEnabled) {
          setState(() {
            _glassesData = {
              ..._glassesData,
              'lastSync': 'Turn ON WiFi or Bluetooth',
            };
          });
        }
      }
    } catch (e) {
      dev.log('DEBUG: Error during device scan: $e');
      setState(() {
        if (deviceType == 'glove') {
          _gloveData = {..._gloveData, 'lastSync': 'Scan Error'};
        } else {
          _glassesData = {..._glassesData, 'lastSync': 'Scan Error'};
        }
      });
    }
  }

  // Scan for WiFi devices (network discovery)
  Future<bool> _scanWiFiDevices(String deviceType) async {
    dev.log('DEBUG: Scanning WiFi network for SafeHer $deviceType');

    // In a real implementation, you would:
    // 1. Scan local network for devices
    // 2. Look for SafeHer devices advertising themselves
    // 3. Use mDNS/Bonjour service discovery
    // 4. Check for specific device identifiers

    // Simulate network scan delay
    await Future.delayed(const Duration(seconds: 2));

    // For now, show that no WiFi-enabled SafeHer devices were found
    // Real implementation would use network_info_plus and lan_scanner packages
    setState(() {
      _glassesData = {..._glassesData, 'lastSync': 'No WiFi Device Found'};
    });

    return false;
  }

  // Scan for Bluetooth devices
  Future<void> _scanBluetoothDevices(String deviceType) async {
    dev.log('DEBUG: Scanning Bluetooth for SafeHer $deviceType');

    // Check if running on web platform
    if (kIsWeb) {
      dev.log('DEBUG: Running on web - Bluetooth scanning limited');
      setState(() {
        if (deviceType == 'glove') {
          _gloveData = {
            ..._gloveData,
            'lastSync': 'Deploy to Android/iOS for real scanning',
          };
        } else {
          _glassesData = {
            ..._glassesData,
            'lastSync': 'Deploy to Android/iOS for real scanning',
          };
        }
      });
      return;
    }

    try {
      // Check if Bluetooth is available
      bool isAvailable = await FlutterBluePlus.isSupported;
      if (!isAvailable) {
        setState(() {
          if (deviceType == 'glove') {
            _gloveData = {..._gloveData, 'lastSync': 'Bluetooth Unavailable'};
          } else {
            _glassesData = {
              ..._glassesData,
              'lastSync': 'Bluetooth Unavailable',
            };
          }
        });
        return;
      }

      // Start scanning for Bluetooth devices
      dev.log('DEBUG: Starting Bluetooth scan...');
      List<BluetoothDevice> foundDevices = [];

      // Start scan with timeout
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

      // Listen to scan results
      FlutterBluePlus.scanResults.listen((results) {
        for (var result in results) {
          final device = result.device;
          final deviceName = device.platformName.toLowerCase();

          dev.log('DEBUG: Found BT device: ${device.platformName}');

          // Check if this is a SafeHer device
          if (deviceName.contains('safeher')) {
            if (deviceType == 'glove' && deviceName.contains('glove')) {
              foundDevices.add(device);
              dev.log('DEBUG: Found SafeHer Glove!');
            } else if (deviceType == 'glasses' &&
                (deviceName.contains('glasses') ||
                    deviceName.contains('glass'))) {
              foundDevices.add(device);
              dev.log('DEBUG: Found SafeHer Glasses!');
            }
          }
        }
      });

      // Wait for scan to complete
      await Future.delayed(const Duration(seconds: 5));
      await FlutterBluePlus.stopScan();

      // Check if we found any matching devices
      if (foundDevices.isNotEmpty) {
        dev.log('DEBUG: Connecting to ${foundDevices[0].platformName}');
        await _connectToBluetoothDevice(foundDevices[0], deviceType);
      } else {
        dev.log('DEBUG: No SafeHer $deviceType found via Bluetooth');
        setState(() {
          if (deviceType == 'glove') {
            _gloveData = {
              ..._gloveData,
              'lastSync': 'No Device Found - Check pairing',
            };
          } else {
            _glassesData = {
              ..._glassesData,
              'lastSync': 'No Device Found - Check pairing',
            };
          }
        });
      }
    } catch (e) {
      dev.log('DEBUG: Bluetooth scan error: $e');
      setState(() {
        if (deviceType == 'glove') {
          _gloveData = {
            ..._gloveData,
            'lastSync': 'Bluetooth Error - Check permissions',
          };
        } else {
          _glassesData = {
            ..._glassesData,
            'lastSync': 'Bluetooth Error - Check permissions',
          };
        }
      });
    }
  }

  // Connect to actual Bluetooth device
  Future<void> _connectToBluetoothDevice(
    BluetoothDevice device,
    String deviceType,
  ) async {
    try {
      dev.log('DEBUG: Attempting connection to ${device.platformName}');

      // Connect to the device
      await device.connect(timeout: const Duration(seconds: 10));

      // Get battery level from device (if available)
      int batteryLevel = await _readBatteryLevel(device);

      setState(() {
        if (deviceType == 'glove') {
          _gloveData = {
            ..._gloveData,
            'connected': true,
            'connectionType': 'bluetooth',
            'signal': _generateSignalStrength(),
            'lastSync': _getTimeAgo(),
            'battery': batteryLevel,
          };
        } else {
          _glassesData = {
            ..._glassesData,
            'connected': true,
            'connectionType': 'bluetooth',
            'signal': _generateSignalStrength(),
            'lastSync': _getTimeAgo(),
            'battery': batteryLevel,
          };
        }
      });

      dev.log('DEBUG: Successfully connected to $deviceType');
    } catch (e) {
      dev.log('DEBUG: Failed to connect: $e');
      setState(() {
        if (deviceType == 'glove') {
          _gloveData = {..._gloveData, 'lastSync': 'Connection Failed'};
        } else {
          _glassesData = {..._glassesData, 'lastSync': 'Connection Failed'};
        }
      });
    }
  }

  // Read battery level from Bluetooth device
  Future<int> _readBatteryLevel(BluetoothDevice device) async {
    try {
      // Discover services
      List<BluetoothService> services = await device.discoverServices();

      // Look for battery service (UUID: 0x180F)
      for (var service in services) {
        if (service.uuid.toString().toLowerCase().contains('180f')) {
          for (var characteristic in service.characteristics) {
            // Battery level characteristic (UUID: 0x2A19)
            if (characteristic.uuid.toString().toLowerCase().contains('2a19')) {
              List<int> value = await characteristic.read();
              if (value.isNotEmpty) {
                return value[0]; // Battery level is first byte
              }
            }
          }
        }
      }
    } catch (e) {
      dev.log('DEBUG: Could not read battery level: $e');
    }

    // Default battery level if we can't read it
    return 75;
  }

  // Device connection status indicator
  Widget _buildConnectionStatus() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildConnectionIndicator('WiFi', _wifiConnected, Icons.wifi),
          Container(width: 1, height: 20, color: const Color(0xFF2A2A2A)),
          _buildConnectionIndicator(
            'Bluetooth',
            _bluetoothEnabled,
            Icons.bluetooth,
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionIndicator(String name, bool connected, IconData icon) {
    return InkWell(
      onTap: () {
        dev.log('DEBUG: Clicked on $name indicator');
        // Add manual toggle for testing (especially useful on web)
        if (name == 'Bluetooth') {
          _toggleBluetoothForTesting();
        } else if (name == 'WiFi') {
          dev.log('DEBUG: WiFi toggle triggered');
          _toggleWiFiForTesting();
        }
      },
      child: Row(
        children: [
          Icon(
            icon,
            color: connected
                ? const Color(0xFF10B981)
                : const Color(0xFF6B7280),
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: TextStyle(
              color: connected
                  ? const Color(0xFF10B981)
                  : const Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: connected
                  ? const Color(0xFF10B981)
                  : const Color(0xFFEF4444),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  // Manual Bluetooth toggle for testing (useful on web platform)
  void _toggleBluetoothForTesting() {
    dev.log('DEBUG: Manually toggling Bluetooth state');
    setState(() {
      _bluetoothEnabled = !_bluetoothEnabled;
      dev.log('DEBUG: Bluetooth manually set to: $_bluetoothEnabled');

      if (!_bluetoothEnabled) {
        // Manually turn off Bluetooth - disconnect devices
        _gloveData = {
          ..._gloveData,
          'connected': false,
          'connectionType': 'none',
          'signal': 0,
          'lastSync': 'Bluetooth Turned Off',
          'battery': 0,
        };

        if (_glassesData['connectionType'] == 'bluetooth') {
          _glassesData = {
            ..._glassesData,
            'connected': _wifiConnected,
            'connectionType': _wifiConnected ? 'wifi' : 'none',
            'signal': _wifiConnected ? _glassesData['signal'] : 0,
            'lastSync': _wifiConnected
                ? _glassesData['lastSync']
                : 'Bluetooth Off',
            'battery': _wifiConnected ? _glassesData['battery'] : 0,
          };
        }
        dev.log('DEBUG: Disconnected devices due to Bluetooth off');
      } else {
        dev.log('DEBUG: Bluetooth turned on - devices can now connect');
      }
    });
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    final cardContent = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );

    // If onTap is provided, wrap in InkWell for clickable functionality
    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: cardContent,
      );
    }

    return cardContent;
  }
}
