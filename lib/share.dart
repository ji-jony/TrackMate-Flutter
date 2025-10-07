import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'train_route.dart';

class ShareLocationScreen extends StatefulWidget {
  @override
  _ShareLocationScreenState createState() => _ShareLocationScreenState();
}

class _ShareLocationScreenState extends State<ShareLocationScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _database = FirebaseDatabase.instance.ref();
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  GoogleMapController? _mapController;
  Timer? _locationUpdateTimer;
  Timer? _searchDebouncer;
  
  final _vehicleNameController = TextEditingController();
  final _vehicleNumberController = TextEditingController();
  final _fromController = TextEditingController();
  final _toController = TextEditingController();
  final _passwordController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  final _fromFocusNode = FocusNode();
  final _toFocusNode = FocusNode();
  
  String _selectedVehicleType = 'Bus';
  String _shareType = 'Public';
  String _generatedPasskey = '';
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  int _selectedHours = 0;
  int _selectedMinutes = 0;
  
  static final LatLngBounds bangladeshBounds = LatLngBounds(
    southwest: LatLng(20.670883, 88.028336),
    northeast: LatLng(26.4465255, 92.6804979),
  );
  
  LatLng _currentPosition = LatLng(23.8103, 90.4125);
  LatLng? _startPosition;
  LatLng? _destinationPosition;
  bool _isMapReady = false;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  String? _locationShareId;
  bool _isSettingStart = false;
  bool _isSettingDestination = false;
  bool _isLoadingRoute = false;
  
  List<LocationSuggestion> _fromSuggestions = [];
  List<LocationSuggestion> _toSuggestions = [];
  bool _showFromSuggestions = false;
  bool _showToSuggestions = false;
  bool _isSearchingFrom = false;
  bool _isSearchingTo = false;
  
  final TrainRouteService _trainService = TrainRouteService();
  List<TrainRoute> _availableTrains = [];
  TrainRoute? _selectedTrainRoute;
  bool _showTrainRoutes = false;
  
  final _vehicleTypes = ['Bus', 'Train', 'Air', 'Ferry'];
  final _shareTypes = ['Public', 'Private'];

  final Map<String, LatLng> _bangladeshLocations = {
    'Dhaka': LatLng(23.8103, 90.4125),
    'Chittagong': LatLng(22.3569, 91.7832),
    'Sylhet': LatLng(24.8949, 91.8687),
    'Rajshahi': LatLng(24.3745, 88.6042),
    'Khulna': LatLng(22.8456, 89.5403),
    'Barisal': LatLng(22.7010, 90.3535),
    'Rangpur': LatLng(25.7439, 89.2752),
    'Mymensingh': LatLng(24.7471, 90.4203),
    'Comilla': LatLng(23.4682, 91.1788),
    'Cox\'s Bazar': LatLng(21.4272, 92.0058),
    'Gazipur': LatLng(23.9999, 90.4203),
    'Narayanganj': LatLng(23.6238, 90.4990),
    'Jessore': LatLng(23.1665, 89.2081),
    'Bogura': LatLng(24.8465, 89.3775),
    'Dinajpur': LatLng(25.6217, 88.6354),
    'Kushtia': LatLng(23.9013, 89.1205),
    'Faridpur': LatLng(23.6070, 89.8429),
    'Tangail': LatLng(24.2513, 89.9167),
    'Jamalpur': LatLng(24.9158, 89.9370),
    'Pabna': LatLng(24.0064, 89.2372),
  };

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(duration: Duration(milliseconds: 800), vsync: this);
    _slideAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));
    _animationController.forward();
    _generatePasskey();
    _getCurrentLocation();
    _setupTextFieldListeners();
    _loadAvailableTrains();
  }

  void _loadAvailableTrains() {
    _availableTrains = _trainService.getAllTrains();
  }

  void _setupTextFieldListeners() {
    _fromController.addListener(() => _onSearchChanged(_fromController.text, true));
    _toController.addListener(() => _onSearchChanged(_toController.text, false));
    _fromFocusNode.addListener(() {
      if (!_fromFocusNode.hasFocus) setState(() => _showFromSuggestions = false);
    });
    _toFocusNode.addListener(() {
      if (!_toFocusNode.hasFocus) setState(() => _showToSuggestions = false);
    });
  }

  void _onSearchChanged(String query, bool isFrom) {
    if (_selectedVehicleType == 'Train') {
      _searchTrainRoutes(query, isFrom);
    } else {
      _searchDebouncer?.cancel();
      _searchDebouncer = Timer(Duration(milliseconds: 300), () => _searchPlaces(query, isFrom));
    }
  }
  void _searchTrainRoutes(String query, bool isFrom) {
    if (query.trim().isEmpty) {
      setState(() {
        if (isFrom) {
          _fromSuggestions = [];
          _showFromSuggestions = false;
          _isSearchingFrom = false;
        } else {
          _toSuggestions = [];
          _showToSuggestions = false;
          _isSearchingTo = false;
        }
        _availableTrains = _trainService.getAllTrains();
        _showTrainRoutes = false;
      });
      return;
    }

    setState(() {
      if (isFrom) {
        _isSearchingFrom = true;
        _showFromSuggestions = true;
      } else {
        _isSearchingTo = true;
        _showToSuggestions = true;
      }
    });

    try {
      List<TrainRoute> matchingTrains = _trainService.searchTrains(query);
      Set<String> stationNames = _trainService.getAllStationNames();
      List<String> matchingStations = stationNames
          .where((station) => station.toLowerCase().contains(query.toLowerCase()))
          .take(8)
          .toList();

      List<LocationSuggestion> suggestions = [];
      
      for (String stationName in matchingStations) {
        TrainStation? station = _trainService.findStation(stationName);
        if (station != null) {
          suggestions.add(LocationSuggestion(
            address: station.name,
            position: station.position,
            type: SuggestionType.transport,
            trainStation: station,
          ));
        }
      }

      setState(() {
        if (isFrom) {
          _fromSuggestions = suggestions;
          _isSearchingFrom = false;
        } else {
          _toSuggestions = suggestions;
          _isSearchingTo = false;
        }
        _availableTrains = matchingTrains;
        _showTrainRoutes = matchingTrains.isNotEmpty;
      });
    } catch (e) {
      setState(() {
        if (isFrom) {
          _fromSuggestions = [];
          _isSearchingFrom = false;
        } else {
          _toSuggestions = [];
          _isSearchingTo = false;
        }
      });
      print('Error searching train routes: $e');
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _locationUpdateTimer?.cancel();
    _searchDebouncer?.cancel();
    [_vehicleNameController, _vehicleNumberController, _fromController, _toController, _passwordController, _descriptionController].forEach((c) => c.dispose());
    [_fromFocusNode, _toFocusNode].forEach((f) => f.dispose());
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition();
        LatLng newPos = LatLng(position.latitude, position.longitude);
        
        if (_isWithinBangladesh(newPos)) {
          setState(() => _currentPosition = newPos);
          _updateCameraPosition(_currentPosition);
        }
      }
    } catch (e) {
      print('Error getting location: $e');
    }
  }

  bool _isWithinBangladesh(LatLng position) {
    return position.latitude >= bangladeshBounds.southwest.latitude &&
           position.latitude <= bangladeshBounds.northeast.latitude &&
           position.longitude >= bangladeshBounds.southwest.longitude &&
           position.longitude <= bangladeshBounds.northeast.longitude;
  }

  void _generatePasskey() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    Random random = Random();
    _generatedPasskey = String.fromCharCodes(Iterable.generate(8, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
  }

  IconData _getVehicleIcon(String type) {
    const icons = {'Bus': Icons.directions_bus, 'Train': Icons.train, 'Air': Icons.flight, 'Ferry': Icons.directions_boat};
    return icons[type] ?? Icons.directions_bus;
  }

  Color _getVehicleColor(String type) {
    const colors = {'Bus': Colors.green, 'Train': Colors.blue, 'Air': Colors.orange, 'Ferry': Colors.teal};
    return colors[type] ?? Colors.green;
  }

  String _getFormattedTime() {
    if (_selectedHours == 0 && _selectedMinutes == 0) return '';
    String timeString = '';
    if (_selectedHours > 0) timeString += '${_selectedHours}h';
    if (_selectedMinutes > 0) {
      if (timeString.isNotEmpty) timeString += ' ';
      timeString += '${_selectedMinutes}m';
    }
    return timeString;
  }

  bool _validateEstimatedTime() => _selectedHours > 0 || _selectedMinutes > 0;

  Future<void> _searchPlaces(String query, bool isFrom) async {
  if (query.trim().isEmpty) {
    setState(() {
      if (isFrom) {
        _fromSuggestions = [];
        _showFromSuggestions = false;
        _isSearchingFrom = false;
      } else {
        _toSuggestions = [];
        _showToSuggestions = false;
        _isSearchingTo = false;
      }
    });
    return;
  }

  if (query.length < 2) return;

  setState(() {
    if (isFrom) {
      _isSearchingFrom = true;
      _showFromSuggestions = true;
    } else {
      _isSearchingTo = true;
      _showToSuggestions = true;
    }
  });

  try {
    List<LocationSuggestion> suggestions = [];
    
    // Add Bangladesh preset locations first
    suggestions.addAll(_getBangladeshLocationSuggestions(query));
    
    // Search with multiple query variations for better results
    List<String> searchQueries = [
      '$query Bangladesh',
      '$query Dhaka Bangladesh', 
      '$query Chittagong Bangladesh',
      '$query Sylhet Bangladesh',
      query.trim(),
    ];
    
    for (String searchQuery in searchQueries) {
      if (suggestions.length >= 10) break;
      
      try {
        List<Location> locations = await locationFromAddress(searchQuery);
        
        for (Location loc in locations.take(5)) {
          LatLng position = LatLng(loc.latitude, loc.longitude);
          
          // Only include locations within Bangladesh bounds
          if (_isWithinBangladesh(position)) {
            String cleanAddress = await _getCleanAddressFromLatLng(position);
            
            // Avoid duplicates
            bool isDuplicate = suggestions.any((s) => 
              (s.address.toLowerCase() == cleanAddress.toLowerCase()) ||
              (Geolocator.distanceBetween(
                s.position.latitude, s.position.longitude,
                position.latitude, position.longitude
              ) < 100) // Less than 100 meters apart
            );
            
            if (!isDuplicate && cleanAddress.isNotEmpty) {
              suggestions.add(LocationSuggestion(
                address: cleanAddress,
                position: position,
                type: _getSuggestionType(cleanAddress)
              ));
            }
          }
        }
      } catch (e) {
        print('Search error for "$searchQuery": $e');
        continue;
      }
    }

    // Remove duplicates and limit results
    List<LocationSuggestion> uniqueSuggestions = [];
    for (LocationSuggestion suggestion in suggestions) {
      bool isDuplicate = uniqueSuggestions.any((s) => 
        s.address.toLowerCase() == suggestion.address.toLowerCase()
      );
      if (!isDuplicate) {
        uniqueSuggestions.add(suggestion);
      }
    }

    // Sort by relevance (exact matches first, then partial matches)
    uniqueSuggestions.sort((a, b) {
      String queryLower = query.toLowerCase();
      bool aExact = a.address.toLowerCase().startsWith(queryLower);
      bool bExact = b.address.toLowerCase().startsWith(queryLower);
      
      if (aExact && !bExact) return -1;
      if (!aExact && bExact) return 1;
      return a.address.length.compareTo(b.address.length);
    });

    setState(() {
      if (isFrom) {
        _fromSuggestions = uniqueSuggestions.take(8).toList();
        _isSearchingFrom = false;
      } else {
        _toSuggestions = uniqueSuggestions.take(8).toList();
        _isSearchingTo = false;
      }
    });
  } catch (e) {
    setState(() {
      if (isFrom) {
        _fromSuggestions = [];
        _isSearchingFrom = false;
      } else {
        _toSuggestions = [];
        _isSearchingTo = false;
      }
    });
    print('Error searching places: $e');
    }
  }

  Future<String> _getCleanAddressFromLatLng(LatLng position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        List<String> addressParts = [];
        
        if (place.name != null && place.name!.isNotEmpty && !_isRoadCode(place.name!)) addressParts.add(place.name!);
        if (place.locality != null && place.locality!.isNotEmpty) addressParts.add(place.locality!);
        if (place.subAdministrativeArea != null && place.subAdministrativeArea!.isNotEmpty) addressParts.add(place.subAdministrativeArea!);
        if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) addressParts.add(place.administrativeArea!);
        
        return addressParts.join(', ');
      }
    } catch (e) {
      print('Error getting clean address: $e');
    }
    return '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
  }

  bool _isRoadCode(String name) => RegExp(r'^[A-Z0-9\-]+$').hasMatch(name) || name.length < 3 || name.contains(RegExp(r'\d{3,}'));

  List<LocationSuggestion> _getBangladeshLocationSuggestions(String query) {
    return _bangladeshLocations.entries
        .where((entry) => entry.key.toLowerCase().contains(query.toLowerCase()))
        .map((entry) => LocationSuggestion(address: entry.key, position: entry.value, type: SuggestionType.city))
        .toList();
  }

  SuggestionType _getSuggestionType(String address) {
    if (address.contains('Airport')) return SuggestionType.airport;
    if (address.contains('Station') || address.contains('Terminal')) return SuggestionType.transport;
    if (address.contains('Hospital')) return SuggestionType.hospital;
    if (address.contains('University') || address.contains('College')) return SuggestionType.education;
    return SuggestionType.general;
  }
  Future<void> _getVehicleRoute() async {
    if (_startPosition == null || _destinationPosition == null) return;
    
    setState(() => _isLoadingRoute = true);
    
    try {
      List<LatLng> routePoints = [];
      
      switch (_selectedVehicleType) {
        case 'Bus':
          routePoints = await _getBusRoute(_startPosition!, _destinationPosition!);
          break;
        case 'Train':
          routePoints = await _getTrainRoute(_startPosition!, _destinationPosition!);
          break;
        case 'Air':
          routePoints = await _getAirRoute(_startPosition!, _destinationPosition!);
          break;
        case 'Ferry':
          routePoints = await _getFerryRoute(_startPosition!, _destinationPosition!);
          break;
      }
      
      if (routePoints.isNotEmpty) {
        setState(() {
          _polylines = {
            Polyline(
              polylineId: PolylineId('vehicle_route'),
              points: routePoints,
              color: _getVehicleColor(_selectedVehicleType),
              width: 5,
              patterns: _getVehiclePattern(_selectedVehicleType),
            ),
          };
        });
      }
    } catch (e) {
      print('Error getting vehicle route: $e');
    } finally {
      setState(() => _isLoadingRoute = false);
    }
  }

  List<PatternItem> _getVehiclePattern(String vehicleType) {
    switch (vehicleType) {
      case 'Bus': return [PatternItem.dash(15), PatternItem.gap(5)];
      case 'Train': return [PatternItem.dash(20), PatternItem.gap(10)];
      case 'Air': return [PatternItem.dot, PatternItem.gap(8)];
      case 'Ferry': return [PatternItem.dash(10), PatternItem.gap(5), PatternItem.dot, PatternItem.gap(5)];
      default: return [PatternItem.dash(10)];
    }
  }

  Future<List<LatLng>> _getBusRoute(LatLng start, LatLng destination) async {
    const String apiKey = 'AIzaSyD9By6x8PGV02Tj_yT2-6nZzD7S113PaYY';
    final String url = 'https://maps.googleapis.com/maps/api/directions/json?origin=${start.latitude},${start.longitude}&destination=${destination.latitude},${destination.longitude}&mode=transit&transit_mode=bus&region=bd&key=$apiKey';
    
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'].isNotEmpty) {
          String encodedPoints = data['routes'][0]['overview_polyline']['points'];
          return _decodePolyline(encodedPoints);
        }
      }
    } catch (e) {
      print('Error getting bus route: $e');
    }
    
    return [start, destination];
  }

  Future<List<LatLng>> _getTrainRoute(LatLng start, LatLng destination) async {
    if (_selectedTrainRoute != null) {
      return _selectedTrainRoute!.stations.map((station) => station.position).toList();
    }
    
    String startName = await _getAddressFromLatLng(start);
    String destName = await _getAddressFromLatLng(destination);
    
    List<TrainRoute> possibleTrains = _trainService.getTrainsBetween(startName, destName);
    
    if (possibleTrains.isNotEmpty) {
      TrainRoute selectedTrain = possibleTrains.first;
      List<TrainStation> routeStations = selectedTrain.getStationsBetween(startName, destName);
      return routeStations.map((station) => station.position).toList();
    }
    
    List<LatLng> railwayStations = [
      LatLng(23.8103, 90.4125), LatLng(22.3569, 91.7832), LatLng(24.8949, 91.8687),
      LatLng(24.3745, 88.6042), LatLng(23.1665, 89.2081), LatLng(24.2513, 89.9167),
    ];
    
    LatLng nearestStartStation = _findNearestStation(start, railwayStations);
    LatLng nearestDestStation = _findNearestStation(destination, railwayStations);
    
    if (nearestStartStation != nearestDestStation) {
      return [start, nearestStartStation, nearestDestStation, destination];
    }
    
    return [start, destination];
  }

  Future<List<LatLng>> _getAirRoute(LatLng start, LatLng destination) async {
    List<LatLng> airports = [
      LatLng(23.8433, 90.3978), LatLng(22.2496, 91.8093), LatLng(24.9633, 91.8673), LatLng(21.4522, 92.0093),
    ];
    
    LatLng nearestStartAirport = _findNearestStation(start, airports);
    LatLng nearestDestAirport = _findNearestStation(destination, airports);
    
    if (nearestStartAirport != nearestDestAirport) {
      return _createFlightPath(nearestStartAirport, nearestDestAirport);
    }
    
    return [start, destination];
  }

  Future<List<LatLng>> _getFerryRoute(LatLng start, LatLng destination) async {
    List<LatLng> ferryTerminals = [
      LatLng(23.6238, 90.4990), LatLng(22.7010, 90.3535), LatLng(23.1665, 89.2081),
      LatLng(22.8456, 89.5403), LatLng(23.9013, 89.1205),
    ];
    
    LatLng nearestStartTerminal = _findNearestStation(start, ferryTerminals);
    LatLng nearestDestTerminal = _findNearestStation(destination, ferryTerminals);
    
    if (nearestStartTerminal != nearestDestTerminal) {
      return _createWaterwayPath(nearestStartTerminal, nearestDestTerminal);
    }
    
    return [start, destination];
  }

  LatLng _findNearestStation(LatLng position, List<LatLng> stations) {
    double minDistance = double.infinity;
    LatLng nearest = stations.first;
    
    for (LatLng station in stations) {
      double distance = Geolocator.distanceBetween(position.latitude, position.longitude, station.latitude, station.longitude);
      if (distance < minDistance) {
        minDistance = distance;
        nearest = station;
      }
    }
    
    return nearest;
  }

  List<LatLng> _createFlightPath(LatLng start, LatLng end) {
    List<LatLng> path = [];
    int steps = 20;
    
    for (int i = 0; i <= steps; i++) {
      double ratio = i / steps;
      double lat = start.latitude + (end.latitude - start.latitude) * ratio;
      double lng = start.longitude + (end.longitude - start.longitude) * ratio;
      
      double curve = math.sin(ratio * math.pi) * 0.5;
      lat += curve;
      
      path.add(LatLng(lat, lng));
    }
    
    return path;
  }

  List<LatLng> _createWaterwayPath(LatLng start, LatLng end) {
    List<LatLng> path = [];
    int steps = 15;
    
    for (int i = 0; i <= steps; i++) {
      double ratio = i / steps;
      double lat = start.latitude + (end.latitude - start.latitude) * ratio;
      double lng = start.longitude + (end.longitude - start.longitude) * ratio;
      
      double zigzag = math.sin(ratio * math.pi * 4) * 0.01;
      lng += zigzag;
      
      path.add(LatLng(lat, lng));
    }
    
    return path;
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> polyline = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      polyline.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return polyline;
  }

  void _updateMarkers() {
    Set<Marker> markers = {};
    
    if (_startPosition != null) {
      markers.add(Marker(
        markerId: MarkerId('start'),
        position: _startPosition!,
        infoWindow: InfoWindow(title: 'Start Location', snippet: 'Starting point'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ));
    }
    
    if (_destinationPosition != null) {
      markers.add(Marker(
        markerId: MarkerId('destination'),
        position: _destinationPosition!,
        infoWindow: InfoWindow(title: 'Destination', snippet: 'End point'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ));
    }
    
    markers.add(Marker(
      markerId: MarkerId('current'),
      position: _currentPosition,
      infoWindow: InfoWindow(title: 'Current Location'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
    ));
    
    if (_selectedVehicleType == 'Train' && _selectedTrainRoute != null) {
      for (int i = 0; i < _selectedTrainRoute!.stations.length; i++) {
        TrainStation station = _selectedTrainRoute!.stations[i];
        markers.add(Marker(
          markerId: MarkerId('train_station_$i'),
          position: station.position,
          infoWindow: InfoWindow(
            title: station.name,
            snippet: 'Arrival: ${_trainService.formatTime(station.arrivalTime)}\nDeparture: ${_trainService.formatTime(station.departureTime)}',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        ));
      }
    }
    
    setState(() => _markers = markers);
    _getVehicleRoute();
  }

  Future<String> _getAddressFromLatLng(LatLng position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        List<String> addressParts = [];
        if (place.name != null && place.name!.isNotEmpty) addressParts.add(place.name!);
        if (place.street != null && place.street!.isNotEmpty && place.street != place.name) addressParts.add(place.street!);
        if (place.locality != null && place.locality!.isNotEmpty) addressParts.add(place.locality!);
        if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) addressParts.add(place.administrativeArea!);
        if (place.country != null && place.country!.isNotEmpty) addressParts.add(place.country!);
        return addressParts.join(', ');
      }
    } catch (e) {
      print('Error getting address: $e');
    }
    return '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
  }

  Future<void> _selectLocationFromSuggestion(LocationSuggestion suggestion, bool isStart) async {
    setState(() {
      if (isStart) {
        _startPosition = suggestion.position;
        _fromController.text = suggestion.address;
        _showFromSuggestions = false;
        _fromFocusNode.unfocus();
      } else {
        _destinationPosition = suggestion.position;
        _toController.text = suggestion.address;
        _showToSuggestions = false;
        _toFocusNode.unfocus();
      }
    });
    _updateMarkers();
    _updateCameraPosition(suggestion.position);
  }

  void _selectTrainRoute(TrainRoute trainRoute) {
    setState(() {
      _selectedTrainRoute = trainRoute;
      _vehicleNameController.text = trainRoute.trainName;
      _vehicleNumberController.text = trainRoute.trainNumber;
      
      if (trainRoute.stations.isNotEmpty) {
        TrainStation firstStation = trainRoute.stations.first;
        TrainStation lastStation = trainRoute.stations.last;
        
        _startPosition = firstStation.position;
        _destinationPosition = lastStation.position;
        _fromController.text = firstStation.name;
        _toController.text = lastStation.name;
        
        Duration journeyTime = trainRoute.getJourneyTime(firstStation.name, lastStation.name);
        _selectedHours = journeyTime.inHours;
        _selectedMinutes = journeyTime.inMinutes.remainder(60);
      }
      
      _showTrainRoutes = false;
    });
    _updateMarkers();
    
    if (_startPosition != null && _destinationPosition != null) {
      _fitMarkersInView();
    }
  }

  void _updateCameraPosition(LatLng position) {
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(position, 15));
  }

  void _onMapTap(LatLng position) async {
    if (!_isWithinBangladesh(position)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select location within Bangladesh'), backgroundColor: Colors.red),
      );
      return;
    }
    
    String address = await _getAddressFromLatLng(position);
    
    setState(() {
      if (_isSettingStart) {
        _startPosition = position;
        _fromController.text = address;
        _isSettingStart = false;
      } else if (_isSettingDestination) {
        _destinationPosition = position;
        _toController.text = address;
        _isSettingDestination = false;
      }
    });
    _updateMarkers();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_isSettingStart || _isSettingDestination ? "Location" : "Location"} set successfully'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _fitMarkersInView() {
    if (_startPosition != null && _destinationPosition != null) {
      LatLngBounds bounds = LatLngBounds(
        southwest: LatLng(
          math.min(_startPosition!.latitude, _destinationPosition!.latitude),
          math.min(_startPosition!.longitude, _destinationPosition!.longitude),
        ),
        northeast: LatLng(
          math.max(_startPosition!.latitude, _destinationPosition!.latitude),
          math.max(_startPosition!.longitude, _destinationPosition!.longitude),
        ),
      );
      _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
    }
  }
  void _swapLocations() {
    if (_startPosition != null && _destinationPosition != null) {
      String tempText = _fromController.text;
      LatLng tempPosition = _startPosition!;
      
      setState(() {
        _fromController.text = _toController.text;
        _toController.text = tempText;
        _startPosition = _destinationPosition;
        _destinationPosition = tempPosition;
      });
      _updateMarkers();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Locations swapped!'), duration: Duration(seconds: 1), backgroundColor: _getVehicleColor(_selectedVehicleType)),
      );
    }
  }

  void _openFullMap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text('Select Location - ${_selectedVehicleType}'),
            backgroundColor: _getVehicleColor(_selectedVehicleType),
            foregroundColor: Colors.white,
            actions: [
              if (_startPosition != null && _destinationPosition != null)
                IconButton(icon: Icon(Icons.zoom_out_map), onPressed: _fitMarkersInView),
            ],
          ),
          body: Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(target: _currentPosition, zoom: 12),
                onMapCreated: (controller) {
                  _mapController = controller;
                  controller.setMapStyle('''[{"featureType": "administrative.country","elementType": "geometry","stylers": [{"visibility": "on"}]}]''');
                },
                onTap: _onMapTap,
                markers: _markers,
                polylines: _polylines,
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                mapType: MapType.normal,
                minMaxZoomPreference: MinMaxZoomPreference(6, 18),
                cameraTargetBounds: CameraTargetBounds(bangladeshBounds),
                gestureRecognizers: Set()..add(Factory<PanGestureRecognizer>(() => PanGestureRecognizer())),
              ),
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: Container(
                  padding: EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _isSettingStart = !_isSettingStart;
                                  _isSettingDestination = false;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(_isSettingStart ? 'Tap on map to set start location' : 'Start location setting cancelled'), duration: Duration(seconds: 1)),
                                );
                              },
                              icon: Icon(Icons.play_arrow, size: 16),
                              label: Text('Set Start'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isSettingStart ? Colors.green : Colors.grey.shade300,
                                foregroundColor: _isSettingStart ? Colors.white : Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _isSettingDestination = !_isSettingDestination;
                                  _isSettingStart = false;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(_isSettingDestination ? 'Tap on map to set destination' : 'Destination setting cancelled'), duration: Duration(seconds: 1)),
                                );
                              },
                              icon: Icon(Icons.stop, size: 16),
                              label: Text('Set Destination'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isSettingDestination ? Colors.red : Colors.grey.shade300,
                                foregroundColor: _isSettingDestination ? Colors.white : Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_startPosition != null && _destinationPosition != null) ...[
                        SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: _swapLocations,
                          icon: Icon(Icons.swap_vert, size: 16),
                          label: Text('Swap Locations'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _getVehicleColor(_selectedVehicleType),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                      if (_isLoadingRoute) ...[
                        SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(_getVehicleColor(_selectedVehicleType)))),
                            SizedBox(width: 8),
                            Text('Finding ${_selectedVehicleType.toLowerCase()} route...', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: _startPosition != null && _destinationPosition != null
              ? FloatingActionButton(
                  onPressed: () {
                    _fitMarkersInView();
                    Navigator.pop(context);
                  },
                  backgroundColor: _getVehicleColor(_selectedVehicleType),
                  child: Icon(Icons.check, color: Colors.white),
                )
              : null,
        ),
      ),
    );
  }

  void _startLocationUpdates() {
    _locationUpdateTimer = Timer.periodic(Duration(seconds: 10), (timer) async {
      try {
        Position position = await Geolocator.getCurrentPosition();
        LatLng newPosition = LatLng(position.latitude, position.longitude);
        
        if (_isWithinBangladesh(newPosition)) {
          setState(() => _currentPosition = newPosition);
          _updateMarkers();
          
          if (_locationShareId != null) {
            await _database.child('shared_locations').child(_locationShareId!).update({
              'currentLat': newPosition.latitude,
              'currentLng': newPosition.longitude,
              'lastUpdated': DateTime.now().millisecondsSinceEpoch,
            });
          }
        }
      } catch (e) {
        print('Error updating location: $e');
      }
    });
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate() || !_validateEstimatedTime()) {
      if (!_validateEstimatedTime()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please select estimated time'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    if (_startPosition == null || _destinationPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select start and destination points'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final locationData = {
        'vehicleType': _selectedVehicleType,
        'vehicleName': _vehicleNameController.text.trim(),
        'vehicleNumber': _vehicleNumberController.text.trim(),
        'from': _fromController.text.trim(),
        'to': _toController.text.trim(),
        'estimatedHours': _selectedHours,
        'estimatedMinutes': _selectedMinutes,
        'shareType': _shareType,
        'password': _shareType == 'Public' ? _passwordController.text : null,
        'passkey': _shareType == 'Private' ? _generatedPasskey : null,
        'description': _descriptionController.text.trim(),
        'startLat': _startPosition!.latitude,
        'startLng': _startPosition!.longitude,
        'destLat': _destinationPosition!.latitude,
        'destLng': _destinationPosition!.longitude,
        'currentLat': _currentPosition.latitude,
        'currentLng': _currentPosition.longitude,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        'status': 'active',
        'trainRoute': _selectedTrainRoute != null ? {
          'trainName': _selectedTrainRoute!.trainName,
          'trainNumber': _selectedTrainRoute!.trainNumber,
          'stations': _selectedTrainRoute!.stations.map((station) => {
            'name': station.name,
            'code': station.code,
            'lat': station.position.latitude,
            'lng': station.position.longitude,
            'arrivalTime': station.arrivalTime.millisecondsSinceEpoch,
            'departureTime': station.departureTime.millisecondsSinceEpoch,
          }).toList(),
        } : null,
      };

      DatabaseReference ref = await _database.child('shared_locations').push();
      await ref.set(locationData);
      _locationShareId = ref.key;
      
      _startLocationUpdates();
      
      setState(() => _isLoading = false);
      _showSuccessDialog();
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorDialog();
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(_getVehicleIcon(_selectedVehicleType), color: Colors.green, size: 50),
            ),
            SizedBox(height: 20),
            Text('${_selectedVehicleType} Location Shared!', 
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                textAlign: TextAlign.center),
            SizedBox(height: 10),
            if (_shareType == 'Private') ...[
              Container(
                padding: EdgeInsets.all(15),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                child: Column(
                  children: [
                    Text('Your Private Passkey:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    SizedBox(height: 8),
                    SelectableText(_generatedPasskey, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.blue)),
                    SizedBox(height: 8),
                    Text('Share this key with viewers', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              SizedBox(height: 20),
            ],
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showErrorDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(Icons.error, color: Colors.red, size: 50),
            ),
            SizedBox(height: 20),
            Text('Submission Failed!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red), textAlign: TextAlign.center),
            SizedBox(height: 10),
            Text('Please try again.', style: TextStyle(fontSize: 14, color: Colors.grey.shade600), textAlign: TextAlign.center),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(_getVehicleIcon(_selectedVehicleType), color: Colors.white),
            SizedBox(width: 8),
            Text('Share ${_selectedVehicleType} Location'),
          ],
        ),
        backgroundColor: _getVehicleColor(_selectedVehicleType),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_getVehicleColor(_selectedVehicleType), _getVehicleColor(_selectedVehicleType).withOpacity(0.1)],
          ),
        ),
        child: AnimatedBuilder(
          animation: _slideAnimation,
          builder: (context, child) => Transform.translate(
            offset: Offset(_slideAnimation.value * 300, 0),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Vehicle Type'),
                    _buildVehicleTypeSelector(),
                    SizedBox(height: 20),
                    _buildSectionTitle('Vehicle Information'),
                    _buildInputCard([
                      _buildTextFormField(_vehicleNameController, 'Vehicle Name', _getVehicleIcon(_selectedVehicleType), (v) => v?.isEmpty ?? true ? 'Vehicle name is required' : null),
                      SizedBox(height: 15),
                      _buildTextFormField(_vehicleNumberController, 'Vehicle Number', Icons.confirmation_number, (v) => v?.isEmpty ?? true ? 'Vehicle number is required' : null),
                    ]),
                    SizedBox(height: 20),
                    if (_selectedVehicleType == 'Train') ...[
                      _buildSectionTitle('Train Route Information'),
                      _buildTrainRouteSection(),
                      SizedBox(height: 20),
                    ],
                    _buildSectionTitle('Route Information'),
                    _buildEnhancedRouteSection(),
                    SizedBox(height: 20),
                    _buildSectionTitle('Interactive Bangladesh Map'),
                    _buildEnhancedMapSection(),
                    SizedBox(height: 20),
                    _buildSectionTitle('Sharing Options'),
                    _buildShareTypeSelector(),
                    SizedBox(height: 20),
                    if (_shareType == 'Public') _buildPasswordSection(),
                    if (_shareType == 'Private') _buildPasskeySection(),
                    SizedBox(height: 20),
                    _buildSectionTitle('Description (Optional)'),
                    _buildInputCard([_buildTextFormField(_descriptionController, 'Additional Information', Icons.description, null, 3)]),
                    SizedBox(height: 30),
                    _buildSubmitButton(),
                    SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrainRouteSection() => _buildInputCard([
    TextFormField(
      decoration: InputDecoration(
        labelText: 'Search Train Routes',
        hintText: 'Enter train name or route',
        prefixIcon: Icon(Icons.train, color: _getVehicleColor(_selectedVehicleType)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _getVehicleColor(_selectedVehicleType), width: 2)),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
      onChanged: (query) => _searchTrainRoutes(query, true),
    ),
    
    if (_showTrainRoutes && _availableTrains.isNotEmpty) ...[
      SizedBox(height: 15),
      Container(
        height: 200,
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _getVehicleColor(_selectedVehicleType).withOpacity(0.1),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(9), topRight: Radius.circular(9)),
              ),
              child: Row(
                children: [
                  Icon(Icons.train, color: _getVehicleColor(_selectedVehicleType), size: 18),
                  SizedBox(width: 8),
                  Text('Available Train Routes', style: TextStyle(fontWeight: FontWeight.w600, color: _getVehicleColor(_selectedVehicleType))),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: _availableTrains.length,
                separatorBuilder: (context, index) => Divider(height: 1),
                itemBuilder: (context, index) {
                  final train = _availableTrains[index];
                  final isSelected = _selectedTrainRoute?.trainNumber == train.trainNumber;
                  
                  return Container(
                    color: isSelected ? _getVehicleColor(_selectedVehicleType).withOpacity(0.1) : null,
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: isSelected ? _getVehicleColor(_selectedVehicleType) : Colors.grey.shade300,
                        child: Text(train.trainNumber, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.grey.shade600)),
                      ),
                      title: Text(train.trainName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isSelected ? _getVehicleColor(_selectedVehicleType) : null)),
                      subtitle: Text('${train.stations.first.name} → ${train.stations.last.name}', style: TextStyle(fontSize: 12)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(train.type, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: _getVehicleColor(_selectedVehicleType))),
                          Text(_trainService.formatDuration(train.getJourneyTime(train.stations.first.name, train.stations.last.name)), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                        ],
                      ),
                      onTap: () => _selectTrainRoute(train),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ],
    
    if (_selectedTrainRoute != null) ...[
      SizedBox(height: 15),
      Container(
        padding: EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: _getVehicleColor(_selectedVehicleType).withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _getVehicleColor(_selectedVehicleType).withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.train, color: _getVehicleColor(_selectedVehicleType)),
                SizedBox(width: 8),
                Expanded(child: Text('${_selectedTrainRoute!.trainName} (${_selectedTrainRoute!.trainNumber})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                Chip(label: Text(_selectedTrainRoute!.type, style: TextStyle(fontSize: 10)), backgroundColor: _getVehicleColor(_selectedVehicleType).withOpacity(0.2)),
              ],
            ),
            SizedBox(height: 10),
            Text('Stations (${_selectedTrainRoute!.stations.length}):', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 5),
            Container(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedTrainRoute!.stations.length,
                itemBuilder: (context, index) {
                  final station = _selectedTrainRoute!.stations[index];
                  final isFirst = index == 0;
                  final isLast = index == _selectedTrainRoute!.stations.length - 1;
                  
                  return Container(
                    width: 120,
                    margin: EdgeInsets.only(right: 10),
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isFirst ? Colors.green : isLast ? Colors.red : Colors.grey.shade300, width: isFirst || isLast ? 2 : 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(station.name.split('(')[0].trim(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                        SizedBox(height: 2),
                        Text(station.code, style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
                        Spacer(),
                        Text('Arr: ${_trainService.formatTime(station.arrivalTime)}', style: TextStyle(fontSize: 9, color: Colors.blue)),
                        Text('Dep: ${_trainService.formatTime(station.departureTime)}', style: TextStyle(fontSize: 9, color: Colors.orange)),
                      ],
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Journey Time: ${_trainService.formatDuration(_selectedTrainRoute!.getJourneyTime(_selectedTrainRoute!.stations.first.name, _selectedTrainRoute!.stations.last.name))}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                TextButton(onPressed: () => setState(() => _selectedTrainRoute = null), child: Text('Clear Selection', style: TextStyle(color: Colors.red, fontSize: 12))),
              ],
            ),
          ],
        ),
      ),
    ],
  ]);

  Widget _buildEnhancedRouteSection() => _buildInputCard([
    Stack(
      children: [
        Column(
          children: [
            _buildSearchField(_fromController, _fromFocusNode, 'From Location', Icons.my_location, true, (v) => v?.isEmpty ?? true ? 'Starting location is required' : null),
            SizedBox(height: 15),
            _buildSearchField(_toController, _toFocusNode, 'To Location', Icons.location_on, false, (v) => v?.isEmpty ?? true ? 'Destination is required' : null),
            SizedBox(height: 15),
            _buildEstimatedTimeSelector(),
          ],
        ),
        if (_showFromSuggestions && _fromSuggestions.isNotEmpty)
          Positioned(
            top: 55,
            left: 0,
            right: 0,
            child: _buildSuggestionsList(_fromSuggestions, true),
          ),
        if (_showToSuggestions && _toSuggestions.isNotEmpty)
          Positioned(
            top: 125,
            left: 0,
            right: 0,
            child: _buildSuggestionsList(_toSuggestions, false),
          ),
      ],
    ),
    if (_startPosition != null && _destinationPosition != null) ...[
      SizedBox(height: 15),
      Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 20),
            SizedBox(width: 8),
            Expanded(child: Text('Route selected on map', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w500, fontSize: 14))),
            TextButton(onPressed: _swapLocations, child: Text('Swap', style: TextStyle(fontSize: 12))),
          ],
        ),
      ),
    ],
  ]);

  Widget _buildSearchField(TextEditingController controller, FocusNode focusNode, String label, IconData icon, bool isFrom, String? Function(String?)? validator) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: _getVehicleColor(_selectedVehicleType)),
        suffixIcon: controller.text.isNotEmpty ? IconButton(icon: Icon(Icons.clear, color: Colors.grey), onPressed: () => controller.clear()) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _getVehicleColor(_selectedVehicleType), width: 2)),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
      onTap: () => setState(() {
        if (isFrom) _showToSuggestions = false;
        else _showFromSuggestions = false;
      }),
    );
  }

  Widget _buildSuggestionsList(List<LocationSuggestion> suggestions, bool isFrom) {
    return Container(
      constraints: BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.symmetric(vertical: 8),
        itemCount: suggestions.length,
        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade100),
        itemBuilder: (context, index) {
          final suggestion = suggestions[index];
          return ListTile(
            leading: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _getSuggestionColor(suggestion.type).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_getSuggestionIcon(suggestion.type), size: 18, color: _getSuggestionColor(suggestion.type)),
            ),
            title: Text(suggestion.address, style: TextStyle(fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(_getSuggestionTypeLabel(suggestion.type), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            onTap: () => _selectLocationFromSuggestion(suggestion, isFrom),
          );
        },
      ),
    );
  }

  Widget _buildEnhancedMapSection() => Container(
    height: 350,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(15),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: Offset(0, 5))],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            color: _getVehicleColor(_selectedVehicleType).withOpacity(0.9),
            child: Row(
              children: [
                Icon(_getVehicleIcon(_selectedVehicleType), color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(child: Text('Tap on map to select locations', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500))),
                GestureDetector(
                  onTap: _openFullMap,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fullscreen, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text('Full Map', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
                if (_startPosition != null && _destinationPosition != null) ...[
                  SizedBox(width: 8),
                  GestureDetector(
                    onTap: _fitMarkersInView,
                    child: Container(
                      padding: EdgeInsets.all(5),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(5)),
                      child: Icon(Icons.zoom_out_map, color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: _currentPosition, zoom: 11),
              onMapCreated: (controller) {
                _mapController = controller;
                setState(() => _isMapReady = true);
              },
              onTap: _onMapTap,
              markers: _markers,
              polylines: _polylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              mapType: MapType.normal,
              zoomControlsEnabled: false,
              minMaxZoomPreference: MinMaxZoomPreference(6, 18),
              cameraTargetBounds: CameraTargetBounds(bangladeshBounds),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildSectionTitle(String title) => Padding(
    padding: EdgeInsets.only(bottom: 10),
    child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
  );

  Widget _buildInputCard(List<Widget> children) => Container(
    padding: EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: Offset(0, 5))],
    ),
    child: Column(children: children),
  );

  Widget _buildTextFormField(TextEditingController controller, String label, IconData icon, String? Function(String?)? validator, [int maxLines = 1, bool obscureText = false, Widget? suffixIcon]) => TextFormField(
    controller: controller,
    validator: validator,
    maxLines: maxLines,
    obscureText: obscureText,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _getVehicleColor(_selectedVehicleType)),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _getVehicleColor(_selectedVehicleType), width: 2)),
      filled: true,
      fillColor: Colors.grey.shade50,
    ),
  );

  Widget _buildEstimatedTimeSelector() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(Icons.access_time, color: _getVehicleColor(_selectedVehicleType)),
          SizedBox(width: 10),
          Text('Estimated Time', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey.shade700)),
        ],
      ),
      SizedBox(height: 15),
      Row(
        children: [
          Expanded(child: _buildDropdown(_selectedHours, 'Hours', List.generate(25, (i) => i), (v) => setState(() => _selectedHours = v ?? 0))),
          SizedBox(width: 15),
          Expanded(child: _buildDropdown(_selectedMinutes, 'Minutes', [0, 15, 30, 45], (v) => setState(() => _selectedMinutes = v ?? 0))),
        ],
      ),
      if (_getFormattedTime().isNotEmpty) ...[
        SizedBox(height: 10),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _getVehicleColor(_selectedVehicleType).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _getVehicleColor(_selectedVehicleType).withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule, size: 16, color: _getVehicleColor(_selectedVehicleType)),
              SizedBox(width: 5),
              Text('Selected: ${_getFormattedTime()}', style: TextStyle(color: _getVehicleColor(_selectedVehicleType), fontWeight: FontWeight.w500, fontSize: 12)),
            ],
          ),
        ),
      ],
    ],
  );

  Widget _buildDropdown(int value, String hint, List<int> items, Function(int?) onChanged) => Container(
    padding: EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10), color: Colors.grey.shade50),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: value,
        hint: Text(hint),
        isExpanded: true,
        items: items.map((item) => DropdownMenuItem<int>(value: item, child: Text('$item ${hint.toLowerCase()}'))).toList(),
        onChanged: onChanged,
      ),
    ),
  );

  Widget _buildVehicleTypeSelector() => Container(
    height: 80,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: _vehicleTypes.length,
      itemBuilder: (context, index) {
        String type = _vehicleTypes[index];
        bool isSelected = _selectedVehicleType == type;
        return GestureDetector(
          onTap: () => setState(() {
            _selectedVehicleType = type;
            if (type != 'Train') {
              _selectedTrainRoute = null;
              _showTrainRoutes = false;
            }
          }),
          child: Container(
            width: 100,
            margin: EdgeInsets.only(right: 15),
            decoration: BoxDecoration(
              color: isSelected ? _getVehicleColor(type) : Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: isSelected ? _getVehicleColor(type) : Colors.grey.shade300, width: 2),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: Offset(0, 3))],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_getVehicleIcon(type), color: isSelected ? Colors.white : _getVehicleColor(type), size: 28),
                SizedBox(height: 8),
                Text(type, style: TextStyle(color: isSelected ? Colors.white : _getVehicleColor(type), fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _buildShareTypeSelector() => _buildInputCard([
    DropdownButtonFormField<String>(
      value: _shareType,
      decoration: InputDecoration(
        labelText: 'Share Type',
        prefixIcon: Icon(Icons.security, color: _getVehicleColor(_selectedVehicleType)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _getVehicleColor(_selectedVehicleType), width: 2)),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
      items: _shareTypes.map((type) => DropdownMenuItem<String>(
        value: type,
        child: Row(
          children: [
            Icon(type == 'Public' ? Icons.public : Icons.lock, size: 18, color: _getVehicleColor(_selectedVehicleType)),
            SizedBox(width: 8),
            Text(type),
          ],
        ),
      )).toList(),
      onChanged: (value) => setState(() {
        _shareType = value!;
        if (_shareType == 'Private') _generatePasskey();
      }),
    ),
  ]);

  Widget _buildPasswordSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _buildSectionTitle('Password Protection'),
      _buildInputCard([
        _buildTextFormField(
          _passwordController,
          'Set Password',
          Icons.lock,
          (v) => v?.isEmpty ?? true ? 'Password is required for public sharing' : v!.length < 6 ? 'Password must be at least 6 characters' : null,
          1,
          !_isPasswordVisible,
          IconButton(
            icon: Icon(_isPasswordVisible ? Icons.visibility : Icons.visibility_off, color: _getVehicleColor(_selectedVehicleType)),
            onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
          ),
        ),
      ]),
    ],
  );

  Widget _buildPasskeySection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _buildSectionTitle('Private Passkey'),
      Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [_getVehicleColor(_selectedVehicleType).withOpacity(0.1), _getVehicleColor(_selectedVehicleType).withOpacity(0.05)]),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: _getVehicleColor(_selectedVehicleType).withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.vpn_key, color: _getVehicleColor(_selectedVehicleType)),
                SizedBox(width: 10),
                Text('Auto-Generated Passkey:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              ],
            ),
            SizedBox(height: 15),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_generatedPasskey, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 3, color: _getVehicleColor(_selectedVehicleType))),
                  IconButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _generatedPasskey));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Passkey copied to clipboard!'), backgroundColor: Colors.green));
                    },
                    icon: Icon(Icons.copy, color: _getVehicleColor(_selectedVehicleType)),
                  ),
                ],
              ),
            ),
            SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
                SizedBox(width: 5),
                Expanded(child: Text('Share this passkey with people you want to give access to your location', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
              ],
            ),
          ],
        ),
      ),
    ],
  );

  Widget _buildSubmitButton() => Container(
    width: double.infinity,
    height: 55,
    child: ElevatedButton(
      onPressed: _isLoading ? null : _submitForm,
      style: ElevatedButton.styleFrom(
        backgroundColor: _getVehicleColor(_selectedVehicleType),
        foregroundColor: Colors.white,
        elevation: 8,
        shadowColor: _getVehicleColor(_selectedVehicleType).withOpacity(0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      child: _isLoading
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 20, height: 20, child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white), strokeWidth: 2)),
                SizedBox(width: 15),
                Text('Sharing ${_selectedVehicleType} Location...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_getVehicleIcon(_selectedVehicleType), size: 24),
                SizedBox(width: 10),
                Text('Share ${_selectedVehicleType} Location', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
    ),
  );

  IconData _getSuggestionIcon(SuggestionType type) {
    switch (type) {
      case SuggestionType.city: return Icons.location_city;
      case SuggestionType.airport: return Icons.flight;
      case SuggestionType.transport: return Icons.train;
      case SuggestionType.hospital: return Icons.local_hospital;
      case SuggestionType.education: return Icons.school;
      default: return Icons.place;
    }
  }

  Color _getSuggestionColor(SuggestionType type) {
    switch (type) {
      case SuggestionType.city: return Colors.blue;
      case SuggestionType.airport: return Colors.orange;
      case SuggestionType.transport: return Colors.green;
      case SuggestionType.hospital: return Colors.red;
      case SuggestionType.education: return Colors.purple;
      default: return Colors.grey;
    }
  }

  String _getSuggestionTypeLabel(SuggestionType type) {
    switch (type) {
      case SuggestionType.city: return 'City';
      case SuggestionType.airport: return 'Airport';
      case SuggestionType.transport: return 'Transport Hub';
      case SuggestionType.hospital: return 'Hospital';
      case SuggestionType.education: return 'Educational Institute';
      default: return 'Location';
    }
  }
}

class LocationSuggestion {
  final String address;
  final LatLng position;
  final SuggestionType type;
  final TrainStation? trainStation;

  LocationSuggestion({
    required this.address,
    required this.position,
    required this.type,
    this.trainStation,
  });
}

enum SuggestionType {
  general,
  city,
  airport,
  transport,
  hospital, 
  education,
}