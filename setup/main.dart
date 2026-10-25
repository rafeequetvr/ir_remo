import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MiRemoteApp());
}

class MiRemoteApp extends StatelessWidget {
  const MiRemoteApp({super.key});

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
      home: const DashboardScreen(),
    );
  }
}

// ==========================================
// IR TRANSMITTER ENGINE
// ==========================================

class IrEngine {
  static const platform = MethodChannel('com.custom.ir_remote/ir');

  static Future<bool> hasIr() async {
    try {
      return await platform.invokeMethod('hasIrEmitter') ?? false;
    } catch (_) {
      return false;
    }
  }

  // Proven working protocol on your phone (MSB First 32-bit NEC)
  static List<int> buildNecMsb(int code32) {
    final List<int> p = [9000, 4500];
    for (int i = 31; i >= 0; i--) {
      final int bit = (code32 >> i) & 1;
      p.add(560);
      p.add(bit == 1 ? 1690 : 560);
    }
    p.add(560);
    return p;
  }

  // Haier AC Multi-Variant Generator
  static List<int> buildHaierAc(int variant, bool power, int temp, String mode) {
    if (variant == 0) {
      // Variant 1: Haier YR-W02 / HSU 13-byte (3000,3000,3000,4500 header)
      List<int> b = [0xA6, 0x02, 0x40, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00];
      b[1] = (((temp.clamp(16, 30) - 16) & 0x0F) << 4) | 0x02;
      b[4] = power ? 0x40 : 0x00;
      b[7] = mode == 'DRY' ? 0x80 : (mode == 'FAN' ? 0xC0 : 0x40);
      int sum = 0;
      for (int i = 0; i < 12; i++) sum = (sum + b[i]) & 0xFF;
      b[12] = sum;

      final List<int> p = [3000, 3000, 3000, 4500];
      for (int byte in b) {
        for (int i = 7; i >= 0; i--) {
          p.add(540);
          p.add(((byte >> i) & 1) == 1 ? 1650 : 600);
        }
      }
      p.add(540);
      return p;
    } else if (variant == 1) {
      // Variant 2: Haier 9-byte A7 Protocol (3100, 4400 header)
      List<int> b = [0xA7, 0x00, 0x40, 0x00, 0x20, 0x00, 0x00, 0x20, 0x00];
      b[1] = (((temp.clamp(16, 30) - 16) & 0x0F) << 4) | (power ? 0x08 : 0x00) | 0x02;
      int sum = 0;
      for (int i = 0; i < 8; i++) sum = (sum + b[i]) & 0xFF;
      b[8] = sum;

      final List<int> p = [3100, 4400];
      for (int byte in b) {
        for (int i = 7; i >= 0; i--) {
          p.add(540);
          p.add(((byte >> i) & 1) == 1 ? 1650 : 600);
        }
      }
      p.add(540);
      return p;
    } else {
      // Variant 3: Haier / Midea NEC-like 48-bit (4400, 4400 header)
      List<int> b = [0xB2, 0x4D, power ? 0xBF : 0x7B, power ? 0x40 : 0x84, 0xE0, 0x1F];
      final List<int> p = [4400, 4400];
      for (int byte in b) {
        for (int i = 7; i >= 0; i--) {
          p.add(540);
          p.add(((byte >> i) & 1) == 1 ? 1600 : 540);
        }
      }
      p.add(540);
      return p;
    }
  }

  // TCL AC Multi-Variant Generator
  static List<int> buildTclAc(int variant, bool power, int temp, String mode) {
    List<int> b = [
      0x23, 0xCB, 0x26, 0x01, 0x00,
      power ? 0x24 : 0x20,
      mode == 'DRY' ? 0x02 : (mode == 'FAN' ? 0x07 : 0x03),
      (31 - temp.clamp(16, 30)) & 0x0F,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ];
    int sum = 0;
    for (int i = 0; i < 13; i++) sum = (sum + b[i]) & 0xFF;
    b[13] = sum;

    if (variant == 0) {
      // Variant 1: TCL112AC Standard LSB (3100, 1650)
      final List<int> p = [3100, 1650];
      for (int byte in b) {
        for (int i = 0; i < 8; i++) {
          p.add(500);
          p.add(((byte >> i) & 1) == 1 ? 1100 : 350);
        }
      }
      p.add(500);
      return p;
    } else if (variant == 1) {
      // Variant 2: TCL112AC Standard MSB (3100, 1650)
      final List<int> p = [3100, 1650];
      for (int byte in b) {
        for (int i = 7; i >= 0; i--) {
          p.add(500);
          p.add(((byte >> i) & 1) == 1 ? 1100 : 350);
        }
      }
      p.add(500);
      return p;
    } else {
      // Variant 3: TCL / Gree Alt Protocol (9000, 4500 header)
      return buildNecMsb(power ? 0x19082050 : 0x09082050);
    }
  }

