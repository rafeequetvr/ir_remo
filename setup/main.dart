import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const UniversalIrApp());
}

class UniversalIrApp extends StatelessWidget {
  const UniversalIrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Universal IR Remote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF14161B),
        colorScheme: const ColorScheme.dark(
          primary: Colors.amber,
          secondary: Colors.blueAccent,
        ),
      ),
      home: const RemoteHomeScreen(),
    );
  }
}

class IrButtonModel {
  String label;
  String type;
  String payload;
  int colorValue;

  IrButtonModel({
    required this.label,
    required this.type,
    required this.payload,
    this.colorValue = 0xFF262A34,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'type': type,
        'payload': payload,
        'colorValue': colorValue,
      };

  factory IrButtonModel.fromJson(Map<String, dynamic> json) => IrButtonModel(
        label: json['label'] ?? 'BTN',
        type: json['type'] ?? 'nec',
        payload: json['payload'] ?? '0x00000000',
        colorValue: json['colorValue'] ?? 0xFF262A34,
      );
}

class RemoteProfileModel {
  String name;
  int frequency;
  List<IrButtonModel> buttons;

  RemoteProfileModel({
    required this.name,
    this.frequency = 38000,
    required this.buttons,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'frequency': frequency,
        'buttons': buttons.map((b) => b.toJson()).toList(),
      };

  factory RemoteProfileModel.fromJson(Map<String, dynamic> json) =>
      RemoteProfileModel(
        name: json['name'] ?? 'New Remote',
        frequency: json['frequency'] ?? 38000,
        buttons: (json['buttons'] as List<dynamic>? ?? [])
            .map((b) => IrButtonModel.fromJson(b))
            .toList(),
      );
}

class RemoteHomeScreen extends StatefulWidget {
  const RemoteHomeScreen({super.key});

  @override
  State<RemoteHomeScreen> createState() => _RemoteHomeScreenState();
}

class _RemoteHomeScreenState extends State<RemoteHomeScreen> {
  static const platform = MethodChannel('com.custom.ir_remote/ir');
  static const String _storageKey = 'saved_ir_remotes_v1';

  List<RemoteProfileModel> _profiles = [];
  int _selectedIndex = 0;
  bool _hasIr = false;

  @override
  void initState() {
    super.initState();
    _checkIrSupport();
    _loadProfiles();
  }

  Future<void> _checkIrSupport() async {
    try {
      final bool res = await platform.invokeMethod('hasIrEmitter');
      setState(() => _hasIr = res);
    } catch (_) {
      setState(() => _hasIr = false);
    }
  }

  Future<void> _loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final String? rawJson = prefs.getString(_storageKey);

    if (rawJson != null && rawJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(rawJson);
        setState(() {
          _profiles = decoded.map((e) => RemoteProfileModel.fromJson(e)).toList();
          _selectedIndex = 0;
        });
        return;
      } catch (_) {}
    }

    setState(() {
      _profiles = [_getDefaultAtombergProfile()];
      _selectedIndex = 0;
    });
    _saveProfiles();
  }

