import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MiRemoteCloneApp());
}

class MiRemoteCloneApp extends StatelessWidget {
  const MiRemoteCloneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mi Remote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121418),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A1D24),
          elevation: 0,
          centerTitle: true,
        ),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF6700),
          secondary: Color(0xFF00BFA5),
        ),
      ),
      home: const MiDashboardScreen(),
    );
  }
}

// ==========================================
// DATA MODELS & HARDWARE PROTOCOLS
// ==========================================

class IrCommand {
  String type; // 'nec_msb', 'nec_lsb', 'haier_ac', 'tcl_ac', 'raw'
  String payload;

  IrCommand({required this.type, required this.payload});

  Map<String, dynamic> toJson() => {'type': type, 'payload': payload};

  factory IrCommand.fromJson(Map<String, dynamic> json) => IrCommand(
        type: json['type'] ?? 'nec_msb',
        payload: json['payload'] ?? '0x00000000',
      );
}

class MiRemoteDevice {
  String id;
  String name;
  String brand;
  String category; // 'FAN', 'AC', 'TV'
  int frequency;
  Map<String, IrCommand> keymap;

  MiRemoteDevice({
    required this.id,
    required this.name,
    required this.brand,
    required this.category,
    this.frequency = 38000,
    required this.keymap,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'brand': brand,
        'category': category,
        'frequency': frequency,
        'keymap': keymap.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory MiRemoteDevice.fromJson(Map<String, dynamic> json) {
    final rawMap = json['keymap'] as Map<String, dynamic>? ?? {};
    return MiRemoteDevice(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name'] ?? 'Remote',
      brand: json['brand'] ?? 'Generic',
      category: json['category'] ?? 'FAN',
      frequency: json['frequency'] ?? 38000,
      keymap: rawMap.map((k, v) => MapEntry(k, IrCommand.fromJson(v))),
    );
  }
}

// ==========================================
// EXACT IR PROTOCOL ENCODERS (ATOMBERG, V-GUARD, HAIER, TCL)
// ==========================================

class IrService {
  static const platform = MethodChannel('com.custom.ir_remote/ir');

  static Future<bool> hasIrEmitter() async {
    try {
      return await platform.invokeMethod('hasIrEmitter') ?? false;
    } catch (_) {
      return false;
    }
  }

  // 1. Standard NEC 32-bit (MSB First - IRremote / Arduino format)
  static List<int> buildNecMsb(int code) {
    final List<int> p = [9000, 4500];
    for (int i = 31; i >= 0; i--) {
      final int bit = (code >> i) & 1;
      p.add(560);
      p.add(bit == 1 ? 1690 : 560);
    }
    p.add(560);
    return p;
  }

  // 2. Hardware NEC 32-bit (LSB First - Real NEC Hardware Bit Order)
  static List<int> buildNecLsb(int address16, int command8) {
    final List<int> p = [9000, 4500];
    final int invCommand8 = (~command8) & 0xFF;
    final int fullFrame = (address16 & 0xFFFF) | ((command8 & 0xFF) << 16) | (invCommand8 << 24);
    for (int i = 0; i < 32; i++) {
      final int bit = (fullFrame >> i) & 1;
      p.add(560);
      p.add(bit == 1 ? 1690 : 560);
    }
    p.add(560);
    return p;
  }

  // 3. Haier AC 104-bit (13-Byte) Protocol Generator (YR-W02 / HSU Series)
  static List<int> buildHaierAc({required bool power, required int temp, String mode = 'COOL'}) {
    List<int> bytes = List.filled(13, 0);
    bytes[0] = 0xA6; // Haier Model Header
    final int tempOffset = (temp.clamp(16, 30) - 16) & 0x0F;
    bytes[1] = (tempOffset << 4) | 0x02; // Temp + Swing Auto
    bytes[2] = 0x40; // Fan Speed Auto
    bytes[4] = power ? 0x40 : 0x00; // Power Bit
    int modeBits = 0x02; // Cool = 2, Dry = 4, Fan = 6
    if (mode == 'DRY') modeBits = 0x04;
    if (mode == 'FAN') modeBits = 0x06;
    bytes[7] = (modeBits << 5);

    // Checksum in byte 12 (sum of bytes 0..11)
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      sum = (sum + bytes[i]) & 0xFF;
    }
    bytes[12] = sum;

    // Haier Distinctive Double Header: 3000, 3000, 3000, 4500 (MSB per byte)
    final List<int> p = [3000, 3000, 3000, 4500];
    for (int b in bytes) {
      for (int i = 7; i >= 0; i--) {
        final int bit = (b >> i) & 1;
        p.add(520);
        p.add(bit == 1 ? 1650 : 650);
      }
    }
    p.add(520);
    return p;
  }

  // 4. TCL AC 112-bit (14-Byte) Protocol Generator (TCL112AC / GYKQ Series)
  static List<int> buildTclAc({required bool power, required int temp, String mode = 'COOL'}) {
    List<int> bytes = [
      0x23, 0xCB, 0x26, 0x01, 0x00,
      power ? 0x24 : 0x20, // Byte 5: Power bit (0x04)
      0x03, // Byte 6: Cool Mode (0x03), Dry (0x02), Fan (0x07)
      (31 - temp.clamp(16, 30)) & 0x0F, // Byte 7: TCL Temp formula (31 - temp)
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ];
    if (mode == 'DRY') bytes[6] = 0x02;
    if (mode == 'FAN') bytes[6] = 0x07;

    // Checksum in byte 13 (sum of bytes 0..12)
    int sum = 0;
    for (int i = 0; i < 13; i++) {
      sum = (sum + bytes[i]) & 0xFF;
    }
    bytes[13] = sum;

    // TCL Header: 3100, 1650 (LSB per byte)
    final List<int> p = [3100, 1650];
    for (int b in bytes) {
      for (int i = 0; i < 8; i++) {
        final int bit = (b >> i) & 1;
        p.add(500);
        p.add(bit == 1 ? 1100 : 350);
      }
    }
    p.add(500);
    return p;
  }

  static Future<void> transmitPattern(BuildContext context, int frequency, List<int> pattern) async {
    HapticFeedback.lightImpact();
    try {
      await platform.invokeMethod('transmit', {
        'frequency': frequency,
        'pattern': pattern,
      });
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('IR Error: $e')),
      );
    }
  }

  static Future<void> transmitCommand(BuildContext context, int frequency, IrCommand? cmd) async {
    if (cmd == null) return;
    try {
      List<int> pattern = [];
      if (cmd.type == 'nec_msb') {
        final clean = cmd.payload.trim().replaceAll('0x', '').replaceAll('0X', '');
        pattern = buildNecMsb(int.parse(clean, radix: 16));
      } else if (cmd.type == 'nec_lsb') {
        // Format: "0xF300,0x91" (Address,Command)
        final parts = cmd.payload.split(',');
        final addr = int.parse(parts[0].trim().replaceAll('0x', ''), radix: 16);
        final c = int.parse(parts[1].trim().replaceAll('0x', ''), radix: 16);
        pattern = buildNecLsb(addr, c);
      } else {
        pattern = cmd.payload.split(',').map((e) => int.parse(e.trim())).toList();
      }
      await transmitPattern(context, frequency, pattern);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid Code Format: $e')),
      );
    }
  }
}

