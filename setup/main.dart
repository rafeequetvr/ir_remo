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

  // Standard 32-bit NEC (MSB First - Confirmed working on your Atomberg Fan)
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

  // Standard 32-bit NEC (LSB First)
  static List<int> buildNecLsb(int addr16, int cmd8) {
    final List<int> p = [9000, 4500];
    final int invCmd = (~cmd8) & 0xFF;
    final int frame = (addr16 & 0xFFFF) | ((cmd8 & 0xFF) << 16) | (invCmd << 24);
    for (int i = 0; i < 32; i++) {
      final int bit = (frame >> i) & 1;
      p.add(560);
      p.add(bit == 1 ? 1690 : 560);
    }
    p.add(560);
    return p;
  }

  // Holtek 12-bit / 24-bit RF-style IR Protocol (Used in many Indian BLDC fans)
  static List<int> buildHoltekFan(int code12) {
    final List<int> p = [];
    // Repeat frame 3 times for reliability
    for (int r = 0; r < 3; r++) {
      for (int i = 11; i >= 0; i--) {
        final int bit = (code12 >> i) & 1;
        if (bit == 1) {
          p.addAll([840, 420]);
        } else {
          p.addAll([420, 840]);
        }
      }
      p.addAll([420, 10000]); // Sync gap
    }
    return p;
  }

  // Helper to convert byte array to Haier IR Pulses (3000, 3000, 3000, 4450 header)
  static List<int> _haierBytesToPulses(List<int> bytes, {bool lsb = false}) {
    int sum = 0;
    for (int i = 0; i < bytes.length - 1; i++) {
      sum = (sum + bytes[i]) & 0xFF;
    }
    bytes[bytes.length - 1] = sum;

    final List<int> p = [3000, 3000, 3000, 4450];
    for (int b in bytes) {
      if (lsb) {
        for (int i = 0; i < 8; i++) {
          p.add(540);
          p.add(((b >> i) & 1) == 1 ? 1650 : 580);
        }
      } else {
        for (int i = 7; i >= 0; i--) {
          p.add(540);
          p.add(((b >> i) & 1) == 1 ? 1650 : 580);
        }
      }
    }
    p.add(540);
    return p;
  }

  // Haier HS-12NSS3(DCINV) 5-Variant Protocol Generator
  static List<int> buildHaierAc(int variant, bool power, int temp, String mode) {
    final int t = (temp.clamp(16, 30) - 16) & 0x0F;

    switch (variant) {
      case 0:
        // Mode 1: Haier 2017 9-Byte (72-bit) YR-H / YR-M Series (0xA5 Header)
        List<int> b = [
          0xA5,
          (t << 4) | 0x01,
          0x20,
          power ? 0x02 : 0x00,
          mode == 'DRY' ? 0x40 : (mode == 'FAN' ? 0x60 : 0x20),
          0x00,
          0x00,
          0x00,
          0x00
        ];
        return _haierBytesToPulses(b);

      case 1:
        // Mode 2: Haier 14-Byte (112-bit) YR-HD DC Inverter (0xA6, 0x22 Header)
        List<int> b = [
          0xA6,
          (t << 4) | 0x02,
          0x00,
          0x00,
          power ? 0x40 : 0x00,
          0x60,
          0x00,
          mode == 'DRY' ? 0x40 : (mode == 'FAN' ? 0x60 : 0x20),
          0x00,
          0x00,
          0x00,
          0x00,
          0x80,
          0x00
        ];
        return _haierBytesToPulses(b);

      case 2:
        // Mode 3: Haier 13-Byte (104-bit) YR-W02 / HSU Series (MSB)
        List<int> b = [
          0xA6,
          (t << 4) | 0x02,
          0x40,
          0x00,
          power ? 0x40 : 0x00,
          0x00,
          0x00,
          mode == 'DRY' ? 0x80 : (mode == 'FAN' ? 0xC0 : 0x40),
          0x00,
          0x00,
          0x00,
          0x00,
          0x00
        ];
        return _haierBytesToPulses(b);

      case 3:
        // Mode 4: Haier 9-Byte (72-bit) 0xA3 / 0xA7 Series
        List<int> b = [
          0xA3,
          (t << 4) | (power ? 0x08 : 0x00) | 0x02,
          0x40,
          0x00,
          0x20,
          0x00,
          0x00,
          0x20,
          0x00
        ];
        return _haierBytesToPulses(b);

      default:
        // Mode 5: Haier 13-Byte LSB Order Variant
        List<int> b = [
          0xA6,
          (t << 4) | 0x02,
          0x40,
          0x00,
          power ? 0x40 : 0x00,
          0x00,
          0x00,
          0x40,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00
        ];
        return _haierBytesToPulses(b, lsb: true);
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
// DASHBOARD SCREEN
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
        'sub': 'BLDC Ceiling Fan (Working + Code Fixer)',
        'icon': Icons.wind_power,
        'color': const Color(0xFFFF6700),
        'page': const AtombergRemoteScreen(),
      },
      {
        'title': 'V-Guard Windle Deco',
        'sub': 'BLDC Fan (8 IR Protocol Scanner)',
        'icon': Icons.cyclone,
        'color': Colors.amber,
        'page': const VGuardRemoteScreen(),
      },
      {
        'title': 'Haier HS-12NSS3(DCINV)',
        'sub': 'DC Inverter Split AC (5 Haier Modes)',
        'icon': Icons.ac_unit,
        'color': Colors.tealAccent,
        'page': const AcRemoteScreen(brand: 'Haier', maxModes: 5),
      },
      {
        'title': 'TCL Split AC',
        'sub': 'Air Conditioner (3 TCL Modes)',
        'icon': Icons.ac_unit,
        'color': Colors.lightBlueAccent,
        'page': const AcRemoteScreen(brand: 'TCL', maxModes: 3),
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
// 1. ATOMBERG FAN SCREEN
// ==========================================

class AtombergRemoteScreen extends StatefulWidget {
  const AtombergRemoteScreen({super.key});

  @override
  State<AtombergRemoteScreen> createState() => _AtombergRemoteScreenState();
}

class _AtombergRemoteScreenState extends State<AtombergRemoteScreen> {
  final Map<String, int> _codes = {
    'POWER': 0xCF8976,
    'SPEED_1': 0xCFD12E,
    'SPEED_2': 0xCFC936,
    'SPEED_3': 0xCFE11E,
    'SPEED_4': 0xCF916E,
    'SPEED_5': 0xCF817E,
    'BOOST': 0xCFA15E,
    'LED': 0xCF51AE,
    'SLEEP': 0xCFF50A,
    'TIMER_1H': 0xCFAD52,
    'TIMER_2H': 0xCFDD22,
    'TIMER_3H': 0xCF837C,
    'TIMER_6H': 0xCFE31C,
  };

  final List<int> _candidateAtombergCodes = [
    0xCFE11E, 0xCF916E, 0xCF817E, 0xCF51AE,
    0xCF9966, 0xCFF906, 0xCFA55A, 0xCF956A,
    0xCF619E, 0xCFB14E, 0xCFD926, 0xCF718E,
    0xCF49B6, 0xCFC13E, 0xCF29D6, 0xCFA956,
    0xCF857A, 0xCF45BA, 0xCFC53A, 0xCF25DA,
    0xCF11EE, 0xCF31CE, 0xCFB946, 0xCF59A6,
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
                  'Tap TEST SIGNAL while pointing at fan. When the fan responds, tap SAVE TO BUTTON.',
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
                  'Code ${testIndex + 1} of ${_candidateAtombergCodes.length}',
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
// 2. V-GUARD WINDLE DECO FAN SCREEN (8-MODE SCANNER)
// ==========================================

class VGuardRemoteScreen extends StatefulWidget {
  const VGuardRemoteScreen({super.key});

  @override
  State<VGuardRemoteScreen> createState() => _VGuardRemoteScreenState();
}

class _VGuardRemoteScreenState extends State<VGuardRemoteScreen> {
  int _mode = 0;

  void _send(String key) {
    List<int> pattern;

    switch (_mode) {
      case 0:
        // Mode 1: NEC 0x00FF (LSB Hardware Order)
        final map = {'POWER': 0x45, 'LED': 0x47, 'SPEED_1': 0x0C, 'SPEED_2': 0x18, 'SPEED_3': 0x5E, 'SPEED_4': 0x08, 'SPEED_5': 0x1C, 'BOOST': 0x5A, 'TIMER_1H': 0x42, 'TIMER_2H': 0x4A, 'TIMER_4H': 0x52};
        pattern = IrEngine.buildNecLsb(0xFF00, map[key] ?? 0x45);
        break;
      case 1:
        // Mode 2: NEC 0x00FF Set B (MSB Order)
        final map = {'POWER': 0x00FF02FD, 'LED': 0x00FF6897, 'SPEED_1': 0x00FF30CF, 'SPEED_2': 0x00FF18E7, 'SPEED_3': 0x00FF7A85, 'SPEED_4': 0x00FF10EF, 'SPEED_5': 0x00FF38C7, 'BOOST': 0x00FF5AA5, 'TIMER_1H': 0x00FF42BD, 'TIMER_2H': 0x00FF4AB5, 'TIMER_4H': 0x00FF52AD};
        pattern = IrEngine.buildNecMsb(map[key] ?? 0x00FF02FD);
        break;
      case 2:
        // Mode 3: NEC 0x00FF Set C (0xA25D Power)
        final map = {'POWER': 0x00FFA25D, 'LED': 0x00FFE21D, 'SPEED_1': 0x00FF22DD, 'SPEED_2': 0x00FF02FD, 'SPEED_3': 0x00FFC23D, 'SPEED_4': 0x00FFE01F, 'SPEED_5': 0x00FFA857, 'BOOST': 0x00FF906F, 'TIMER_1H': 0x00FF6897, 'TIMER_2H': 0x00FF9867, 'TIMER_4H': 0x00FFB04F};
        pattern = IrEngine.buildNecMsb(map[key] ?? 0x00FFA25D);
        break;
      case 3:
        // Mode 4: NEC 0x807F Address
        final map = {'POWER': 0x807F48B7, 'LED': 0x807F8877, 'SPEED_1': 0x807F807F, 'SPEED_2': 0x807F40BF, 'SPEED_3': 0x807FC03F, 'SPEED_4': 0x807F20DF, 'SPEED_5': 0x807FA05F, 'BOOST': 0x807F609F, 'TIMER_1H': 0x807FE01F, 'TIMER_2H': 0x807F10EF, 'TIMER_4H': 0x807F906F};
        pattern = IrEngine.buildNecMsb(map[key] ?? 0x807F48B7);
        break;
      case 4:
        // Mode 5: NEC 0x40BF Address
        final map = {'POWER': 0x40BF00FF, 'LED': 0x40BF40BF, 'SPEED_1': 0x40BF807F, 'SPEED_2': 0x40BFC03F, 'SPEED_3': 0x40BF20DF, 'SPEED_4': 0x40BFA05F, 'SPEED_5': 0x40BF609F, 'BOOST': 0x40BFE01F, 'TIMER_1H': 0x40BF10EF, 'TIMER_2H': 0x40BF906F, 'TIMER_4H': 0x40BF50AF};
        pattern = IrEngine.buildNecMsb(map[key] ?? 0x40BF00FF);
        break;
      case 5:
        // Mode 6: NEC 0x10EF / Crompton-VGuard Shared Board
        final map = {'POWER': 0x10EF38C7, 'LED': 0x10EF58A7, 'SPEED_1': 0x10EFFA05, 'SPEED_2': 0x10EFDA25, 'SPEED_3': 0x10EFF807, 'SPEED_4': 0x10EF7887, 'SPEED_5': 0x10EF5AA5, 'BOOST': 0x10EFBA45, 'TIMER_1H': 0x10EF9867, 'TIMER_2H': 0x10EFB847, 'TIMER_4H': 0x10EFD827};
        pattern = IrEngine.buildNecMsb(map[key] ?? 0x10EF38C7);
        break;
      case 6:
        // Mode 7: Holtek 12-bit Fan IC (Address 0x05)
        final map = {'POWER': 0x501, 'LED': 0x502, 'SPEED_1': 0x504, 'SPEED_2': 0x508, 'SPEED_3': 0x510, 'SPEED_4': 0x520, 'SPEED_5': 0x530, 'BOOST': 0x53F, 'TIMER_1H': 0x503, 'TIMER_2H': 0x505, 'TIMER_4H': 0x509};
        pattern = IrEngine.buildHoltekFan(map[key] ?? 0x501);
        break;
      default:
        // Mode 8: Same 0xCF MSB board as Atomberg (Some V-Guard OEM boards use 0xCF)
        final map = {'POWER': 0xCF8976, 'LED': 0xCF956A, 'SPEED_1': 0xCFD12E, 'SPEED_2': 0xCFC936, 'SPEED_3': 0xCFE11E, 'SPEED_4': 0xCF916E, 'SPEED_5': 0xCF817E, 'BOOST': 0xCFA15E, 'TIMER_1H': 0xCFAD52, 'TIMER_2H': 0xCFDD22, 'TIMER_4H': 0xCF837C};
        pattern = IrEngine.buildNecMsb(map[key] ?? 0xCF8976);
        break;
    }

    IrEngine.sendPattern(context, pattern);
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
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 8,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  return ChoiceChip(
                    label: Text('Mode ${i + 1}'),
                    selected: _mode == i,
                    selectedColor: Colors.amber.shade800,
                    onSelected: (_) => setState(() => _mode = i),
                  );
                },
              ),
            ),
            const Text(
              'Select Mode 1 to 8 above and tap POWER until fan beeps',
              style: TextStyle(fontSize: 11, color: Colors.grey),
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
// 3 & 4. HAIER HS-12NSS3(DCINV) & TCL AC SCREEN
// ==========================================

class AcRemoteScreen extends StatefulWidget {
  final String brand;
  final int maxModes;
  const AcRemoteScreen({super.key, required this.brand, required this.maxModes});

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
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.maxModes,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  return ChoiceChip(
                    label: Text('${widget.brand} Mode ${i + 1}'),
                    selected: _variant == i,
                    selectedColor: Colors.teal,
                    onSelected: (_) => setState(() => _variant = i),
                  );
                },
              ),
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