  Future<void> _saveProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_profiles.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }

  RemoteProfileModel _getDefaultAtombergProfile() {
    return RemoteProfileModel(
      name: 'Atomberg Fan',
      frequency: 38000,
      buttons: [
        IrButtonModel(label: 'POWER', type: 'nec', payload: '0xF300916E', colorValue: 0xFFE53935),
        IrButtonModel(label: 'LED', type: 'nec', payload: '0xF3000AF5', colorValue: 0xFFFF8F00),
        IrButtonModel(label: 'SPEED 1', type: 'nec', payload: '0xF30004FB'),
        IrButtonModel(label: 'SPEED 2', type: 'nec', payload: '0xF30005FA'),
        IrButtonModel(label: 'SPEED 3', type: 'nec', payload: '0xF30006F9'),
        IrButtonModel(label: 'SPEED 4', type: 'nec', payload: '0xF30007F8'),
        IrButtonModel(label: 'SPEED 5', type: 'nec', payload: '0xF30008F7'),
        IrButtonModel(label: 'BOOST', type: 'nec', payload: '0xF30009F6', colorValue: 0xFF1E88E5),
        IrButtonModel(label: 'SLEEP', type: 'nec', payload: '0xF3000BF4'),
        IrButtonModel(label: 'TIMER 1H', type: 'nec', payload: '0xF3000CF3'),
        IrButtonModel(label: 'TIMER 2H', type: 'nec', payload: '0xF3000DF2'),
        IrButtonModel(label: 'TIMER 3H', type: 'nec', payload: '0xF3000EF1'),
        IrButtonModel(label: 'TIMER 6H', type: 'nec', payload: '0xF3000FF0'),
      ],
    );
  }

  List<int> _buildNecPattern(int hexCode) {
    final List<int> pattern = [9000, 4500];
    for (int i = 31; i >= 0; i--) {
      final int bit = (hexCode >> i) & 1;
      pattern.add(560);
      pattern.add(bit == 1 ? 1690 : 560);
    }
    pattern.add(560);
    return pattern;
  }

  Future<void> _transmitButton(IrButtonModel btn) async {
    HapticFeedback.lightImpact();
    final currentRemote = _profiles[_selectedIndex];
    List<int> pattern = [];

    try {
      if (btn.type == 'nec') {
        final String cleanHex = btn.payload.trim().replaceAll('0x', '').replaceAll('0X', '');
        final int hexVal = int.parse(cleanHex, radix: 16);
        pattern = _buildNecPattern(hexVal);
      } else {
        pattern = btn.payload
            .split(',')
            .map((s) => int.parse(s.trim()))
            .toList();
      }

      await platform.invokeMethod('transmit', {
        'frequency': currentRemote.frequency,
        'pattern': pattern,
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid IR Code Format: $e')),
      );
    }
  }

  void _showButtonDialog({IrButtonModel? existingBtn, int? btnIndex}) {
    final labelCtrl = TextEditingController(text: existingBtn?.label ?? '');
    final payloadCtrl = TextEditingController(text: existingBtn?.payload ?? '0xF300');
    String selectedType = existingBtn?.type ?? 'nec';
    int selectedColor = existingBtn?.colorValue ?? 0xFF262A34;

    final List<int> colorOptions = [
      0xFF262A34,
      0xFFE53935,
      0xFF1E88E5,
      0xFF43A047,
      0xFFFF8F00,
      0xFF8E24AA,
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E222B),
          title: Text(existingBtn == null ? 'Add Button' : 'Edit Button'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Button Label (e.g. POWER, 24°C)',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(labelText: 'Signal Type'),
                  items: const [
                    DropdownMenuItem(value: 'nec', child: Text('NEC Hex (e.g. 0xF300916E)')),
                    DropdownMenuItem(value: 'raw', child: Text('Raw Pulses (e.g. 9000,4500...)')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedType = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: payloadCtrl,
                  decoration: InputDecoration(
                    labelText: selectedType == 'nec'
                        ? 'Hex Code (e.g. 0xF300916E)'
                        : 'Raw Array (Comma separated)',
                  ),
                  maxLines: selectedType == 'raw' ? 3 : 1,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  children: colorOptions.map((c) {
                    return GestureDetector(
                      onTap: () => setDialogState(() => selectedColor = c),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: Color(c),
                        child: selectedColor == c
                            ? const Icon(Icons.check, size: 16, color: Colors.white)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            if (existingBtn != null && btnIndex != null)
              TextButton(
                onPressed: () {
                  setState(() {
                    _profiles[_selectedIndex].buttons.removeAt(btnIndex);
                  });
                  _saveProfiles();
                  Navigator.pop(ctx);
                },
                child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (labelCtrl.text.trim().isEmpty || payloadCtrl.text.trim().isEmpty) return;
                final newBtn = IrButtonModel(
                  label: labelCtrl.text.trim(),
                  type: selectedType,
                  payload: payloadCtrl.text.trim(),
                  colorValue: selectedColor,
                );
                setState(() {
                  if (btnIndex != null) {
                    _profiles[_selectedIndex].buttons[btnIndex] = newBtn;
                  } else {
                    _profiles[_selectedIndex].buttons.add(newBtn);
                  }
                });
                _saveProfiles();
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddRemoteDialog() {
    final nameCtrl = TextEditingController();
    final freqCtrl = TextEditingController(text: '38000');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222B),
        title: const Text('Add New Remote'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Remote Name (e.g. Bedroom AC)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: freqCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Frequency Hz (Default: 38000)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) return;
              setState(() {
                _profiles.add(RemoteProfileModel(
                  name: nameCtrl.text.trim(),
                  frequency: int.tryParse(freqCtrl.text.trim()) ?? 38000,
                  buttons: [],
                ));
                _selectedIndex = _profiles.length - 1;
              });
              _saveProfiles();
              Navigator.pop(ctx);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showJsonBackupDialog() {
    final String currentJson = const JsonEncoder.withIndent('  ')
        .convert(_profiles.map((e) => e.toJson()).toList());
    final jsonCtrl = TextEditingController(text: currentJson);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222B),
        title: const Text('JSON Backup (Export / Import)'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Copy this JSON to backup your remotes, or paste a JSON backup below and tap Import:',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: jsonCtrl,
                maxLines: 10,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy JSON'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonCtrl.text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('JSON copied to clipboard!')),
              );
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Import JSON'),
            onPressed: () {
              try {
                final List<dynamic> parsed = jsonDecode(jsonCtrl.text);
                final imported = parsed.map((e) => RemoteProfileModel.fromJson(e)).toList();
                if (imported.isEmpty) throw Exception('Empty list');
                setState(() {
                  _profiles = imported;
                  _selectedIndex = 0;
                });
                _saveProfiles();
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Remotes imported successfully!')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid JSON format!')),
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
    if (_profiles.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final currentRemote = _profiles[_selectedIndex];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222B),
        title: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: _selectedIndex,
            dropdownColor: const Color(0xFF232732),
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            icon: const Icon(Icons.arrow_drop_down, color: Colors.amber),
            items: List.generate(_profiles.length, (i) {
              return DropdownMenuItem(value: i, child: Text(_profiles[i].name));
            }),
            onChanged: (val) {
              if (val != null) setState(() => _selectedIndex = val);
            },
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Add Remote',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _showAddRemoteDialog,
          ),
          IconButton(
            tooltip: 'JSON Export / Import',
            icon: const Icon(Icons.import_export),
            onPressed: _showJsonBackupDialog,
          ),
          if (_profiles.length > 1)
            IconButton(
              tooltip: 'Delete Remote',
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () {
                setState(() {
                  _profiles.removeAt(_selectedIndex);
                  _selectedIndex = 0;
                });
                _saveProfiles();
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              _hasIr
                  ? '● IR Blaster Ready (${currentRemote.frequency} Hz) • Long press button to edit'
                  : '● No IR Blaster Detected • Long press button to edit',
              style: TextStyle(
                color: _hasIr ? Colors.greenAccent : Colors.orangeAccent,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.0,
          ),
          itemCount: currentRemote.buttons.length,
          itemBuilder: (context, index) {
            final btn = currentRemote.buttons[index];
            return GestureDetector(
              onLongPress: () => _showButtonDialog(existingBtn: btn, btnIndex: index),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(btn.colorValue),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 4,
                ),
                onPressed: () => _transmitButton(btn),
                child: Text(
                  btn.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.amber,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Add Button', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => _showButtonDialog(),
      ),
    );
  }
}
