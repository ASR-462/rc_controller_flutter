
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() => runApp(const RCControllerApp());

class RCControllerApp extends StatelessWidget {
  const RCControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RC Controller',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1a2a6c),
        colorScheme: ColorScheme.fromSwatch().copyWith(
          secondary: const Color(0xFFb21f1f),
        ),
      ),
      home: const BleControllerScreen(),
    );
  }
}

class BleControllerScreen extends StatefulWidget {
  const BleControllerScreen({super.key});

  @override
  State<BleControllerScreen> createState() => _BleControllerScreenState();
}

class _BleControllerScreenState extends State<BleControllerScreen> {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  late QualifiedCharacteristic _commandChar;
  late QualifiedCharacteristic _sensorChar;
  StreamSubscription<List<int>>? _sensorSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connection;
  bool _isConnected = false;
  bool _emergency = false;
  double _tempLeft = 0.0;
  double _tempRight = 0.0;
  double _currentLeft = 0.0;
  double _currentRight = 0.0;
  int _speed = 150;
  vm.Vector2 _joystickPosition = vm.Vector2.zero();
  bool _isDragging = false;

  // BLE UUIDs
  final Uuid _serviceUuid = Uuid.parse("4fafc201-1fb5-459e-8fcc-c5c9c331914b");
  final Uuid _commandUuid = Uuid.parse("beb5483e-36e1-4688-b7f5-ea07361b26a8");
  final Uuid _sensorUuid = Uuid.parse("cba1d466-344c-4be3-ab3f-189f80dd7518");

