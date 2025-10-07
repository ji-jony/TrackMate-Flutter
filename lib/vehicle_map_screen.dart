import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'dart:math' as math;
import 'view.dart';

class VehicleMapScreen extends StatefulWidget {
  final String? vehicleId;
  final String vehicleType;

  const VehicleMapScreen({
    Key? key,
    this.vehicleId,
    this.vehicleType = 'Bus',
  }) : super(key: key);

  @override
  _VehicleMapScreenState createState() => _VehicleMapScreenState();
}

class _VehicleMapScreenState extends State<VehicleMapScreen>
    with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  
  Timer? _locationUpdateTimer;
  
  VehicleLocation? _selectedVehicle;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  
  bool _isLoading = true;
  bool _isTracking = false;
  bool _isShowingFullRoute = false;
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  final Map<String, Color> _vehicleColors = {
    'Bus': Colors.blue,
    'Train': Colors.green,
    'Air': Colors.orange,
    'Ferry': Colors.teal,
  };
  
  final Map<String, IconData> _vehicleIcons = {
    'Bus': Icons.directions_bus,
    'Train': Icons.train,
    'Air': Icons.flight,
    'Ferry': Icons.directions_boat,
  };

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startLocationUpdates();
    if (widget.vehicleId != null) {
      _isTracking = true;
    }
  }

  @override
  void dispose() {
    _locationUpdateTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    )..repeat();
    
    _pulseAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }

  void _startLocationUpdates() {
    _updateVehicleLocation();
    _locationUpdateTimer = Timer.periodic(Duration(seconds: 3), (timer) {
      _updateVehicleLocation();
    });
  }

  Future<void> _updateVehicleLocation() async {
    if (widget.vehicleId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final snapshot = await _database
          .child('shared_locations')
          .child(widget.vehicleId!)
          .once();
      
      if (!snapshot.snapshot.exists) {
        setState(() => _isLoading = false);
        return;
      }

      final data = snapshot.snapshot.value as Map<dynamic, dynamic>;
      
      // Only show if vehicle is active and public
      if (data['status'] == 'active' && data['shareType'] == 'Public') {
        final vehicle = VehicleLocation.fromJson(widget.vehicleId!, data);
        
        setState(() {
          _selectedVehicle = vehicle;
          _isLoading = false;
        });
        
        _updateMapDisplay();
        
        if (_isTracking) {
          _centerOnVehicle();
        }
        
        // Reset full route view if we're tracking and vehicle moved significantly
        if (_isShowingFullRoute && _isTracking) {
          setState(() => _isShowingFullRoute = false);
        }
      } else {
        setState(() {
          _selectedVehicle = null;
          _isLoading = false;
        });
      }

    } catch (e) {
      print('Error updating location: $e');
      setState(() => _isLoading = false);
    }
  }

  void _updateMapDisplay() {
    if (_selectedVehicle == null) {
      setState(() {
        _markers = {};
        _polylines = {};
      });
      return;
    }

    final vehicle = _selectedVehicle!;
    Set<Marker> newMarkers = {};
    Set<Polyline> newPolylines = {};
    
    // Current location marker with custom icon
    newMarkers.add(Marker(
      markerId: MarkerId('current'),
      position: LatLng(vehicle.currentLat, vehicle.currentLng),
      icon: BitmapDescriptor.defaultMarkerWithHue(
        _getMarkerHue(vehicle.vehicleType),
      ),
      infoWindow: InfoWindow(
        title: vehicle.vehicleName,
        snippet: '${vehicle.vehicleNumber} • Speed: ${vehicle.estimatedSpeed.toStringAsFixed(1)} km/h',
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
      color: _vehicleColors[vehicle.vehicleType]!,
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
    if (_selectedVehicle != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_selectedVehicle!.currentLat, _selectedVehicle!.currentLng),
          16.0,
        ),
      );
      
      setState(() {
        _isShowingFullRoute = false; // We're now focused on vehicle
      });
    }
  }

  void _showFullRoute() {
    if (_selectedVehicle != null && _mapController != null) {
      List<LatLng> allPoints = [
        LatLng(_selectedVehicle!.startLat, _selectedVehicle!.startLng),
        LatLng(_selectedVehicle!.currentLat, _selectedVehicle!.currentLng),
        LatLng(_selectedVehicle!.destLat, _selectedVehicle!.destLng),
      ];

      LatLngBounds bounds = _createBounds(allPoints);
      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
      
      setState(() {
        _isShowingFullRoute = true;
        _isTracking = false; // Stop tracking when showing full route
      });
    }
  }

  void _toggleMapView() {
    if (_isShowingFullRoute) {
      // Currently showing full route, switch to tracking vehicle
      _centerOnVehicle();
      setState(() {
        _isShowingFullRoute = false;
        _isTracking = true;
      });
    } else {
      // Currently tracking or normal view, switch to full route
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

  void _showVehicleDetails() {
    if (_selectedVehicle == null) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          color: Colors.white,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
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
                    color: _vehicleColors[_selectedVehicle!.vehicleType]!.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _vehicleIcons[_selectedVehicle!.vehicleType]!,
                    color: _vehicleColors[_selectedVehicle!.vehicleType]!,
                    size: 28,
                  ),
                ),
                SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedVehicle!.vehicleName,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _selectedVehicle!.vehicleNumber,
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                // Live indicator
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) => Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.5 + 0.5 * _pulseAnimation.value),
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: 5),
                        Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 25),
            
            // Stats row
            Row(
              children: [
                Expanded(child: _buildStatCard('Speed', '${_selectedVehicle!.estimatedSpeed.toStringAsFixed(1)} km/h', Colors.blue)),
                SizedBox(width: 10),
                Expanded(child: _buildStatCard('Progress', '${_selectedVehicle!.progressPercentage.toStringAsFixed(0)}%', Colors.green)),
                SizedBox(width: 10),
                Expanded(child: _buildStatCard('Distance', '${_selectedVehicle!.totalDistance.toStringAsFixed(1)} km', Colors.orange)),
              ],
            ),
            
            SizedBox(height: 20),
            
            // Route info
            Container(
              padding: EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _buildRouteRow('From', _selectedVehicle!.from, Icons.location_on, Colors.green),
                  SizedBox(height: 10),
                  _buildRouteRow('To', _selectedVehicle!.to, Icons.location_on, Colors.red),
                  SizedBox(height: 10),
                  _buildRouteRow('ETA', _selectedVehicle!.estimatedTime, Icons.access_time, Colors.blue),
                  SizedBox(height: 10),
                  _buildRouteRow('Updated', _formatTime(_selectedVehicle!.lastUpdated), Icons.update, Colors.grey),
                ],
              ),
            ),
            
            if (_selectedVehicle!.description.isNotEmpty) ...[
              SizedBox(height: 15),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _selectedVehicle!.description,
                        style: TextStyle(fontSize: 14, color: Colors.blue.shade700),
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
                      backgroundColor: _vehicleColors[_selectedVehicle!.vehicleType]!,
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
        Text('$label: ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        Expanded(child: Text(value, style: TextStyle(fontSize: 14))),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedVehicle != null 
            ? '${_selectedVehicle!.vehicleName} - Live Tracking'
            : 'Vehicle Tracking'),
        backgroundColor: _selectedVehicle != null 
            ? _vehicleColors[_selectedVehicle!.vehicleType]
            : _vehicleColors[widget.vehicleType],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: _vehicleColors[widget.vehicleType],
                  ),
                  SizedBox(height: 20),
                  Text('Loading vehicle location...'),
                ],
              ),
            )
          : _selectedVehicle == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.location_off, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'Vehicle not found or inactive',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'The vehicle may be offline or sharing has been disabled',
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : Stack(
                  children: [
                    GoogleMap(
                      onMapCreated: (GoogleMapController controller) {
                        _mapController = controller;
                        if (_selectedVehicle != null) {
                          _centerOnVehicle();
                        }
                      },
                      initialCameraPosition: CameraPosition(
                        target: _selectedVehicle != null
                            ? LatLng(_selectedVehicle!.currentLat, _selectedVehicle!.currentLng)
                            : LatLng(23.8103, 90.4125), // Default to Dhaka
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
                      top: 10,
                      left: 10,
                      right: 10,
                      child: Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(
                                _vehicleIcons[_selectedVehicle!.vehicleType]!,
                                color: _vehicleColors[_selectedVehicle!.vehicleType]!,
                                size: 24,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _selectedVehicle!.vehicleName,
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    Text(
                                      '${_selectedVehicle!.from} → ${_selectedVehicle!.to}',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: _showVehicleDetails,
                                child: Container(
                                  padding: EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _vehicleColors[_selectedVehicle!.vehicleType]!.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.info_outline,
                                    color: _vehicleColors[_selectedVehicle!.vehicleType]!,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    
                    // Smart toggle button for map view
                    Positioned(
                      bottom: 20,
                      right: 20,
                      child: FloatingActionButton(
                        mini: true,
                        backgroundColor: _isShowingFullRoute ? _vehicleColors[_selectedVehicle!.vehicleType] : Colors.white,
                        onPressed: _toggleMapView,
                        child: Icon(
                          _isShowingFullRoute ? Icons.my_location : Icons.zoom_out_map, 
                          color: _isShowingFullRoute ? Colors.white : Colors.grey.shade700,
                        ),
                        heroTag: "mapToggle",
                      ),
                    ),
                  ],
                ),
    );
  }
}

// VehicleLocation class remains the same
class VehicleLocation {
  final String id;
  final String vehicleName;
  final String vehicleNumber;
  final String vehicleType;
  final String from;
  final String to;
  final double currentLat;
  final double currentLng;
  final double startLat;
  final double startLng;
  final double destLat;
  final double destLng;
  final int estimatedHours;
  final int estimatedMinutes;
  final String description;
  final int lastUpdated;
  final int createdAt;

  VehicleLocation({
    required this.id,
    required this.vehicleName,
    required this.vehicleNumber,
    required this.vehicleType,
    required this.from,
    required this.to,
    required this.currentLat,
    required this.currentLng,
    required this.startLat,
    required this.startLng,
    required this.destLat,
    required this.destLng,
    required this.estimatedHours,
    required this.estimatedMinutes,
    required this.description,
    required this.lastUpdated,
    required this.createdAt,
  });

  factory VehicleLocation.fromJson(String key, Map<dynamic, dynamic> json) {
    return VehicleLocation(
      id: key,
      vehicleName: json['vehicleName'] ?? '',
      vehicleNumber: json['vehicleNumber'] ?? '',
      vehicleType: json['vehicleType'] ?? 'Bus',
      from: json['from'] ?? '',
      to: json['to'] ?? '',
      currentLat: (json['currentLat'] ?? 0.0).toDouble(),
      currentLng: (json['currentLng'] ?? 0.0).toDouble(),
      startLat: (json['startLat'] ?? 0.0).toDouble(),
      startLng: (json['startLng'] ?? 0.0).toDouble(),
      destLat: (json['destLat'] ?? 0.0).toDouble(),
      destLng: (json['destLng'] ?? 0.0).toDouble(),
      estimatedHours: json['estimatedHours'] ?? 0,
      estimatedMinutes: json['estimatedMinutes'] ?? 0,
      description: json['description'] ?? '',
      lastUpdated: json['lastUpdated'] ?? 0,
      createdAt: json['createdAt'] ?? 0,
    );
  }

  String get estimatedTime {
    if (estimatedHours == 0 && estimatedMinutes == 0) return 'Not specified';
    String timeString = '';
    if (estimatedHours > 0) timeString += '${estimatedHours}h';
    if (estimatedMinutes > 0) {
      if (timeString.isNotEmpty) timeString += ' ';
      timeString += '${estimatedMinutes}m';
    }
    return timeString;
  }

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
    if (lastUpdated == createdAt) return 0;
    
    double timeElapsedHours = (lastUpdated - createdAt) / (1000 * 60 * 60);
    if (timeElapsedHours == 0) return 0;
    
    return traveledDistance / timeElapsedHours;
  }
}