import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'dart:async';
import 'dart:convert';
import 'CustomBar.dart';
import 'database.dart';

var logger = Logger();

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late GoogleMapController mapController;
  final LatLng defaultLocation = const LatLng(37.4878198, 139.9296658);
  final Completer<GoogleMapController> _controller = Completer();
  LatLng? _currentPosition;
  final TextEditingController _searchController = TextEditingController();
  Set<Marker> _markers = {}; // Markers set to show on the map
  final int _selectedIndex = 0;
  double _currentZoom = 15.0;

  @override
  void initState() {
    super.initState();
    _initLocationService();
  }

  Future<void> _initLocationService() async {
    final locationResult = await checkLocationSetting();
    if (locationResult == LocationSettingResult.enabled) {
      await _getCurrentLocation();
    } else {
      await recoverLocationSettings(
          locationResult as BuildContext, context as LocationSettingResult);
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });
      _moveToCurrentLocation();
    } catch (e) {
      logger.w("Error getting location: $e");
    }
  }

  void _moveToCurrentLocation() {
    if (_currentPosition != null) {
      mapController.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _currentPosition!, zoom: 17),
        ),
      );
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
    _controller.complete(controller);
  }

  void _zoomIn() {
    setState(() {
      _currentZoom += 1.0;
    });
    mapController.animateCamera(CameraUpdate.zoomTo(_currentZoom));
  }

  // 縮小機能
  void _zoomOut() {
    setState(() {
      _currentZoom -= 1.0;
    });
    mapController.animateCamera(CameraUpdate.zoomTo(_currentZoom));
  }

  Future<void> _searchAndNavigate() async {
    String searchQuery = _searchController.text.toLowerCase();
    debugPrint("Search Query: $searchQuery"); // Debug: print the search query

    List<String> keywords = [
      'Tsurugajo',
      'Tsurugajo castle',
      'tsurugajo',
      'tsurugajo castle',
      'castle',
      '鶴ヶ城',
      '会津若松城'
    ];

    bool isTsurugajo = keywords.any((keyword) => searchQuery.contains(keyword));
    debugPrint(
        "Is Tsurugajo: $isTsurugajo"); // Debug: print whether it's a Tsurugajo-related search

    final apiKey = 'AIzaSyB3WzJiraDNM_hDGe9M_f1-bjzgSry53nc';
    final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(searchQuery)}&key=$apiKey');

    try {
      final response = await http.get(url);
      debugPrint("Response Body: ${response.body}");
      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Tsurugajo のキーワード検索でマーカーを直接追加
        if (isTsurugajo) {
          setState(() {
            _markers = {
              Marker(
                markerId: MarkerId('Tsurugajo_Marker'),
                position: LatLng(37.5076457, 139.9318131),
                infoWindow: InfoWindow(
                  title: 'Schedule',
                  onTap: _showBusSchedulePopup,
                ),
              ),
            };
            debugPrint("Marker added for Tsurugajo location");
          });

          // Tsurugajo の位置に移動
          mapController.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: LatLng(37.5076457, 139.9318131), zoom: 15),
            ),
          );
        } else if (data['results'].isNotEmpty) {
          final location = data['results'][0]['geometry']['location'];
          LatLng searchedLocation = LatLng(location['lat'], location['lng']);

          debugPrint("Searched Location: $searchedLocation");

          mapController.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: searchedLocation, zoom: 15),
            ),
          );

          setState(() {
            _markers = {};
          });
        } else {
          logger.w("No results found for the search.");
        }
      } else {
        logger.w("Failed to fetch location data.");
      }
    } catch (e) {
      logger.w("Error searching location: $e");
    }
  }

  Future<void> _showBusSchedulePopup() async {
    DatabaseHelper dbHelper = DatabaseHelper.instance;
    List<Map<String, dynamic>> schedule = await dbHelper.getBusSchedule();

    // スケジュールのリストを文字列に変換
    String busTimes =
        schedule.map((item) => item['departureTime'].toString()).join('\n');

    // mountedチェックを追加して、画面がまだ存在していることを確認
    if (!mounted) return;

    showOkAlertDialog(
      context: context,
      title: 'Bus Schedule',
      message: busTimes, // ここにバススケジュールを表示
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search location',
            suffixIcon: IconButton(
              icon: Icon(Icons.search),
              onPressed: _searchAndNavigate,
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: CameraPosition(
              target: _currentPosition ?? defaultLocation,
              zoom: _currentZoom,
            ),
            zoomControlsEnabled: false,
            myLocationEnabled: true,
            onMapCreated: _onMapCreated,
            markers: _markers,
          ),
          Positioned(
            bottom: 80,
            right: 10,
            child: Column(
              children: [
                FloatingActionButton(
                  onPressed: _zoomIn,
                  child: Icon(Icons.zoom_in),
                ),
                SizedBox(height: 10),
                FloatingActionButton(
                  onPressed: _zoomOut,
                  child: Icon(Icons.zoom_out),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: CustomBar(
        selectedIndex: _selectedIndex,
        onTap: (index) {},
      ),
    );
  }
}

enum LocationSettingResult {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  enabled,
}

Future<LocationSettingResult> checkLocationSetting() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    logger.w('Location services are disabled.');
    return LocationSettingResult.serviceDisabled;
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      logger.w('Location permissions are denied.');
      return LocationSettingResult.permissionDenied;
    }
  }

  if (permission == LocationPermission.deniedForever) {
    logger.w('Location permissions are permanently denied.');
    return LocationSettingResult.permissionDeniedForever;
  }

  return LocationSettingResult.enabled;
}

Future<void> recoverLocationSettings(
    BuildContext context, LocationSettingResult locationResult) async {
  if (locationResult == LocationSettingResult.enabled) {
    return;
  }

  final result = await showOkCancelAlertDialog(
    context: context,
    okLabel: 'OK',
    cancelLabel: 'Cancel',
    title: 'Location Settings',
    message: 'Please enable location services or permissions to continue.',
  );

  if (result == OkCancelResult.cancel) {
    logger.w('User canceled recovery of location settings.');
  } else {
    if (locationResult == LocationSettingResult.serviceDisabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}