  static Future<void> sendPattern(BuildContext context, List<int> pattern) async {
    HapticFeedback.lightImpact();
    try {
      await platform.invokeMethod('transmit', {
        'frequency': 38000,
        'pattern': pattern,
      });
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('IR Error: $e')));
    }
  }
}

// ==========================================
// DASHBOARD SCREEN (ONLY YOUR 4 APPLIANCES)
// ==========================================

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _hasIr = false;

  @override
  void initState() {
    super.initState();
    IrEngine.hasIr().then((v) => setState(() => _hasIr = v));
  }

  @override
  Widget build(BuildContext context) {
    final devices = [
      {
        'title': 'Atomberg Ameza Fan',
        'sub': 'BLDC Ceiling Fan (0xCF Protocol)',
        'icon': Icons.wind_power,
        'color': const Color(0xFFFF6700),
        'page': const AtombergRemoteScreen(),
      },
      {
        'title': 'V-Guard Windle Deco',
        'sub': 'BLDC Ceiling Fan (Multi-Code)',
        'icon': Icons.cyclone,
        'color': Colors.amber,
        'page': const VGuardRemoteScreen(),
      },
      {
        'title': 'Haier Split AC',
        'sub': 'Air Conditioner (3 Protocol Modes)',
        'icon': Icons.ac_unit,
        'color': Colors.tealAccent,
        'page': const AcRemoteScreen(brand: 'Haier'),
      },
      {
        'title': 'TCL Split AC',
        'sub': 'Air Conditioner (3 Protocol Modes)',
        'icon': Icons.ac_unit,
        'color': Colors.lightBlueAccent,
        'page': const AcRemoteScreen(brand: 'TCL'),
      },
    ];

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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              _hasIr ? '● IR Blaster Ready' : '● No IR Blaster Detected',
              style: TextStyle(fontSize: 11, color: _hasIr ? Colors.greenAccent : Colors.orangeAccent),
            ),
          ),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: devices.length,
        itemBuilder: (ctx, i) {
          final d = devices[i];
          return Card(
            color: const Color(0xFF1C2029),
            margin: const EdgeInsets.only(bottom: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              leading: CircleAvatar(
                radius: 26,
                backgroundColor: (d['color'] as Color).withOpacity(0.18),
                child: Icon(d['icon'] as IconData, color: d['color'] as Color, size: 28),
              ),
              title: Text(d['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              subtitle: Text(d['sub'] as String, style: const TextStyle(color: Colors.grey, fontSize: 13)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => d['page'] as Widget)),
            ),
          );
        },
      ),
    );
  }
}

// ==========================================
// 1. ATOMBERG FAN SCREEN (WITH SPEED 3,4,5 & LED FIXER)
// ==========================================

class AtombergRemoteScreen extends StatefulWidget {
  const AtombergRemoteScreen({super.key});

  @override
  State<AtombergRemoteScreen> createState() => _AtombergRemoteScreenState();
}

