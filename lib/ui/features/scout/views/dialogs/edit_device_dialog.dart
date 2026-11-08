import 'package:flutter/material.dart';
import 'package:network_suite_shared/network_suite_shared.dart';

class EditDeviceDialog extends StatefulWidget {
  const EditDeviceDialog({
    super.key,
    required this.macAddress,
    this.initialName,
    this.initialCategory,
    this.initialVendor,
    this.initialNotes,
    required this.onSave,
  });

  final String macAddress;
  final String? initialName;
  final String? initialCategory;
  final String? initialVendor;
  final String? initialNotes;
  final void Function({
    required String mac,
    required String name,
    String? category,
    String? vendor,
    String? notes,
  }) onSave;

  @override
  State<EditDeviceDialog> createState() => _EditDeviceDialogState();
}

class _EditDeviceDialogState extends State<EditDeviceDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _vendorCtrl;
  late final TextEditingController _notesCtrl;
  String _selectedCategoryKey = 'other';

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
    _vendorCtrl = TextEditingController(text: widget.initialVendor ?? '');
    _notesCtrl = TextEditingController(text: widget.initialNotes ?? '');
    _selectedCategoryKey = widget.initialCategory ?? 'other';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _vendorCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentCat = DeviceCategory.fromKey(_selectedCategoryKey);

    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFF38BDF8),
                    radius: 14,
                    child: Icon(currentCat.icon, size: 16, color: Colors.black),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Edit Device in Shared Library',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // MAC Address (read-only)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF252526),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF3E3E42)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.memory, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    const Text('MAC: ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(
                      widget.macAddress,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Device Friendly Name
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Friendly Device Name *',
                  hintText: 'e.g. Primary Gateway, Living Room Apple TV',
                  prefixIcon: Icon(Icons.label_outline, size: 18),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),

              // Category Selector Dropdown
              DropdownButtonFormField<String>(
                initialValue: _selectedCategoryKey,
                dropdownColor: const Color(0xFF252526),
                decoration: const InputDecoration(
                  labelText: 'Device Category',
                  prefixIcon: Icon(Icons.category_outlined, size: 18),
                  border: OutlineInputBorder(),
                ),
                items: DeviceCategory.values.map((cat) {
                  return DropdownMenuItem<String>(
                    value: cat.key,
                    child: Row(
                      children: [
                        Icon(cat.icon, size: 16, color: const Color(0xFF38BDF8)),
                        const SizedBox(width: 8),
                        Text(cat.label, style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedCategoryKey = val);
                  }
                },
              ),
              const SizedBox(height: 14),

              // Vendor (Optional)
              TextField(
                controller: _vendorCtrl,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Hardware Vendor',
                  hintText: 'e.g. Ubiquiti, Apple, Cisco',
                  prefixIcon: Icon(Icons.business, size: 18),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),

              // Notes (Optional)
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Notes & Inventory Info',
                  hintText: 'e.g. Rack 2, Port 4, 10GbE SFP+',
                  prefixIcon: Icon(Icons.notes, size: 18),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Save to Library'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF38BDF8),
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () {
                      final name = _nameCtrl.text.trim();
                      if (name.isEmpty) return;

                      widget.onSave(
                        mac: widget.macAddress,
                        name: name,
                        category: _selectedCategoryKey,
                        vendor: _vendorCtrl.text.trim().isNotEmpty
                            ? _vendorCtrl.text.trim()
                            : null,
                        notes: _notesCtrl.text.trim().isNotEmpty
                            ? _notesCtrl.text.trim()
                            : null,
                      );
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
