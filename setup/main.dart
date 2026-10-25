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
          primary: Color(0xFFFF6700), // Xiaomi Orange
          secondary: Color(0xFF00BFA5),
        ),
      ),
      home: const MiDashboardScreen(),
    );
  }
}

// ==========================================
// DATA MODELS & PRESET DATABASE
// ==========================================

class IrCommand {
  String type; // 'nec' or 'raw'
  String payload;

  IrCommand({required this.type, required this.payload});

  Map<String, dynamic> toJson() => {'type': type, 'payload': payload};

  factory IrCommand.fromJson(Map<String, dynamic> json) => IrCommand(
        type: json['type'] ?? 'nec',
        payload: json['payload'] ?? '0x00000000',
      );
}

class MiRemoteDevice {
  String id;
  String name;
  String brand;
  String category; // 'TV', 'AC', 'FAN'
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

// Built-in Preset Database (TV, AC, Fan)
final List<MiRemoteDevice> builtInPresets = [
  // 1. Atomberg Fan
  MiRemoteDevice(
    id: 'preset_atomberg',
    name: 'Atomberg Fan',
    brand: 'Atomberg',
    category: 'FAN',
    keymap: {
      'POWER': IrCommand(type: 'nec', payload: '0xF300916E'),
      'LED': IrCommand(type: 'nec', payload: '0xF3000AF5'),
      'SPEED_1': IrCommand(type: 'nec', payload: '0xF30004FB'),
      'SPEED_2': IrCommand(type: 'nec', payload: '0xF30005FA'),
      'SPEED_3': IrCommand(type: 'nec', payload: '0xF30006F9'),
      'SPEED_4': IrCommand(type: 'nec', payload: '0xF30007F8'),
      'SPEED_5': IrCommand(type: 'nec', payload: '0xF30008F7'),
      'BOOST': IrCommand(type: 'nec', payload: '0xF30009F6'),
      'SLEEP': IrCommand(type: 'nec', payload: '0xF3000BF4'),
      'TIMER_1H': IrCommand(type: 'nec', payload: '0xF3000CF3'),
      'TIMER_2H': IrCommand(type: 'nec', payload: '0xF3000DF2'),
      'TIMER_3H': IrCommand(type: 'nec', payload: '0xF3000EF1'),
      'TIMER_6H': IrCommand(type: 'nec', payload: '0xF3000FF0'),
    },
  ),
  // 2. Orient / Crompton Fan
  MiRemoteDevice(
    id: 'preset_orient',
    name: 'Orient BLDC Fan',
    brand: 'Orient',
    category: 'FAN',
    keymap: {
      'POWER': IrCommand(type: 'nec', payload: '0x00FF02FD'),
      'LED': IrCommand(type: 'nec', payload: '0x00FF6897'),
      'SPEED_1': IrCommand(type: 'nec', payload: '0x00FF22DD'),
      'SPEED_2': IrCommand(type: 'nec', payload: '0x00FF02FD'),
      'SPEED_3': IrCommand(type: 'nec', payload: '0x00FFC23D'),
      'SPEED_4': IrCommand(type: 'nec', payload: '0x00FFE01F'),
      'SPEED_5': IrCommand(type: 'nec', payload: '0x00FFA857'),
      'BOOST': IrCommand(type: 'nec', payload: '0x00FF906F'),
      'SLEEP': IrCommand(type: 'nec', payload: '0x00FF9867'),
      'TIMER_1H': IrCommand(type: 'nec', payload: '0x00FFB04F'),
      'TIMER_2H': IrCommand(type: 'nec', payload: '0x00FF30CF'),
      'TIMER_3H': IrCommand(type: 'nec', payload: '0x00FF18E7'),
      'TIMER_6H': IrCommand(type: 'nec', payload: '0x00FF7A85'),
    },
  ),
  // 3. LG / Mi / Samsung Smart TV
  MiRemoteDevice(
    id: 'preset_lg_tv',
    name: 'Living Room TV',
    brand: 'LG / Generic TV',
    category: 'TV',
    keymap: {
      'POWER': IrCommand(type: 'nec', payload: '0x20DF10EF'),
      'MUTE': IrCommand(type: 'nec', payload: '0x20DF906F'),
      'SOURCE': IrCommand(type: 'nec', payload: '0x20DFD02F'),
      'UP': IrCommand(type: 'nec', payload: '0x20DF02FD'),
      'DOWN': IrCommand(type: 'nec', payload: '0x20DF827D'),
      'LEFT': IrCommand(type: 'nec', payload: '0x20DFE01F'),
      'RIGHT': IrCommand(type: 'nec', payload: '0x20DF609F'),
      'OK': IrCommand(type: 'nec', payload: '0x20DF22DD'),
      'VOL_UP': IrCommand(type: 'nec', payload: '0x20DF40BF'),
      'VOL_DOWN': IrCommand(type: 'nec', payload: '0x20DFC03F'),
      'CH_UP': IrCommand(type: 'nec', payload: '0x20DF00FF'),
      'CH_DOWN': IrCommand(type: 'nec', payload: '0x20DF807F'),
      'HOME': IrCommand(type: 'nec', payload: '0x20DF3EC1'),
      'BACK': IrCommand(type: 'nec', payload: '0x20DF14EB'),
      'MENU': IrCommand(type: 'nec', payload: '0x20DFC23D'),
    },
  ),
  // 4. LG / Voltas Split AC
  MiRemoteDevice(
    id: 'preset_lg_ac',
    name: 'Bedroom AC',
    brand: 'LG / Voltas',
    category: 'AC',
    keymap: {
      'POWER_ON': IrCommand(type: 'nec', payload: '0x880094D0'),
      'POWER_OFF': IrCommand(type: 'nec', payload: '0x88C00510'),
      'MODE': IrCommand(type: 'nec', payload: '0x88089450'),
      'FAN_SPEED': IrCommand(type: 'nec', payload: '0x8808A460'),
      'SWING': IrCommand(type: 'nec', payload: '0x88131490'),
      'TEMP_18': IrCommand(type: 'nec', payload: '0x880834F0'),
      'TEMP_19': IrCommand(type: 'nec', payload: '0x88084400'),
      'TEMP_20': IrCommand(type: 'nec', payload: '0x88085410'),
      'TEMP_21': IrCommand(type: 'nec', payload: '0x88086420'),
      'TEMP_22': IrCommand(type: 'nec', payload: '0x88087430'),
      'TEMP_23': IrCommand(type: 'nec', payload: '0x88088440'),
      'TEMP_24': IrCommand(type: 'nec', payload: '0x88089450'),
      'TEMP_25': IrCommand(type: 'nec', payload: '0x8808A460'),
      'TEMP_26': IrCommand(type: 'nec', payload: '0x8808B470'),
      'TEMP_27': IrCommand(type: 'nec', payload: '0x8808C480'),
      'TEMP_28': IrCommand(type: 'nec', payload: '0x8808D490'),
    },
  ),
];

// ==========================================
// IR TRANSMITTER SERVICE
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