class _AtombergRemoteScreenState extends State<AtombergRemoteScreen> {
  // Default codes: POWER, SPEED 1, SPEED 2, BOOST, SLEEP, TIMERS are locked to what worked for you!
  // SPEED 3, 4, 5, and LED are updated to alternate Atomberg 0xCF hex codes, AND can be customized!
  Map<String, int> _codes = {
    'POWER': 0xCF8976,
    'SPEED_1': 0xCFD12E,
    'SPEED_2': 0xCFC936,
    'SPEED_3': 0xCFE11E, // Updated Ameza/Renesa Speed 3
    'SPEED_4': 0xCF916E, // Updated Ameza/Renesa Speed 4
    'SPEED_5': 0xCF817E, // Updated Ameza/Renesa Speed 5
    'BOOST': 0xCFA15E,
    'LED': 0xCF51AE,     // Updated Ameza/Renesa LED
    'SLEEP': 0xCFF50A,
    'TIMER_1H': 0xCFAD52,
    'TIMER_2H': 0xCFDD22,
    'TIMER_3H': 0xCF837C,
    'TIMER_6H': 0xCFE31C,
  };

  // Candidate Atomberg 0xCF codes for Speed 3, 4, 5 & LED so you can test and lock the exact one!
  final List<int> _candidateAtombergCodes = [
    0xCFE11E, 0xCF916E, 0xCF817E, 0xCF51AE, // Set A
    0xCF9966, 0xCFF906, 0xCFA55A, 0xCF956A, // Set B
    0xCF619E, 0xCFB14E, 0xCFD926, 0xCF718E, // Set C
    0xCF49B6, 0xCFC13E, 0xCF29D6, 0xCFA956, // Set D
    0xCF857A, 0xCF45BA, 0xCFC53A, 0xCF25DA, // Set E
    0xCF11EE, 0xCF31CE, 0xCFB946, 0xCF59A6, // Set F
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedAtombergCodes();
  }

