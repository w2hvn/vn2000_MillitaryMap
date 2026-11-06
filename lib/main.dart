import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VnGridMapperApp());
}

class VnGridMapperApp extends StatelessWidget {
  const VnGridMapperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bản đồ Tọa độ Quân sự VN-2000',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  
  // Tọa độ khởi tạo mặc định (Cà Mau)
  LatLng _selectedPoint = const LatLng(9.1769, 105.1500);
  double _currentZoom = 13.0;

  // Dữ liệu chuyển đổi
  String _grid4Code = '';
  String _grid9Code = '';
  double _easting = 0.0;
  double _northing = 0.0;
  double _ktt = 105.0;
  int _zoneWidth = 6;
  double _k0 = 0.9996;

  @override
  void initState() {
    super.initState();
    _calculateGrid(_selectedPoint);
  }

  /// Thuật toán chọn Kinh tuyến trục và Múi chiếu
  void _calculateGrid(LatLng point) {
    final double lat = point.latitude;
    final double lon = point.longitude;

    // Xác định tỷ lệ qua mức Zoom bản đồ
    // Zoom >= 14 tương đương tỷ lệ >= 1:25.000 (Múi 6 độ)
    // Zoom < 14 tương đương tỷ lệ < 1:25.000 (Múi 3 độ)
    if (_currentZoom >= 14.0) {
      _zoneWidth = 6;
      _k0 = 0.9996;
      if (lon >= 108.0) {
        _ktt = 111.0;
      } else {
        _ktt = 105.0;
      }
    } else {
      _zoneWidth = 3;
      _k0 = 0.9999;
      if (lon <= 106.5) {
        _ktt = 105.0;
      } else if (lon > 106.5 && lon < 109.5) {
        _ktt = 108.0;
      } else {
        _ktt = 111.0;
      }
    }

    // Khởi tạo hệ tọa độ WGS84 & VN-2000 TM tùy chỉnh theo KTT
    final srcProj = proj4.Projection.get('EPSG:4326') ??
        proj4.Projection.add(
          'EPSG:4326',
          '+proj=longlat +datum=WGS84 +no_defs',
        );

    final destProjDef =
        '+proj=tmerc +lat_0=0 +lon_0=$_ktt +k=$_k0 +x_0=500000 +y_0=0 +ellps=WGS84 +units=m +no_defs';
    final destProj = proj4.Projection.add('VN2000_CUSTOM', destProjDef);

    // Chuyển đổi tọa độ
    final pointSrc = proj4.Point(x: lon, y: lat);
    final pointDest = srcProj.transform(destProj, pointSrc);

    _easting = pointDest.x;   // Trục Y trắc địa (Easting)
    _northing = pointDest.y;  // Trục X trắc địa (Northing)

    // Lấy 2 chữ số km của Easting và Northing (Quy tắc "Dọc trước, Ngang sau")
    final int eKm = (_easting / 1000).floor() % 100;
    final int nKm = (_northing / 1000).floor() % 100;

    final String eKmStr = eKm.toString().padLeft(2, '0');
    final String nKmStr = nKm.toString().padLeft(2, '0');

    // Tọa độ gốc ô 1km
    final double e0 = (_easting / 1000).floor() * 1000.0;
    final double n0 = (_northing / 1000).floor() * 1000.0;

    // Độ lệch trong ô 1km x 1km
    final double dx = _easting - e0;
    final double dy = _northing - n0;

    // Tính Ô 4 (Kích thước 500m x 500m)
    // Hàng trên: [1, 2], Hàng dưới: [4, 3]
    final int col4 = (dx / 500).floor().clamp(0, 1);
    final int row4 = 1 - (dy / 500).floor().clamp(0, 1);
    final matrix4 = [
      [1, 2],
      [4, 3]
    ];
    final int cell4 = matrix4[row4][col4];

    // Tính Ô 9 (Kích thước ~333.33m x 333.33m)
    // Hàng trên: [1, 2, 3], Hàng giữa: [8, 9, 4], Hàng dưới: [7, 6, 5]
    final int col9 = (dx / (1000 / 3)).floor().clamp(0, 2);
    final int row9 = 2 - (dy / (1000 / 3)).floor().clamp(0, 2);
    final matrix9 = [
      [1, 2, 3],
      [8, 9, 4],
      [7, 6, 5]
    ];
    final int cell9 = matrix9[row9][col9];

    setState(() {
      _grid4Code = '$eKmStr $nKmStr $cell4';
      _grid9Code = '$eKmStr $nKmStr $cell9';
    });
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã sao chép $label: $text'),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF1B5E20),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Tọa độ Ô lưới Quân sự',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1B5E20),
        elevation: 4,
      ),
      body: Stack(
        children: [
          // Bản đồ tương tác OpenStreetMap
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selectedPoint,
              initialZoom: _currentZoom,
              onTap: (tapPosition, point) {
                setState(() {
                  _selectedPoint = point;
                });
                _calculateGrid(point);
              },
              onPositionChanged: (position, hasGesture) {
                if (position.zoom != null && position.zoom != _currentZoom) {
                  _currentZoom = position.zoom!;
                  _calculateGrid(_selectedPoint);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.vn2000_grid_mapper',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _selectedPoint,
                    width: 40,
                    height: 40,
                    alignment: Alignment.topCenter,
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.red,
                      size: 40,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Thẻ thông tin nổi phía dưới màn hình
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: Colors.white.withOpacity(0.95),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Hàng chứa 2 ô hiển thị Tọa độ Ô 4 và Ô 9
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _copyToClipboard(_grid4Code, 'Tọa độ Ô 4'),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.shade400, width: 1.5),
                              ),
                              child: Column(
                                children: [
                                  const Text(
                                    'TỌA ĐỘ Ô 4',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _grid4Code,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red.shade900,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () => _copyToClipboard(_grid9Code, 'Tọa độ Ô 9'),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.shade400, width: 1.5),
                              ),
                              child: Column(
                                children: [
                                  const Text(
                                    'TỌA ĐỘ Ô 9',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _grid9Code,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red.shade900,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    // Thông tin chi tiết
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'WGS84: ${_selectedPoint.latitude.toStringAsFixed(6)}°, ${_selectedPoint.longitude.toStringAsFixed(6)}°',
                          style: const TextStyle(fontSize: 12, color: Colors.black80),
                        ),
                        Text(
                          'KTT: $_ktt° (Múi $_zoneWidth°)',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black80),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Trục X (Bắc): ${_northing.toStringAsFixed(1)} m',
                          style: const TextStyle(fontSize: 12, color: Colors.black80),
                        ),
                        Text(
                          'Trục Y (Đông): ${_easting.toStringAsFixed(1)} m',
                          style: const TextStyle(fontSize: 12, color: Colors.black80),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}