import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import 'dart:math' as math;

class Vehicle {
  final String id;
  final String name;
  final String number;
  final String type;
  final String from;
  final String to;
  final int estimatedHours;
  final int estimatedMinutes;
  final String description;
  final bool isRealTimeEnabled;
  final String passkey;
  final DateTime createdAt;
  final String status;
  final double currentLat;
  final double currentLng;
  final double startLat;
  final double startLng;
  final double destLat;
  final double destLng;
  final int lastUpdated;

  Vehicle({
    required this.id,
    required this.name,
    required this.number,
    required this.type,
    required this.from,
    required this.to,
    required this.estimatedHours,
    required this.estimatedMinutes,
    required this.description,
    required this.isRealTimeEnabled,
    required this.passkey,
    required this.createdAt,
    required this.status,
    required this.currentLat,
    required this.currentLng,
    required this.startLat,
    required this.startLng,
    required this.destLat,
    required this.destLng,
    required this.lastUpdated,
  });

  factory Vehicle.fromFirebase(String id, Map<dynamic, dynamic> data) {
    return Vehicle(
      id: id,
      name: data['vehicleName'] ?? '',
      number: data['vehicleNumber'] ?? '',
      type: data['vehicleType'] ?? '',
      from: data['from'] ?? '',
      to: data['to'] ?? '',
      estimatedHours: data['estimatedHours'] ?? 0,
      estimatedMinutes: data['estimatedMinutes'] ?? 0,
      description: data['description'] ?? '',
      isRealTimeEnabled: data['isRealTimeEnabled'] ?? false,
      passkey: data['passkey'] ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] ?? 0),
      status: data['status'] ?? 'active',
      currentLat: (data['currentLat'] ?? 0.0).toDouble(),
      currentLng: (data['currentLng'] ?? 0.0).toDouble(),
      startLat: (data['startLat'] ?? 0.0).toDouble(),
      startLng: (data['startLng'] ?? 0.0).toDouble(),
      destLat: (data['destLat'] ?? 0.0).toDouble(),
      destLng: (data['destLng'] ?? 0.0).toDouble(),
      lastUpdated: data['lastUpdated'] ?? 0,
    );
  }

  String get estimatedTime {
    if (estimatedHours == 0 && estimatedMinutes == 0) return 'N/A';
    String time = '';
    if (estimatedHours > 0) time += '${estimatedHours}h';
    if (estimatedMinutes > 0) {
      if (time.isNotEmpty) time += ' ';
      time += '${estimatedMinutes}m';
    }
    return time;
  }

  String get remainingTime => estimatedTime;

  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const double earthRadius = 6371;
    
    double dLat = _degreesToRadians(lat2 - lat1);
    double dLng = _degreesToRadians(lng2 - lng1);
    
    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) * math.cos(_degreesToRadians(lat2)) *
        math.sin(dLng / 2) * math.sin(dLng / 2);
    
    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  double get totalDistance {
    return _calculateDistance(startLat, startLng, destLat, destLng);
  }

  double get traveledDistance {
    return _calculateDistance(startLat, startLng, currentLat, currentLng);
  }

  double get progressPercentage {
    if (totalDistance == 0) return 0;
    return (traveledDistance / totalDistance) * 100;
  }

  double get estimatedSpeed {
    if (lastUpdated == createdAt.millisecondsSinceEpoch) return 0;
    
    double timeElapsedHours = (lastUpdated - createdAt.millisecondsSinceEpoch) / (1000 * 60 * 60);
    if (timeElapsedHours == 0) return 0;
    
    return traveledDistance / timeElapsedHours;
  }
}

class PrivateVehicleService {
  static final _database = FirebaseDatabase.instance.ref();

  static Future<Vehicle?> getPrivateVehicle(String passkey) async {
    try {
      final snapshot = await _database
          .child('shared_locations')
          .orderByChild('passkey')
          .equalTo(passkey.toUpperCase())
          .once();

      if (snapshot.snapshot.value != null) {
        final data = snapshot.snapshot.value as Map<dynamic, dynamic>;
        final entry = data.entries.first;
        final vehicleData = entry.value as Map<dynamic, dynamic>;
        
        if (vehicleData['shareType'] == 'Private' && vehicleData['status'] == 'active') {
          return Vehicle.fromFirebase(entry.key, vehicleData);
        }
      }
      return null;
    } catch (e) {
      print('Error fetching private vehicle: $e');
      return null;
    }
  }