  Future<void> _loadSavedAtombergCodes() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      for (var key in _codes.keys) {
        final saved = prefs.getInt('atomberg_$key');
        if (saved != null) _codes[key] = saved;
      }
    });
  }

  Future<void> _saveAtombergCode(String key, int code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('atomberg_$key', code);
    setState(() => _codes[key] = code);
  }

  void _fire(String key) {
    final int code = _codes[key] ?? 0xCF8976;
    IrEngine.sendPattern(context, IrEngine.buildNecMsb(code));
  }

  // Interactive Code Finder for Speed 3, 4, 5 & LED
  void _openCodeFinderDialog() {
    String selectedTarget = 'SPEED_3';
    int testIndex = 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final int currentCandidate = _candidateAtombergCodes[testIndex];
          final String hexStr = '0x${currentCandidate.toRadixString(16).toUpperCase()}';

          return AlertDialog(
            backgroundColor: const Color(0xFF1E222B),
            title: const Text('Fix Speed 3, 4, 5 & LED'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '1. Choose which button to fix.\n2. Tap "TEST SIGNAL" while pointing at fan.\n3. When the fan responds, tap "SAVE TO BUTTON"!',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedTarget,
                  decoration: const InputDecoration(labelText: 'Select Button to Fix'),
                  items: const [
                    DropdownMenuItem(value: 'SPEED_3', child: Text('Speed 3')),
                    DropdownMenuItem(value: 'SPEED_4', child: Text('Speed 4')),
                    DropdownMenuItem(value: 'SPEED_5', child: Text('Speed 5')),
                    DropdownMenuItem(value: 'LED', child: Text('LED Light')),
                  ],
                  onChanged: (v) {
                    if (v != null) setModalState(() => selectedTarget = v);
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  'Candidate ${testIndex + 1} of ${_candidateAtombergCodes.length}',
                  style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
                ),
                Text(hexStr, style: const TextStyle(fontSize: 22, fontFamily: 'monospace')),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios),
                      onPressed: () {
                        setModalState(() {
                          testIndex = (testIndex - 1 + _candidateAtombergCodes.length) % _candidateAtombergCodes.length;
                        });
                      },
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6700)),
                      icon: const Icon(Icons.wifi_tethering),
                      label: const Text('TEST SIGNAL'),
                      onPressed: () {
                        IrEngine.sendPattern(context, IrEngine.buildNecMsb(currentCandidate));
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios),
                      onPressed: () {
                        setModalState(() {
                          testIndex = (testIndex + 1) % _candidateAtombergCodes.length;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () {
                  _saveAtombergCode(selectedTarget, currentCandidate);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Saved $hexStr to $selectedTarget!')),
                  );
                },
                child: const Text('SAVE TO BUTTON'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _btn(String label, String keyName, {Color? bg, double size = 70, IconData? icon}) {
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
        onPressed: () => _fire(keyName),
        child: icon != null
            ? Icon(icon, size: 28)
            : Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Atomberg Ameza Fan'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.build_circle, color: Colors.amber),
            label: const Text('Fix 3,4,5/LED', style: TextStyle(color: Colors.amber)),
            onPressed: _openCodeFinderDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _btn('POWER', 'POWER', bg: Colors.redAccent, size: 84, icon: Icons.power_settings_new),
                  _btn('LED', 'LED', bg: const Color(0xFFFF6700), size: 84, icon: Icons.lightbulb_outline),
                ],
              ),
              const Text('FAN SPEED', style: TextStyle(color: Colors.grey, letterSpacing: 1.5, fontSize: 12)),
              Wrap(
                spacing: 18,
                runSpacing: 18,
                alignment: WrapAlignment.center,
                children: [
                  _btn('1', 'SPEED_1'),
                  _btn('2', 'SPEED_2'),
                  _btn('3', 'SPEED_3'),
                  _btn('4', 'SPEED_4'),
                  _btn('5', 'SPEED_5'),
                  _btn('BOOST', 'BOOST', bg: Colors.blueAccent),
                ],
              ),
              const Text('TIMER & SLEEP', style: TextStyle(color: Colors.grey, letterSpacing: 1.5, fontSize: 12)),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                alignment: WrapAlignment.center,
                children: [
                  _btn('SLEEP', 'SLEEP', size: 62),
                  _btn('1H', 'TIMER_1H', size: 62),
                  _btn('2H', 'TIMER_2H', size: 62),
                  _btn('3H', 'TIMER_3H', size: 62),
                  _btn('6H', 'TIMER_6H', size: 62),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 2. V-GUARD WINDLE DECO FAN SCREEN
// ==========================================

class VGuardRemoteScreen extends StatefulWidget {
  const VGuardRemoteScreen({super.key});

  @override
  State<VGuardRemoteScreen> createState() => _VGuardRemoteScreenState();
}

class _VGuardRemoteScreenState extends State<VGuardRemoteScreen> {
  int _mode = 0;

  // 3 different MSB-First NEC Code Sets used by V-Guard BLDC Fans
  final List<Map<String, int>> _vguardSets = [
    // Mode 1: Standard 0x00FF MSB-First
    {
      'POWER': 0x00FF02FD,
      'LED': 0x00FF6897,
      'SPEED_1': 0x00FF30CF,
      'SPEED_2': 0x00FF18E7,
      'SPEED_3': 0x00FF7A85,
      'SPEED_4': 0x00FF10EF,
      'SPEED_5': 0x00FF38C7,
      'BOOST': 0x00FF5AA5,
      'TIMER_1H': 0x00FF42BD,
      'TIMER_2H': 0x00FF4AB5,
      'TIMER_4H': 0x00FF52AD,
    },
    // Mode 2: V-Guard Alt 0x00FF Set B
    {
      'POWER': 0x00FFA25D,
      'LED': 0x00FFE21D,
      'SPEED_1': 0x00FF22DD,
      'SPEED_2': 0x00FF02FD,
      'SPEED_3': 0x00FFC23D,
      'SPEED_4': 0x00FFE01F,
      'SPEED_5': 0x00FFA857,
      'BOOST': 0x00FF906F,
      'TIMER_1H': 0x00FF6897,
      'TIMER_2H': 0x00FF9867,
      'TIMER_4H': 0x00FFB04F,
    },
    // Mode 3: V-Guard 0x807F / 0x01FE Set C
    {
      'POWER': 0x807F48B7,
      'LED': 0x807F8877,
      'SPEED_1': 0x807F807F,
      'SPEED_2': 0x807F40BF,
      'SPEED_3': 0x807FC03F,
      'SPEED_4': 0x807F20DF,
      'SPEED_5': 0x807FA05F,
      'BOOST': 0x807F609F,
      'TIMER_1H': 0x807FE01F,
      'TIMER_2H': 0x807F10EF,
      'TIMER_4H': 0x807F906F,
    },
  ];

  void _send(String key) {
    final code = _vguardSets[_mode][key] ?? 0x00FF02FD;
    IrEngine.sendPattern(context, IrEngine.buildNecMsb(code));
  }

  Widget _btn(String label, String keyName, {Color? bg, double size = 72}) {
    return SizedBox(
      width: size,
      height: size,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: bg ?? const Color(0xFF222630),
          foregroundColor: Colors.white,
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
        onPressed: () => _send(keyName),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('V-Guard Windle Deco')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(3, (i) {
                return ChoiceChip(
                  label: Text('V-Guard Mode ${i + 1}'),
                  selected: _mode == i,
                  selectedColor: Colors.amber.shade800,
                  onSelected: (_) => setState(() => _mode = i),
                );
              }),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _btn('POWER', 'POWER', bg: Colors.redAccent, size: 84),
                _btn('LED', 'LED', bg: Colors.amber.shade800, size: 84),
              ],
            ),
            Wrap(
              spacing: 18,
              runSpacing: 18,
              alignment: WrapAlignment.center,
              children: [
                _btn('1', 'SPEED_1'),
                _btn('2', 'SPEED_2'),
                _btn('3', 'SPEED_3'),
                _btn('4', 'SPEED_4'),
                _btn('5', 'SPEED_5'),
                _btn('BOOST', 'BOOST', bg: Colors.blueAccent),
              ],
            ),
            Wrap(
              spacing: 16,
              alignment: WrapAlignment.center,
              children: [
                _btn('1H', 'TIMER_1H', size: 64),
                _btn('2H', 'TIMER_2H', size: 64),
                _btn('4H', 'TIMER_4H', size: 64),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 3 & 4. HAIER & TCL AC SCREEN (3 MODES EACH)
// ==========================================

class AcRemoteScreen extends StatefulWidget {
  final String brand;
  const AcRemoteScreen({super.key, required this.brand});

  @override
  State<AcRemoteScreen> createState() => _AcRemoteScreenState();
}

class _AcRemoteScreenState extends State<AcRemoteScreen> {
  int _variant = 0;
  bool _power = true;
  int _temp = 24;
  String _mode = 'COOL';

  void _transmitAc() {
    final pattern = widget.brand == 'Haier'
        ? IrEngine.buildHaierAc(_variant, _power, _temp, _mode)
        : IrEngine.buildTclAc(_variant, _power, _temp, _mode);
    IrEngine.sendPattern(context, pattern);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.brand} Split AC')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(3, (i) {
                return ChoiceChip(
                  label: Text('${widget.brand} Mode ${i + 1}'),
                  selected: _variant == i,
                  selectedColor: Colors.teal,
                  onSelected: (_) => setState(() => _variant = i),
                );
              }),
            ),
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
                  Text('${widget.brand} Mode ${_variant + 1} • $_mode', style: const TextStyle(color: Colors.tealAccent)),
                  const SizedBox(height: 16),
                  Text(_power ? '$_temp°C' : 'OFF', style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w300)),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                SizedBox(
                  width: 76,
                  height: 76,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(shape: const CircleBorder(), backgroundColor: const Color(0xFF222630)),
                    onPressed: () {
                      setState(() => _temp = (_temp - 1).clamp(16, 30));
                      _transmitAc();
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
                      backgroundColor: _power ? Colors.redAccent : Colors.teal,
                    ),
                    onPressed: () {
                      setState(() => _power = !_power);
                      _transmitAc();
                    },
                    child: const Icon(Icons.power_settings_new, size: 38, color: Colors.white),
                  ),
                ),
                SizedBox(
                  width: 76,
                  height: 76,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(shape: const CircleBorder(), backgroundColor: const Color(0xFF222630)),
                    onPressed: () {
                      setState(() => _temp = (_temp + 1).clamp(16, 30));
                      _transmitAc();
                    },
                    child: const Text('TEMP +'),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: ['COOL', 'DRY', 'FAN'].map((m) {
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _mode == m ? Colors.teal : const Color(0xFF222630),
                  ),
                  onPressed: () {
                    setState(() => _mode = m);
                    _transmitAc();
                  },
                  child: Text(m),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