  static List<int> buildNecPattern(int hexCode) {
    final List<int> pattern = [9000, 4500];
    for (int i = 31; i >= 0; i--) {
      final int bit = (hexCode >> i) & 1;
      pattern.add(560);
      pattern.add(bit == 1 ? 1690 : 560);
    }
    pattern.add(560);
    return pattern;
  }

  static Future<void> transmit(BuildContext context, int frequency, IrCommand? cmd) async {
    HapticFeedback.lightImpact();
    if (cmd == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No IR code assigned. Long-press button to set code.')),
      );
      return;
    }

    try {
      List<int> pattern = [];
      if (cmd.type == 'nec') {
        final clean = cmd.payload.trim().replaceAll('0x', '').replaceAll('0X', '');
        final val = int.parse(clean, radix: 16);
        pattern = buildNecPattern(val);
      } else {
        pattern = cmd.payload.split(',').map((e) => int.parse(e.trim())).toList();
      }

      await platform.invokeMethod('transmit', {
        'frequency': frequency,
        'pattern': pattern,
      });
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('IR Transmit Error: $e')),
      );
    }
  }
}

// ==========================================
// SCREEN 1: MI REMOTE HOME DASHBOARD
// ==========================================

class MiDashboardScreen extends StatefulWidget {
  const MiDashboardScreen({super.key});

  @override
  State<MiDashboardScreen> createState() => _MiDashboardScreenState();
}

class _MiDashboardScreenState extends State<MiDashboardScreen> {
  static const String _storageKey = 'mi_remote_saved_devices_v2';
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