  @override
  void dispose() {
    _disconnect();
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      // Пошук пристрою
      final device = await _ble.scanForDevices(
        withServices: [_serviceUuid],
        scanMode: ScanMode.lowLatency,
      ).first;

      // Підключення
      _connection = _ble.connectToDevice(id: device.id).listen((update) {
        if (update.connectionState == DeviceConnectionState.connected) {
          _discoverServices(device.id);
        } else if (update.connectionState == DeviceConnectionState.disconnected) {
          _disconnect();
        }
      });
    } catch (e) {
      _showError("Помилка підключення: ${e.toString()}");
    }
  }

  Future<void> _discoverServices(String deviceId) async {
    try {
      final services = await _ble.discoverServices(deviceId);
      final service = services.firstWhere(
        (s) => s.serviceId == _serviceUuid,
      );

      _commandChar = QualifiedCharacteristic(
        serviceId: service.serviceId,
        characteristicId: _commandUuid,
        deviceId: deviceId,
      );

      _sensorChar = QualifiedCharacteristic(
        serviceId: service.serviceId,
        characteristicId: _sensorUuid,
        deviceId: deviceId,
      );

      // Підписка на дані датчиків
      _sensorSubscription = _ble.subscribeToCharacteristic(_sensorChar).listen(
        (data) {
          try {
            final json = Map<String, dynamic>.from(
              jsonDecode(String.fromCharCodes(data))
            );
            setState(() {
              _tempLeft = json['temp_left']?.toDouble() ?? 0.0;
              _tempRight = json['temp_right']?.toDouble() ?? 0.0;
              _currentLeft = json['current_left']?.toDouble() ?? 0.0;
              _currentRight = json['current_right']?.toDouble() ?? 0.0;
              _emergency = json['emergency'] == true;
            });
          } catch (e) {
            print("Помилка парсингу даних: $e");
          }
        },
        onError: (e) => print("Помилка датчиків: $e"),
      );

      setState(() => _isConnected = true);
    } catch (e) {
      _showError("Помилка сервісів: ${e.toString()}");
    }
  }

  Future<void> _sendCommand(String command) async {
    if (!_isConnected) return;
    try {
      final cmd = command + _speed.toString();
      await _ble.writeCharacteristicWithoutResponse(
        _commandChar,
        value: cmd.codeUnits,
      );
    } catch (e) {
      print("Помилка команди: $e");
    }
  }

  void _disconnect() {
    _sensorSubscription?.cancel();
    _connection?.cancel();
    setState(() {
      _isConnected = false;
      _emergency = false;
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _updateJoystick(Offset localPosition) {
    const double radius = 80.0;
    const double center = radius;
    
    double dx = localPosition.dx - center;
    double dy = localPosition.dy - center;
    final distance = (dx * dx + dy * dy);
    
    if (distance > radius * radius) {
      final angle = atan2(dy, dx);
      dx = cos(angle) * radius;
      dy = sin(angle) * radius;
    }
    
    setState(() {
      _joystickPosition = vm.Vector2(dx, dy);
      _isDragging = true;
    });
    
    // Визначення команди за кутом
    final angle = atan2(dy, dx);
    String command = 'S';
    
    if (distance > 100) {
      if (angle >= -vm.radians(45) && angle < vm.radians(45)) command = 'R';
      else if (angle >= vm.radians(45) && angle < vm.radians(135)) command = 'F';
      else if (angle >= -vm.radians(135) && angle < -vm.radians(45)) command = 'B';
      else command = 'L';
    }
    
    _sendCommand(command);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              // Заголовок та статус бар
              _buildHeader(),
              const SizedBox(height: 16),
              
              // Основні панелі
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Панель підключення
                      _buildConnectionPanel(),
                      const SizedBox(height: 16),
                      
                      // Панель керування
                      _buildControlPanel(),
                      const SizedBox(height: 16),
                      
                      // Панель датчиків
                      _buildSensorPanel(),
                    ],
                  ),
                ),
              ),
              
              // Футер
              const Text(
                'ESP32 RC Controller | Flutter версія',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const Text(
          'RC Controller',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            shadows: [Shadow(blurRadius: 4, color: Colors.black45)],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _isConnected ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                    boxShadow: _isConnected
                        ? [BoxShadow(color: Colors.green, blurRadius: 8)]
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'BLE: ${_isConnected ? "Підключено" : "Відключено"}',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _emergency ? Colors.red : Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Стан: ${_emergency ? "Аварія!" : "Норма"}',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildConnectionPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Text(
            'Підключення',
            style: TextStyle(color: Color(0xFFFFCC00), fontSize: 18),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _isConnected ? _disconnect : _connect,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFCC00),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              minimumSize: const Size(double.infinity, 50),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(
              _isConnected ? "ВІДКЛЮЧИТИ BLE" : "ПІДКЛЮЧИТИ BLE",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Text(
            'Керування',
            style: TextStyle(color: Color(0xFFFFCC00), fontSize: 18),
          ),
          const SizedBox(height: 16),
          
          // Джойстик
          Center(
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF4d94ff), width: 2),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: const BoxDecoration(
                        color: Color(0xFF4d94ff),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black45,
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      transform: Matrix4.translationValues(
                        _joystickPosition.x,
                        _joystickPosition.y,
                        0,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onPanStart: (details) {
                      final localPosition = details.localPosition;
                      _updateJoystick(localPosition);
                    },
                    onPanUpdate: (details) {
                      final localPosition = details.localPosition;
                      _updateJoystick(localPosition);
                    },
                    onPanEnd: (details) {
                      setState(() {
                        _joystickPosition = vm.Vector2.zero();
                        _isDragging = false;
                      });
                      _sendCommand('S');
                    },
                  ),
                ],
              ),
            ),
          ),
          
          // Повзунок швидкості
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Швидкість:', style: TextStyle(color: Colors.white)),
                    Text('$_speed', style: const TextStyle(color: Colors.white)),
                  ],
                ),
                Slider(
                  value: _speed.toDouble(),
                  min: 50,
                  max: 255,
                  divisions: 205,
                  activeColor: const Color(0xFFFFCC00),
                  inactiveColor: Colors.grey[700],
                  onChanged: (value) {
                    setState(() => _speed = value.round());
                  },
                ),
              ],
            ),
          ),
          
          // Кнопки керування
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildControlButton('Вперед', 'F'),
              const SizedBox(width: 16),
              _buildControlButton('Стоп', 'S'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildControlButton('Ліворуч', 'L'),
              const SizedBox(width: 16),
              _buildControlButton('Праворуч', 'R'),
            ],
          ),
          
          // Аварійний режим
          if (_emergency)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(top: 16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.3),
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                border: const Border(
                  left: BorderSide(color: Colors.red, width: 4),
                ),
              ),
              child: const Text(
                'Увага! Аварійний режим',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSensorPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Text(
            'Датчики',
            style: TextStyle(color: Color(0xFFFFCC00), fontSize: 18),
          ),
          const SizedBox(height: 16),
          
          // Показники датчиків
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _buildSensorCard('Темп. ліво', '${_tempLeft.toStringAsFixed(1)} °C'),
              _buildSensorCard('Темп. право', '${_tempRight.toStringAsFixed(1)} °C'),
              _buildSensorCard('Струм ліво', '${_currentLeft.toStringAsFixed(1)} A'),
              _buildSensorCard('Струм право', '${_currentRight.toStringAsFixed(1)} A'),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Кнопки дій
          Row(
            children: [
              Expanded(
                child: _buildActionButton('Скид аварії', Colors.green, 'E'),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildActionButton('Стоп!', Colors.red, 'X'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton(String text, String command) {
    return ElevatedButton(
      onPressed: () => _sendCommand(command),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF4d94ff),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildActionButton(String text, Color color, String command) {
    return ElevatedButton(
      onPressed: () => _sendCommand(command),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildSensorCard(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}