// ==========================================
// BUILT-IN PRESETS FOR YOUR 4 APPLIANCES
// ==========================================

final List<MiRemoteDevice> defaultUserAppliances = [
  // 1. Atomberg Ameza BLDC Fan (Both LSB & MSB Modes)
  MiRemoteDevice(
    id: 'atomberg_ameza',
    name: 'Atomberg Ameza Fan',
    brand: 'Atomberg (LSB Protocol)',
    category: 'FAN',
    keymap: {
      'POWER': IrCommand(type: 'nec_lsb', payload: '0xF300,0x91'),
      'LED': IrCommand(type: 'nec_lsb', payload: '0xF300,0xA9'),
      'SPEED_1': IrCommand(type: 'nec_lsb', payload: '0xF300,0x8B'),
      'SPEED_2': IrCommand(type: 'nec_lsb', payload: '0xF300,0x93'),
      'SPEED_3': IrCommand(type: 'nec_lsb', payload: '0xF300,0x99'),
      'SPEED_4': IrCommand(type: 'nec_lsb', payload: '0xF300,0x9F'),
      'SPEED_5': IrCommand(type: 'nec_lsb', payload: '0xF300,0xA5'),
      'BOOST': IrCommand(type: 'nec_lsb', payload: '0xF300,0x85'),
      'SLEEP': IrCommand(type: 'nec_lsb', payload: '0xF300,0xAF'),
      'TIMER_1H': IrCommand(type: 'nec_lsb', payload: '0xF300,0xB5'),
      'TIMER_2H': IrCommand(type: 'nec_lsb', payload: '0xF300,0xBB'),
      'TIMER_3H': IrCommand(type: 'nec_lsb', payload: '0xF300,0xC1'),
      'TIMER_6H': IrCommand(type: 'nec_lsb', payload: '0xF300,0xC7'),
    },
  ),

  // 2. Atomberg Alternate (Gen-1 / Renesa / Studio Hex)
  MiRemoteDevice(
    id: 'atomberg_alt',
    name: 'Atomberg Fan (Gen-1)',
    brand: 'Atomberg (0x00FF / 0xCF)',
    category: 'FAN',
    keymap: {
      'POWER': IrCommand(type: 'nec_msb', payload: '0xCF8976'),
      'LED': IrCommand(type: 'nec_msb', payload: '0xCF956A'),
      'SPEED_1': IrCommand(type: 'nec_msb', payload: '0xCFD12E'),
      'SPEED_2': IrCommand(type: 'nec_msb', payload: '0xCFC936'),
      'SPEED_3': IrCommand(type: 'nec_msb', payload: '0xCF9966'),
      'SPEED_4': IrCommand(type: 'nec_msb', payload: '0xCFF906'),
      'SPEED_5': IrCommand(type: 'nec_msb', payload: '0xCFA55A'),
      'BOOST': IrCommand(type: 'nec_msb', payload: '0xCFA15E'),
      'SLEEP': IrCommand(type: 'nec_msb', payload: '0xCFF50A'),
      'TIMER_1H': IrCommand(type: 'nec_msb', payload: '0xCFAD52'),
      'TIMER_2H': IrCommand(type: 'nec_msb', payload: '0xCFDD22'),
      'TIMER_3H': IrCommand(type: 'nec_msb', payload: '0xCF837C'),
      'TIMER_6H': IrCommand(type: 'nec_msb', payload: '0xCFE31C'),
    },
  ),

  // 3. V-Guard Windle Deco BLDC Fan
  MiRemoteDevice(
    id: 'vguard_windle_deco',
    name: 'V-Guard Windle Deco',
    brand: 'V-Guard BLDC',
    category: 'FAN',
    keymap: {
      'POWER': IrCommand(type: 'nec_lsb', payload: '0x00FF,0x02'),
      'LED': IrCommand(type: 'nec_lsb', payload: '0x00FF,0x16'),
      'SPEED_1': IrCommand(type: 'nec_lsb', payload: '0x00FF,0x0C'),
      'SPEED_2': IrCommand(type: 'nec_lsb', payload: '0x00FF,0x18'),
      'SPEED_3': IrCommand(type: 'nec_lsb', payload: '0x00FF,0x5E'),
      'SPEED_4': IrCommand(type: 'nec_lsb', payload: '0x00FF,0x08'),
      'SPEED_5': IrCommand(type: 'nec_lsb', payload: '0x00FF,0x1C'),
      'BOOST': IrCommand(type: 'nec_lsb', payload: '0x00FF,0x5A'),
      'SLEEP': IrCommand(type: 'nec_lsb', payload: '0x00FF,0x42'),
      'TIMER_1H': IrCommand(type: 'nec_lsb', payload: '0x00FF,0x4A'),
      'TIMER_2H': IrCommand(type: 'nec_lsb', payload: '0x00FF,0x52'),
      'TIMER_3H': IrCommand(type: 'nec_lsb', payload: '0x00FF,0x40'),
      'TIMER_6H': IrCommand(type: 'nec_lsb', payload: '0x00FF,0x48'),
    },
  ),

  // 4. Haier Split AC
  MiRemoteDevice(
    id: 'haier_ac_unit',
    name: 'Haier Split AC',
    brand: 'Haier (104-Bit Protocol)',
    category: 'AC',
    keymap: {},
  ),

  // 5. TCL Split AC
  MiRemoteDevice(
    id: 'tcl_ac_unit',
    name: 'TCL Split AC',
    brand: 'TCL (112-Bit Protocol)',
    category: 'AC',
    keymap: {},
  ),
];