  static Future<bool> terminatePrivateVehicle(String vehicleId, String passkey) async {
    try {
      await _database
          .child('shared_locations')
          .child(vehicleId)
          .update({'status': 'terminated'});
      return true;
    } catch (e) {
      print('Error terminating vehicle: $e');
      return false;
    }
  }
}

class SharePrivateScreen extends StatefulWidget {
  @override
  _SharePrivateScreenState createState() => _SharePrivateScreenState();
}

class _SharePrivateScreenState extends State<SharePrivateScreen> 
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseAnimation;
  
  final _passkeyController = TextEditingController();
  Vehicle? _activeVehicle;
  List<Vehicle> _searchHistory = [];
  bool _isSearching = false;
  String _searchError = '';
  Timer? _autoRefreshTimer;
  bool _showMapView = false;

  // Map related variables
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  bool _isTracking = false;
  bool _isShowingFullRoute = false;

  // Enhanced private color scheme
  final Color _primaryDark = Color(0xFF1A1A2E);
  final Color _secondaryDark = Color(0xFF16213E);
  final Color _accentPurple = Color(0xFF6C5CE7);
  final Color _accentGold = Color(0xFFFFD700);
  final Color _cardBackground = Color(0xFF0F1419);
  final Color _surfaceColor = Color(0xFF1E2328);

  final _vehicleIcons = {
    'Bus': Icons.directions_bus_rounded,
    'Train': Icons.train_rounded,
    'Air': Icons.flight_rounded,
    'Ferry': Icons.directions_boat_rounded,
  };

  final _vehicleColors = {
    'Bus': Color(0xFF6C5CE7),
    'Train': Color(0xFF00CED1),
    'Air': Color(0xFF9370DB),
    'Ferry': Color(0xFF20B2AA),
  };

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _startAutoRefresh();
  }

  void _initAnimations() {
    _fadeController = AnimationController(duration: Duration(milliseconds: 800), vsync: this);
    _slideController = AnimationController(duration: Duration(milliseconds: 600), vsync: this);
    _pulseController = AnimationController(duration: Duration(seconds: 2), vsync: this)..repeat();
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    
    _slideAnimation = Tween<Offset>(begin: Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.elasticOut),
    );

    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _fadeController.forward();
    _slideController.forward();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (_activeVehicle != null) {
        _refreshActiveVehicle();
      }
    });
  }

  Future<void> _refreshActiveVehicle() async {
    if (_activeVehicle != null) {
      final updatedVehicle = await PrivateVehicleService.getPrivateVehicle(_activeVehicle!.passkey);
      if (updatedVehicle != null) {
        setState(() => _activeVehicle = updatedVehicle);
        if (_showMapView) {
          _updateMapDisplay();
          if (_isTracking) {
            _centerOnVehicle();
          }
        }
      } else {
        _showSnackBar('Vehicle is no longer active', false);
        _clearActiveVehicle();
      }
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    _passkeyController.dispose();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _searchPrivateVehicle() async {
    if (_passkeyController.text.trim().isEmpty) {
      setState(() => _searchError = 'Please enter a passkey');
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = '';
    });

    try {
      final vehicle = await PrivateVehicleService.getPrivateVehicle(_passkeyController.text.trim());
      
      if (vehicle != null) {
        setState(() {
          _activeVehicle = vehicle;
          _addToSearchHistory(vehicle);
          _isSearching = false;
        });
        _showSnackBar('Vehicle found and tracked!', true);
        _passkeyController.clear();
      } else {
        setState(() {
          _isSearching = false;
          _searchError = 'No private vehicle found with this passkey';
        });
      }
    } catch (e) {
      setState(() {
        _isSearching = false;
        _searchError = 'Search failed. Please try again.';
      });
    }
  }

  void _addToSearchHistory(Vehicle vehicle) {
    setState(() {
      _searchHistory.removeWhere((v) => v.id == vehicle.id);
      _searchHistory.insert(0, vehicle);
      if (_searchHistory.length > 5) _searchHistory.removeLast();
    });
  }

  void _clearActiveVehicle() {
    setState(() {
      _activeVehicle = null;
      _passkeyController.clear();
      _showMapView = false;
    });
  }

  void _isMapViewVisible () {
    if (_activeVehicle != null) {
      setState(() {
        _showMapView = true;
        _isTracking = true;
      });
      Future.delayed(Duration(milliseconds: 500), () {
        _updateMapDisplay();
        _centerOnVehicle();
      });
    }
  }

  void _updateMapDisplay() {
    if (_activeVehicle == null) {
      setState(() {
        _markers = {};
        _polylines = {};
      });
      return;
    }

    final vehicle = _activeVehicle!;
    Set<Marker> newMarkers = {};
    Set<Polyline> newPolylines = {};
    
    // Current location marker with custom icon
    newMarkers.add(Marker(
      markerId: MarkerId('current'),
      position: LatLng(vehicle.currentLat, vehicle.currentLng),
      icon: BitmapDescriptor.defaultMarkerWithHue(
        _getMarkerHue(vehicle.type),
      ),
      infoWindow: InfoWindow(
        title: vehicle.name,
        snippet: '${vehicle.number} • Speed: ${vehicle.estimatedSpeed.toStringAsFixed(1)} km/h',
      ),
      onTap: () => _showVehicleDetails(),
    ));

    // Start location marker
    newMarkers.add(Marker(
      markerId: MarkerId('start'),
      position: LatLng(vehicle.startLat, vehicle.startLng),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow: InfoWindow(
        title: 'Start: ${vehicle.from}',
      ),
    ));

    // Destination marker
    newMarkers.add(Marker(
      markerId: MarkerId('destination'),
      position: LatLng(vehicle.destLat, vehicle.destLng),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: InfoWindow(
        title: 'Destination: ${vehicle.to}',
      ),
    ));

    // Route polyline
    List<LatLng> routePoints = [
      LatLng(vehicle.startLat, vehicle.startLng),
      LatLng(vehicle.currentLat, vehicle.currentLng),
      LatLng(vehicle.destLat, vehicle.destLng),
    ];

    newPolylines.add(Polyline(
      polylineId: PolylineId('route'),
      points: routePoints,
      color: _vehicleColors[vehicle.type]!,
      width: 4,
      patterns: [PatternItem.dash(15), PatternItem.gap(8)],
    ));

    setState(() {
      _markers = newMarkers;
      _polylines = newPolylines;
    });
  }

  double _getMarkerHue(String vehicleType) {
    switch (vehicleType) {
      case 'Bus': return BitmapDescriptor.hueBlue;
      case 'Train': return BitmapDescriptor.hueGreen;
      case 'Air': return BitmapDescriptor.hueOrange;
      case 'Ferry': return BitmapDescriptor.hueCyan;
      default: return BitmapDescriptor.hueRed;
    }
  }

  void _centerOnVehicle() {
    if (_activeVehicle != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_activeVehicle!.currentLat, _activeVehicle!.currentLng),
          16.0,
        ),
      );
      
      setState(() {
        _isShowingFullRoute = false;
      });
    }
  }

  void _showFullRoute() {
    if (_activeVehicle != null && _mapController != null) {
      List<LatLng> allPoints = [
        LatLng(_activeVehicle!.startLat, _activeVehicle!.startLng),
        LatLng(_activeVehicle!.currentLat, _activeVehicle!.currentLng),
        LatLng(_activeVehicle!.destLat, _activeVehicle!.destLng),
      ];

      LatLngBounds bounds = _createBounds(allPoints);
      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
      
      setState(() {
        _isShowingFullRoute = true;
        _isTracking = false;
      });
    }
  }

  void _toggleMapView() {
    if (_isShowingFullRoute) {
      _centerOnVehicle();
      setState(() {
        _isShowingFullRoute = false;
        _isTracking = true;
      });
    } else {
      _showFullRoute();
    }
  }

  LatLngBounds _createBounds(List<LatLng> points) {
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (LatLng point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  void _showTerminateDialog(Vehicle vehicle) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: _accentGold, size: 24),
            SizedBox(width: 12),
            Text('Terminate Tracking', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Text(
          'Are you sure you want to stop tracking ${vehicle.name}?',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await PrivateVehicleService.terminatePrivateVehicle(vehicle.id, vehicle.passkey);
              _showSnackBar(success ? 'Vehicle terminated successfully' : 'Termination failed', success);
              if (success) _clearActiveVehicle();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text('Terminate'),
          ),
        ],
      ),
    );
  }

  void _showVehicleDetails() {
    if (_activeVehicle == null) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          color: _cardBackground,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _accentPurple.withOpacity(0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(height: 20),
            
            // Vehicle header
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _vehicleColors[_activeVehicle!.type]!.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _vehicleIcons[_activeVehicle!.type]!,
                    color: _vehicleColors[_activeVehicle!.type]!,
                    size: 28,
                  ),
                ),
                SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _activeVehicle!.name,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        _activeVehicle!.number,
                        style: TextStyle(fontSize: 16, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
                // Live and Private indicators
                Column(
                  children: [
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) => Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade600,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.5 + 0.5 * _pulseAnimation.value),
                                shape: BoxShape.circle,
                              ),
                            ),
                            SizedBox(width: 4),
                            Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 4),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _accentPurple,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('PRIVATE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
            
            SizedBox(height: 25),
            
            // Stats row
            Row(
              children: [
                Expanded(child: _buildStatCard('Speed', '${_activeVehicle!.estimatedSpeed.toStringAsFixed(1)} km/h', Colors.blue)),
                SizedBox(width: 10),
                Expanded(child: _buildStatCard('Progress', '${_activeVehicle!.progressPercentage.toStringAsFixed(0)}%', Colors.green)),
                SizedBox(width: 10),
                Expanded(child: _buildStatCard('Distance', '${_activeVehicle!.totalDistance.toStringAsFixed(1)} km', Colors.orange)),
              ],
            ),
            
            SizedBox(height: 20),
            
            // Route info
            Container(
              padding: EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: _surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _accentPurple.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  _buildRouteRow('From', _activeVehicle!.from, Icons.location_on, Colors.green),
                  SizedBox(height: 10),
                  _buildRouteRow('To', _activeVehicle!.to, Icons.location_on, Colors.red),
                  SizedBox(height: 10),
                  _buildRouteRow('ETA', _activeVehicle!.estimatedTime, Icons.access_time, _accentGold),
                  SizedBox(height: 10),
                  _buildRouteRow('Updated', _formatTime(_activeVehicle!.lastUpdated), Icons.update, Colors.grey),
                ],
              ),
            ),
            
            if (_activeVehicle!.description.isNotEmpty) ...[
              SizedBox(height: 15),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _accentPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _accentPurple.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: _accentPurple, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _activeVehicle!.description,
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            SizedBox(height: 20),
            
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() => _isTracking = true);
                      _centerOnVehicle();
                    },
                    icon: Icon(Icons.my_location),
                    label: Text('Track Vehicle'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _vehicleColors[_activeVehicle!.type]!,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showFullRoute();
                    },
                    icon: Icon(Icons.route),
                    label: Text('Full Route'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade600,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(title, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
          SizedBox(height: 5),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildRouteRow(String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        SizedBox(width: 10),
        Text('$label: ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white)),
        Expanded(child: Text(value, style: TextStyle(fontSize: 14, color: Colors.white70))),
      ],
    );
  }

  String _formatTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    }
  }

  void _showSnackBar(String message, bool isSuccess) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: Colors.white)),
        backgroundColor: isSuccess ? _accentPurple : Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _primaryDark,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(_showMapView ? 'Private Vehicle Map' : 'Private Tracker', 
                   style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_primaryDark, _secondaryDark],
            ),
          ),
        ),
        actions: _activeVehicle != null ? [
          IconButton(
            icon: Icon(_showMapView ? Icons.list_rounded : Icons.map_rounded),
            onPressed: () {
              if (_showMapView) {
                setState(() => _showMapView = false);
              } else {
                _isMapViewVisible ();
              }
            },
          ),
        ] : null,
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: _showMapView ? _buildMapView() : _buildListView(),
      ),
    );
  }

  Widget _buildMapView() {
    if (_activeVehicle == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No vehicle to track',
              style: TextStyle(fontSize: 18, color: Colors.white),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        GoogleMap(
          onMapCreated: (GoogleMapController controller) {
            _mapController = controller;
            _updateMapDisplay();
            _centerOnVehicle();
          },
          initialCameraPosition: CameraPosition(
            target: LatLng(_activeVehicle!.currentLat, _activeVehicle!.currentLng),
            zoom: 14.0,
          ),
          markers: _markers,
          polylines: _polylines,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
        ),
        
        // Vehicle info card
        Positioned(
          top: 110,
          left: 10,
          right: 10,
          child: Card(
            elevation: 8,
            color: _cardBackground,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _vehicleColors[_activeVehicle!.type]!.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _vehicleIcons[_activeVehicle!.type]!,
                      color: _vehicleColors[_activeVehicle!.type]!,
                      size: 20,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _activeVehicle!.name,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                        ),
                        Text(
                          '${_activeVehicle!.from} → ${_activeVehicle!.to}',
                          style: TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                  // Live indicator
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) => Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade600,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.5 + 0.5 * _pulseAnimation.value),
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: 4),
                          Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  GestureDetector(
                    onTap: _showVehicleDetails,
                    child: Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _accentPurple.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.info_outline,
                        color: _accentPurple,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        // Map control buttons
        Positioned(
          bottom: 30,
          right: 20,
          child: Column(
            children: [
              FloatingActionButton(
                mini: true,
                backgroundColor: _isShowingFullRoute ? _accentPurple : Colors.white,
                onPressed: _toggleMapView,
                child: Icon(
                  _isShowingFullRoute ? Icons.my_location : Icons.zoom_out_map, 
                  color: _isShowingFullRoute ? Colors.white : Colors.grey.shade700,
                ),
                heroTag: "mapToggle",
              ),
              SizedBox(height: 10),
              FloatingActionButton(
                mini: true,
                backgroundColor: Colors.red.shade600,
                onPressed: () => _showTerminateDialog(_activeVehicle!),
                child: Icon(Icons.stop_rounded, color: Colors.white),
                heroTag: "terminate",
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildListView() {
    return Column(
      children: [
        _buildCompactHeader(),
        Expanded(child: _buildMainContent()),
      ],
    );
  }

  Widget _buildCompactHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_primaryDark, _secondaryDark],
        ),
      ),
      child: Column(
        children: [
          SizedBox(height: 100),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _accentPurple.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _accentPurple.withOpacity(0.5)),
                      ),
                      child: Icon(Icons.security_rounded, size: 28, color: _accentGold),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Private Vehicle Access',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Secure tracking with encrypted passkey',
                            style: TextStyle(color: _accentGold.withOpacity(0.8), fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20),
                _buildSearchBox(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBox() {
    return Container(
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accentPurple.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: _accentPurple.withOpacity(0.2),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _passkeyController,
              decoration: InputDecoration(
                hintText: 'Enter secure passkey...',
                hintStyle: TextStyle(color: Colors.white38),
                prefixIcon: Icon(Icons.vpn_key_rounded, color: _accentGold, size: 20),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                errorText: _searchError.isNotEmpty ? _searchError : null,
                errorStyle: TextStyle(color: Colors.red.shade400, fontSize: 12),
              ),
              style: TextStyle(color: Colors.white, fontSize: 16),
              textCapitalization: TextCapitalization.characters,
              onChanged: (value) => setState(() => _searchError = ''),
              onSubmitted: (value) => _searchPrivateVehicle(),
            ),
          ),
          Container(
            margin: EdgeInsets.all(4),
            child: ElevatedButton(
              onPressed: _isSearching ? null : _searchPrivateVehicle,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentPurple,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade700,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              child: _isSearching
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(Icons.search_rounded, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    if (_activeVehicle != null) {
      return _buildVehicleDetails();
    } else {
      return _buildWelcomeContent();
    }
  }

  Widget _buildWelcomeContent() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        children: [
          SizedBox(height: 40),
          Container(
            padding: EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: _cardBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _accentPurple.withOpacity(0.3)),
              boxShadow: [
                BoxShadow(
                  color: _accentPurple.withOpacity(0.2),
                  blurRadius: 15,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                Icon(Icons.radar_rounded, size: 80, color: _accentPurple.withOpacity(0.7)),
                SizedBox(height: 20),
                Text(
                  'Awaiting Private Vehicle',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                SizedBox(height: 10),
                Text(
                  'Enter your encrypted passkey to establish secure connection',
                  style: TextStyle(color: Colors.white60, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          SizedBox(height: 30),
          if (_searchHistory.isNotEmpty) _buildSearchHistory(),
        ],
      ),
    );
  }

  Widget _buildSearchHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history_rounded, color: _accentGold, size: 20),
            SizedBox(width: 8),
            Text(
              'Recent Connections',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        SizedBox(height: 15),
        ...(_searchHistory.take(3).map((vehicle) => _buildHistoryItem(vehicle)).toList()),
      ],
    );
  }

  Widget _buildHistoryItem(Vehicle vehicle) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accentPurple.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: _accentPurple.withOpacity(0.1),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(_vehicleIcons[vehicle.type] ?? Icons.directions_bus_rounded, 
               color: _vehicleColors[vehicle.type], size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(vehicle.name, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14)),
                Text(vehicle.number, style: TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              _passkeyController.text = vehicle.passkey;
              _searchPrivateVehicle();
            },
            icon: Icon(Icons.refresh_rounded, color: _accentGold, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleDetails() {
    final vehicle = _activeVehicle!;
    final vehicleColor = _vehicleColors[vehicle.type] ?? _accentPurple;
    final vehicleIcon = _vehicleIcons[vehicle.type] ?? Icons.directions_bus_rounded;

    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        children: [
          // Status indicator
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _accentPurple.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _accentPurple.withOpacity(0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.security_rounded, color: _accentGold, size: 16),
                SizedBox(width: 8),
                Text(
                  'Secure Connection Active',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          
          SizedBox(height: 20),
          
          // Compact vehicle information card
          Container(
            decoration: BoxDecoration(
              color: _cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _accentPurple.withOpacity(0.3)),
              boxShadow: [
                BoxShadow(
                  color: _accentPurple.withOpacity(0.2),
                  blurRadius: 15,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                // Vehicle header
                Container(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: vehicleColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: vehicleColor.withOpacity(0.5)),
                        ),
                        child: Icon(vehicleIcon, color: vehicleColor, size: 20),
                      ),
                      SizedBox(width: 12),
                      
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vehicle.name,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              vehicle.number,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      Column(
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade600,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'LIVE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(height: 4),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _accentPurple,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'PRIVATE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Route information
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 16),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _accentPurple.withOpacity(0.2)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.radio_button_checked, color: Colors.green, size: 14),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              vehicle.from,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.schedule, color: _accentGold, size: 14),
                          SizedBox(width: 8),
                          Text(
                            'Est. ${vehicle.estimatedTime}',
                            style: TextStyle(
                              fontSize: 12,
                              color: _accentGold,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.location_on, color: Colors.red, size: 14),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              vehicle.to,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Description (if available)
                if (vehicle.description.isNotEmpty) ...[
                  SizedBox(height: 12),
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 16),
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _accentPurple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _accentPurple.withOpacity(0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: _accentPurple, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            vehicle.description,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                // Action buttons
                Container(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isMapViewVisible ,
                          icon: Icon(Icons.map_rounded, size: 18),
                          label: Text('View Map'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accentPurple,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _showTerminateDialog(vehicle),
                          icon: Icon(Icons.stop_rounded, size: 18),
                          label: Text('Terminate'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white54,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  }