    // Default initial remotes
    setState(() {
      _hasIr = ir;
      _remotes = [
        MiRemoteDevice.fromJson(builtInPresets[0].toJson()),
        MiRemoteDevice.fromJson(builtInPresets[2].toJson()),
        MiRemoteDevice.fromJson(builtInPresets[3].toJson()),
      ];
    });
    _saveRemotes();
  }

  Future<void> _saveRemotes() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_remotes.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'TV':
        return Icons.tv;
      case 'AC':
        return Icons.ac_unit;
      case 'FAN':
      default:
        return Icons.wind_power;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'TV':
        return Colors.blueAccent;
      case 'AC':
        return Colors.tealAccent.shade700;
      case 'FAN':
      default:
        return const Color(0xFFFF6700);
    }
  }

  void _showJsonBackupModal() {
    final currentJson = const JsonEncoder.withIndent('  ')
        .convert(_remotes.map((e) => e.toJson()).toList());
    final ctrl = TextEditingController(text: currentJson);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222B),
        title: const Text('Backup & Restore (JSON)'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: ctrl,
            maxLines: 10,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: ctrl.text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('JSON Copied to Clipboard!')),
              );
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.restore, size: 18),
            label: const Text('Restore'),
            onPressed: () {
              try {
                final List<dynamic> decoded = jsonDecode(ctrl.text);
                final imported = decoded.map((e) => MiRemoteDevice.fromJson(e)).toList();
                setState(() => _remotes = imported);
                _saveRemotes();
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Remotes Restored Successfully!')),
                );
              } catch (_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid JSON data!')),
                );
              }
            },
          ),
        ],
      ),
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
            tooltip: 'Backup / Restore JSON',
            icon: const Icon(Icons.import_export),
            onPressed: _showJsonBackupModal,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              _hasIr ? '● IR Blaster Ready' : '● No IR Blaster Detected on Phone',
              style: TextStyle(
                fontSize: 11,
                color: _hasIr ? Colors.greenAccent : Colors.orangeAccent,
              ),
            ),
          ),
        ),
      ),
      body: _remotes.isEmpty
          ? const Center(
              child: Text('No remotes added yet. Tap + to add a remote.'),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _remotes.length,
              itemBuilder: (context, index) {
                final remote = _remotes[index];
                return Card(
                  color: const Color(0xFF1C2029),
                  margin: const EdgeInsets.only(bottom: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    leading: CircleAvatar(
                      radius: 26,
                      backgroundColor: _getCategoryColor(remote.category).withOpacity(0.2),
                      child: Icon(
                        _getCategoryIcon(remote.category),
                        color: _getCategoryColor(remote.category),
                        size: 28,
                      ),
                    ),
                    title: Text(
                      remote.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                    ),
                    subtitle: Text(
                      '${remote.brand} • ${remote.category}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () {
                        setState(() => _remotes.removeAt(index));
                        _saveRemotes();
                      },
                    ),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RemoteControlContainer(
                            device: remote,
                            onSave: _saveRemotes,
                          ),
                        ),
                      );
                      setState(() {});
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFFF6700),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Remote', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () async {
          final MiRemoteDevice? newDevice = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddRemoteWizardScreen()),
          );
          if (newDevice != null) {
            setState(() => _remotes.add(newDevice));
            _saveRemotes();
          }
        },
      ),
    );
  }
}

// ==========================================
// SCREEN 2: MI REMOTE "ADD REMOTE" WIZARD
// ==========================================

class AddRemoteWizardScreen extends StatefulWidget {
  const AddRemoteWizardScreen({super.key});

  @override
  State<AddRemoteWizardScreen> createState() => _AddRemoteWizardScreenState();
}