// ==========================================
// DASHBOARD SCREEN
// ==========================================

class MiDashboardScreen extends StatefulWidget {
  const MiDashboardScreen({super.key});

  @override
  State<MiDashboardScreen> createState() => _MiDashboardScreenState();
}

class _MiDashboardScreenState extends State<MiDashboardScreen> {
  static const String _storageKey = 'mi_remote_devices_v3'; // Bumped version so new presets load automatically!
  List<MiRemoteDevice> _remotes = [];
  bool _hasIr = false;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final ir = await IrService.hasIrEmitter();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);

    if (raw != null && raw.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(raw);
        setState(() {
          _hasIr = ir;
          _remotes = list.map((e) => MiRemoteDevice.fromJson(e)).toList();
        });
        return;
      } catch (_) {}
    }

    setState(() {
      _hasIr = ir;
      _remotes = defaultUserAppliances.map((e) => MiRemoteDevice.fromJson(e.toJson())).toList();
    });
    _saveRemotes();
  }

  Future<void> _saveRemotes() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_remotes.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }

  void _resetToFactoryPresets() {
    setState(() {
      _remotes = defaultUserAppliances.map((e) => MiRemoteDevice.fromJson(e.toJson())).toList();
    });
    _saveRemotes();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Loaded Atomberg, V-Guard, Haier AC & TCL AC!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.settings_remote, color: Color(0xFFFF6700)),
            SizedBox(width: 8),
            Text('Mi Remote', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Reload Default Remotes',
            icon: const Icon(Icons.refresh),
            onPressed: _resetToFactoryPresets,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              _hasIr ? '● IR Blaster Ready (38 kHz)' : '● No IR Blaster Detected',
              style: TextStyle(
                fontSize: 11,
                color: _hasIr ? Colors.greenAccent : Colors.orangeAccent,
              ),
            ),
          ),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _remotes.length,
        itemBuilder: (context, index) {
          final remote = _remotes[index];
          final isAc = remote.category == 'AC';
          return Card(
            color: const Color(0xFF1C2029),
            margin: const EdgeInsets.only(bottom: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              leading: CircleAvatar(
                radius: 26,
                backgroundColor: (isAc ? Colors.tealAccent : const Color(0xFFFF6700)).withOpacity(0.18),
                child: Icon(
                  isAc ? Icons.ac_unit : Icons.wind_power,
                  color: isAc ? Colors.tealAccent : const Color(0xFFFF6700),
                  size: 28,
                ),
              ),
              title: Text(remote.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              subtitle: Text(remote.brand, style: const TextStyle(color: Colors.grey)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RemoteControlScreen(device: remote, onSave: _saveRemotes),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ==========================================
// REMOTE CONTROL SCREEN (FAN + HAIER/TCL AC)
// ==========================================

class RemoteControlScreen extends StatefulWidget {
  final MiRemoteDevice device;
  final VoidCallback onSave;

  const RemoteControlScreen({super.key, required this.device, required this.onSave});

  @override
  State<RemoteControlScreen> createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> {
  bool _acPower = true;
  int _acTemp = 24;
  String _acMode = 'COOL';
  // For Fan Protocol Switcher (lets you test 3 different NEC bit-orders instantly!)
  int _fanProtocolVariant = 0;

  void _sendFanKey(String keyName) {
    final cmd = widget.device.keymap[keyName];
    if (cmd == null) return;

    // If user switched variant tab at top of Fan screen, test alternate bit orders automatically!
    if (_fanProtocolVariant == 0) {
      IrService.transmitCommand(context, widget.device.frequency, cmd);
    } else if (_fanProtocolVariant == 1) {
      // Variant 2: Send 0xF300916E style MSB first
      final Map<String, int> msbMap = {
        'POWER': 0xF300916E,
        'LED': 0xF3000AF5,
        'SPEED_1': 0xF30004FB,
        'SPEED_2': 0xF30005FA,
        'SPEED_3': 0xF30006F9,
        'SPEED_4': 0xF30007F8,
        'SPEED_5': 0xF30008F7,
        'BOOST': 0xF30009F6,
        'SLEEP': 0xF3000BF4,
        'TIMER_1H': 0xF3000CF3,
        'TIMER_2H': 0xF3000DF2,
        'TIMER_3H': 0xF3000EF1,
        'TIMER_6H': 0xF3000FF0,
      };
      final code = msbMap[keyName] ?? 0xF300916E;
      IrService.transmitPattern(context, 38000, IrService.buildNecMsb(code));
    } else {
      // Variant 3: Standard 0x00FF NEC LSB
      final Map<String, int> vguardAlt = {
        'POWER': 0x40,
        'LED': 0x12,
        'SPEED_1': 0x01,
        'SPEED_2': 0x02,
        'SPEED_3': 0x03,
        'SPEED_4': 0x04,
        'SPEED_5': 0x05,
        'BOOST': 0x06,
        'SLEEP': 0x07,
        'TIMER_1H': 0x08,
        'TIMER_2H': 0x09,
        'TIMER_3H': 0x0A,
        'TIMER_6H': 0x0B,
      };
      IrService.transmitPattern(
        context,
        38000,
        IrService.buildNecLsb(0x00FF, vguardAlt[keyName] ?? 0x40),
      );
    }
  }

  void _sendAcState() {
    final isTcl = widget.device.brand.toUpperCase().contains('TCL') ||
        widget.device.name.toUpperCase().contains('TCL');

    final List<int> pattern = isTcl
        ? IrService.buildTclAc(power: _acPower, temp: _acTemp, mode: _acMode)
        : IrService.buildHaierAc(power: _acPower, temp: _acTemp, mode: _acMode);

    IrService.transmitPattern(context, 38000, pattern);
  }

  Widget _roundBtn(String label, String keyName, {Color? bg, double size = 70, IconData? icon}) {
    return SizedBox(
      width: size,
      height: size,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: bg ?? const Color(0xFF222630),
          foregroundColor: Colors.white,
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
          elevation: 4,
        ),
        onPressed: () => _sendFanKey(keyName),
        child: icon != null
            ? Icon(icon, size: 28)
            : Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAc = widget.device.category == 'AC';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.name),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: isAc ? _buildAcLayout() : _buildFanLayout(),
        ),
      ),
    );
  }

  Widget _buildFanLayout() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Protocol Variant Selector (Helps test 3 IR bit orders with 1 tap)
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF1C2029),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(3, (i) {
              final selected = _fanProtocolVariant == i;
              return ChoiceChip(
                label: Text('IR Mode ${i + 1}'),
                selected: selected,
                selectedColor: const Color(0xFFFF6700),
                onSelected: (_) => setState(() => _fanProtocolVariant = i),
              );
            }),
          ),
        ),
        const Text(
          'If Mode 1 does not beep, tap Mode 2 or Mode 3 above and test POWER',
          style: TextStyle(fontSize: 11, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _roundBtn('POWER', 'POWER', bg: Colors.redAccent, size: 84, icon: Icons.power_settings_new),
            _roundBtn('LED', 'LED', bg: const Color(0xFFFF6700), size: 84, icon: Icons.lightbulb_outline),
          ],
        ),
        Wrap(
          spacing: 18,
          runSpacing: 18,
          alignment: WrapAlignment.center,
          children: [
            _roundBtn('1', 'SPEED_1'),
            _roundBtn('2', 'SPEED_2'),
            _roundBtn('3', 'SPEED_3'),
            _roundBtn('4', 'SPEED_4'),
            _roundBtn('5', 'SPEED_5'),
            _roundBtn('BOOST', 'BOOST', bg: Colors.blueAccent),
          ],
        ),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          alignment: WrapAlignment.center,
          children: [
            _roundBtn('SLEEP', 'SLEEP', size: 62),
            _roundBtn('1H', 'TIMER_1H', size: 62),
            _roundBtn('2H', 'TIMER_2H', size: 62),
            _roundBtn('3H', 'TIMER_3H', size: 62),
            _roundBtn('6H', 'TIMER_6H', size: 62),
          ],
        ),
      ],
    );
  }

  Widget _buildAcLayout() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2826),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.tealAccent.withOpacity(0.4)),
          ),
          child: Column(
            children: [
              Text(
                '${widget.device.brand} • MODE: $_acMode',
                style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                _acPower ? '$_acTemp°C' : 'OFF',
                style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w300),
              ),
              const SizedBox(height: 8),
              const Text('Stateful 104/112-Bit AC Packet', style: TextStyle(fontSize: 11, color: Colors.white54)),
            ],
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            SizedBox(
              width: 78,
              height: 78,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(shape: const CircleBorder(), backgroundColor: const Color(0xFF222630)),
                onPressed: () {
                  setState(() => _acTemp = (_acTemp - 1).clamp(16, 30));
                  _sendAcState();
                },
                child: const Text('TEMP -'),
              ),
            ),
            SizedBox(
              width: 92,
              height: 92,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  shape: const CircleBorder(),
                  backgroundColor: _acPower ? Colors.redAccent : Colors.teal,
                ),
                onPressed: () {
                  setState(() => _acPower = !_acPower);
                  _sendAcState();
                },
                child: const Icon(Icons.power_settings_new, size: 38, color: Colors.white),
              ),
            ),
            SizedBox(
              width: 78,
              height: 78,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(shape: const CircleBorder(), backgroundColor: const Color(0xFF222630)),
                onPressed: () {
                  setState(() => _acTemp = (_acTemp + 1).clamp(16, 30));
                  _sendAcState();
                },
                child: const Text('TEMP +'),
              ),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['COOL', 'DRY', 'FAN'].map((m) {
            final active = _acMode == m;
            return ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: active ? Colors.teal : const Color(0xFF222630),
              ),
              onPressed: () {
                setState(() => _acMode = m);
                _sendAcState();
              },
              child: Text(m),
            );
          }).toList(),
        ),
      ],
    );
  }
}