class _AddRemoteWizardScreenState extends State<AddRemoteWizardScreen> {
  String? _selectedCategory;
  MiRemoteDevice? _selectedPreset;
  bool _respondedYes = false;
  final TextEditingController _customNameCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Remote')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _selectedCategory == null
            ? _buildCategoryStep()
            : _selectedPreset == null
                ? _buildBrandStep()
                : _buildTestStep(),
      ),
    );
  }

  Widget _buildCategoryStep() {
    final categories = [
      {'cat': 'TV', 'name': 'TV / Mi TV', 'icon': Icons.tv, 'color': Colors.blueAccent},
      {'cat': 'AC', 'name': 'Air Conditioner', 'icon': Icons.ac_unit, 'color': Colors.tealAccent},
      {'cat': 'FAN', 'name': 'Smart / BLDC Fan', 'icon': Icons.wind_power, 'color': const Color(0xFFFF6700)},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Appliance Category',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.2,
            ),
            itemCount: categories.length,
            itemBuilder: (ctx, i) {
              final item = categories[i];
              return InkWell(
                onTap: () => setState(() => _selectedCategory = item['cat'] as String),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C2029),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item['icon'] as IconData, size: 42, color: item['color'] as Color),
                      const SizedBox(height: 12),
                      Text(
                        item['name'] as String,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBrandStep() {
    final filtered = builtInPresets.where((p) => p.category == _selectedCategory).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _selectedCategory = null),
            ),
            Text(
              'Select $_selectedCategory Brand',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final preset = filtered[i];
              return Card(
                color: const Color(0xFF1C2029),
                child: ListTile(
                  title: Text(preset.brand, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(preset.name),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    setState(() {
                      _selectedPreset = MiRemoteDevice.fromJson(preset.toJson());
                      _selectedPreset!.id = DateTime.now().millisecondsSinceEpoch.toString();
                      _customNameCtrl.text = preset.name;
                    });
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTestStep() {
    final powerCmd = _selectedPreset!.keymap['POWER'] ?? _selectedPreset!.keymap['POWER_ON'];

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Point phone at device & tap Power button',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Long press any button later inside the remote to customize its hex/raw IR code.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 36),
        SizedBox(
          width: 110,
          height: 110,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6700),
              shape: const CircleBorder(),
              elevation: 8,
            ),
            onPressed: () => IrService.transmit(context, _selectedPreset!.frequency, powerCmd),
            child: const Icon(Icons.power_settings_new, size: 48, color: Colors.white),
          ),
        ),
        const SizedBox(height: 36),
        if (!_respondedYes) ...[
          const Text('Does the device respond?', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              OutlinedButton(
                onPressed: () => setState(() => _respondedYes = true),
                child: const Text('Skip / Customize Later'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () => setState(() => _respondedYes = true),
                child: const Text('Yes, It Works!'),
              ),
            ],
          ),
        ] else ...[
          TextField(
            controller: _customNameCtrl,
            decoration: const InputDecoration(
              labelText: 'Remote Room / Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6700)),
              onPressed: () {
                if (_customNameCtrl.text.trim().isNotEmpty) {
                  _selectedPreset!.name = _customNameCtrl.text.trim();
                }
                Navigator.pop(context, _selectedPreset);
              },
              child: const Text('Pair & Save Remote', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ],
    );
  }
}

// ==========================================
// SCREEN 3: REMOTE CONTROL UI CONTAINER
// ==========================================

class RemoteControlContainer extends StatefulWidget {
  final MiRemoteDevice device;
  final VoidCallback onSave;

  const RemoteControlContainer({
    super.key,
    required this.device,
    required this.onSave,
  });

  @override
  State<RemoteControlContainer> createState() => _RemoteControlContainerState();
}

class _RemoteControlContainerState extends State<RemoteControlContainer> {
  // AC State
  bool _acPower = true;
  int _acTemp = 24;
  String _acMode = 'COOL';
  String _acFan = 'AUTO';
  bool _acSwing = true;

  void _fireKey(String keyName) {
    final cmd = widget.device.keymap[keyName];
    IrService.transmit(context, widget.device.frequency, cmd);
  }

  // Long Press any button to edit its IR code
  void _editKeyCode(String keyName) {
    final existing = widget.device.keymap[keyName];
    String selectedType = existing?.type ?? 'nec';
    final payloadCtrl = TextEditingController(text: existing?.payload ?? '0xF300916E');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF1E222B),
          title: Text('Edit IR Code: $keyName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedType,
                decoration: const InputDecoration(labelText: 'Protocol Type'),
                items: const [
                  DropdownMenuItem(value: 'nec', child: Text('NEC 32-bit Hex')),
                  DropdownMenuItem(value: 'raw', child: Text('Raw Microsecond Pulses')),
                ],
                onChanged: (v) {
                  if (v != null) setModalState(() => selectedType = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: payloadCtrl,
                maxLines: selectedType == 'raw' ? 3 : 1,
                decoration: InputDecoration(
                  labelText: selectedType == 'nec'
                      ? 'Hex (e.g. 0xF300916E)'
                      : 'Raw Pulses (e.g. 9000,4500,560...)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  widget.device.keymap[keyName] = IrCommand(
                    type: selectedType,
                    payload: payloadCtrl.text.trim(),
                  );
                });
                widget.onSave();
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Updated $keyName IR code!')),
                );
              },
              child: const Text('Save Code'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miBtn({
    required String label,
    required String keyName,
    IconData? icon,
    Color? bgColor,
    Color? fgColor,
    double size = 68,
  }) {
    return GestureDetector(
      onLongPress: () => _editKeyCode(keyName),
      child: SizedBox(
        width: size,
        height: size,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: bgColor ?? const Color(0xFF222630),
            foregroundColor: fgColor ?? Colors.white,
            shape: const CircleBorder(),
            elevation: 4,
            padding: EdgeInsets.zero,
          ),
          onPressed: () => _fireKey(keyName),
          child: icon != null
              ? Icon(icon, size: 26)
              : Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(widget.device.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const Text(
              'Long-press any button to edit IR code',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: widget.device.category == 'TV'
              ? _buildTvRemote()
              : widget.device.category == 'AC'
                  ? _buildAcRemote()
                  : _buildFanRemote(),
        ),
      ),
    );
  }

  // ==========================================
  // LAYOUT 1: XIAOMI MI TV REMOTE LAYOUT
  // ==========================================
  Widget _buildTvRemote() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Top Row: Power, Source, Mute
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _miBtn(label: 'PWR', keyName: 'POWER', icon: Icons.power_settings_new, bgColor: Colors.redAccent),
            _miBtn(label: 'INPUT', keyName: 'SOURCE', icon: Icons.input),
            _miBtn(label: 'MUTE', keyName: 'MUTE', icon: Icons.volume_off),
          ],
        ),

        // Volume & Channel Pill Rockers + Home/Menu
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Volume Rocker
            Container(
              width: 68,
              height: 160,
              decoration: BoxDecoration(
                color: const Color(0xFF222630),
                borderRadius: BorderRadius.circular(40),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _miBtn(label: '+', keyName: 'VOL_UP', icon: Icons.add, bgColor: Colors.transparent),
                  const Text('VOL', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  _miBtn(label: '-', keyName: 'VOL_DOWN', icon: Icons.remove, bgColor: Colors.transparent),
                ],
              ),
            ),

            // Center Menu / Home / Back
            Column(
              children: [
                _miBtn(label: 'HOME', keyName: 'HOME', icon: Icons.home_outlined, size: 60),
                const SizedBox(height: 16),
                _miBtn(label: 'MENU', keyName: 'MENU', icon: Icons.menu, size: 60),
                const SizedBox(height: 16),
                _miBtn(label: 'BACK', keyName: 'BACK', icon: Icons.keyboard_return, size: 60),
              ],
            ),

            // Channel Rocker
            Container(
              width: 68,
              height: 160,
              decoration: BoxDecoration(
                color: const Color(0xFF222630),
                borderRadius: BorderRadius.circular(40),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _miBtn(label: 'CH+', keyName: 'CH_UP', icon: Icons.keyboard_arrow_up, bgColor: Colors.transparent),
                  const Text('CH', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  _miBtn(label: 'CH-', keyName: 'CH_DOWN', icon: Icons.keyboard_arrow_down, bgColor: Colors.transparent),
                ],
              ),
            ),
          ],
        ),

        // Circular Navigation D-Pad
        Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1C2029),
            border: Border.all(color: Colors.white12, width: 2),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                top: 8,
                child: _miBtn(label: 'UP', keyName: 'UP', icon: Icons.keyboard_arrow_up, bgColor: Colors.transparent, size: 60),
              ),
              Positioned(
                bottom: 8,
                child: _miBtn(label: 'DOWN', keyName: 'DOWN', icon: Icons.keyboard_arrow_down, bgColor: Colors.transparent, size: 60),
              ),
              Positioned(
                left: 8,
                child: _miBtn(label: 'LEFT', keyName: 'LEFT', icon: Icons.keyboard_arrow_left, bgColor: Colors.transparent, size: 60),
              ),
              Positioned(
                right: 8,
                child: _miBtn(label: 'RIGHT', keyName: 'RIGHT', icon: Icons.keyboard_arrow_right, bgColor: Colors.transparent, size: 60),
              ),
              _miBtn(label: 'OK', keyName: 'OK', bgColor: const Color(0xFF2C313E), size: 76),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // LAYOUT 2: XIAOMI MI AC REMOTE LAYOUT
  // ==========================================
  Widget _buildAcRemote() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // AC Digital LCD Display Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _acPower
                  ? [const Color(0xFF004D40), const Color(0xFF1C2029)]
                  : [const Color(0xFF222630), const Color(0xFF181B22)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.tealAccent.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('MODE: $_acMode', style: const TextStyle(color: Colors.tealAccent, fontSize: 12)),
                  Text('FAN: $_acFan', style: const TextStyle(color: Colors.tealAccent, fontSize: 12)),
                  Text(_acSwing ? 'SWING: ON' : 'SWING: OFF', style: const TextStyle(color: Colors.tealAccent, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                _acPower ? '$_acTemp°C' : 'OFF',
                style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w300, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text('Target Temperature', style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),

        // Temp + / - Controls
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF222630),
                  shape: const CircleBorder(),
                ),
                onPressed: () {
                  setState(() => _acTemp = (_acTemp - 1).clamp(18, 28));
                  _fireKey('TEMP_$_acTemp');
                },
                onLongPress: () => _editKeyCode('TEMP_$_acTemp'),
                child: const Text('TEMP -', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            GestureDetector(
              onLongPress: () => _editKeyCode(_acPower ? 'POWER_OFF' : 'POWER_ON'),
              child: SizedBox(
                width: 90,
                height: 90,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _acPower ? Colors.redAccent : Colors.teal,
                    shape: const CircleBorder(),
                  ),
                  onPressed: () {
                    setState(() => _acPower = !_acPower);
                    _fireKey(_acPower ? 'POWER_ON' : 'POWER_OFF');
                  },
                  child: const Icon(Icons.power_settings_new, size: 38, color: Colors.white),
                ),
              ),
            ),
            SizedBox(
              width: 80,
              height: 80,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF222630),
                  shape: const CircleBorder(),
                ),
                onPressed: () {
                  setState(() => _acTemp = (_acTemp + 1).clamp(18, 28));
                  _fireKey('TEMP_$_acTemp');
                },
                onLongPress: () => _editKeyCode('TEMP_$_acTemp'),
                child: const Text('TEMP +', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),

        // Mode, Fan Speed, Swing Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _miBtn(
              label: 'MODE',
              keyName: 'MODE',
              size: 74,
            ),
            _miBtn(
              label: 'FAN',
              keyName: 'FAN_SPEED',
              size: 74,
            ),
            _miBtn(
              label: 'SWING',
              keyName: 'SWING',
              size: 74,
            ),
          ],
        ),
      ],
    );
  }

  // ==========================================
  // LAYOUT 3: SMART BLDC FAN REMOTE LAYOUT
  // ==========================================
  Widget _buildFanRemote() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _miBtn(
              label: 'POWER',
              keyName: 'POWER',
              icon: Icons.power_settings_new,
              bgColor: Colors.redAccent,
              size: 84,
            ),
            _miBtn(
              label: 'LED',
              keyName: 'LED',
              icon: Icons.lightbulb_outline,
              bgColor: const Color(0xFFFF6700),
              size: 84,
            ),
          ],
        ),
        const Text('FAN SPEED', style: TextStyle(color: Colors.grey, letterSpacing: 1.5, fontSize: 12)),
        Wrap(
          spacing: 18,
          runSpacing: 18,
          alignment: WrapAlignment.center,
          children: [
            _miBtn(label: '1', keyName: 'SPEED_1'),
            _miBtn(label: '2', keyName: 'SPEED_2'),
            _miBtn(label: '3', keyName: 'SPEED_3'),
            _miBtn(label: '4', keyName: 'SPEED_4'),
            _miBtn(label: '5', keyName: 'SPEED_5'),
            _miBtn(label: 'BOOST', keyName: 'BOOST', bgColor: Colors.blueAccent),
          ],
        ),
        const Text('TIMER & SLEEP', style: TextStyle(color: Colors.grey, letterSpacing: 1.5, fontSize: 12)),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          alignment: WrapAlignment.center,
          children: [
            _miBtn(label: 'SLEEP', keyName: 'SLEEP', size: 62),
            _miBtn(label: '1H', keyName: 'TIMER_1H', size: 62),
            _miBtn(label: '2H', keyName: 'TIMER_2H', size: 62),
            _miBtn(label: '3H', keyName: 'TIMER_3H', size: 62),
            _miBtn(label: '6H', keyName: 'TIMER_6H', size: 62),
          ],
        ),
      ],
    );
  }
}
