import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend/pharmacy.dart';
import '../backend/pharmacy_service.dart';
import '../backend/subscription_service.dart';
import '../backend/user_profile.dart';

class SubscriptionAdminScreen extends StatefulWidget {
  const SubscriptionAdminScreen({required this.profile, super.key});

  final UserProfile profile;

  @override
  State<SubscriptionAdminScreen> createState() => _SubscriptionAdminScreenState();
}

class _SubscriptionAdminScreenState extends State<SubscriptionAdminScreen> {
  final _service = SubscriptionService();
  final _pharmacies = PharmacyService();
  final _tokenEmailController = TextEditingController();
  final _noteController = TextEditingController();
  final _paymentRefController = TextEditingController();
  final _customDaysController = TextEditingController(text: '30');

  String _plan = 'monthly';
  int _durationDays = 30;
  DateTime _startsAt = DateTime.now();
  bool _creating = false;
  String? _lastToken;
  String? _selectedPharmacyId;

  @override
  void dispose() {
    _tokenEmailController.dispose();
    _noteController.dispose();
    _paymentRefController.dispose();
    _customDaysController.dispose();
    super.dispose();
  }

  int get _days => _plan == 'custom' ? (int.tryParse(_customDaysController.text.trim()) ?? 30) : _durationDays;

  Future<void> _generateToken() async {
    setState(() => _creating = true);
    try {
      final token = await _service.createActivationToken(
        plan: _plan == 'custom' ? 'custom' : _plan,
        durationDays: _days,
        startsAt: _startsAt,
        pharmacyId: _selectedPharmacyId,
        ownerEmail: _tokenEmailController.text.trim(),
        note: _noteController.text.trim(),
      );
      await Clipboard.setData(ClipboardData(text: token));
      setState(() => _lastToken = token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Token created and copied: $token')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create token: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _grantDirect() async {
    final pharmacyId = _selectedPharmacyId?.trim() ?? '';
    if (pharmacyId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a pharmacy first.')),
      );
      return;
    }
    final expiresAt = _startsAt.add(Duration(days: _days));
    try {
      await _service.grantLicense(
        pharmacyId: pharmacyId,
        plan: _plan == 'custom' ? 'custom' : _plan,
        startsAt: _startsAt,
        expiresAt: expiresAt,
        note: _noteController.text.trim(),
        paymentReference: _paymentRefController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pharmacy licensed until ${expiresAt.day}/${expiresAt.month}/${expiresAt.year}. Write access is restored.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Grant failed: $error')),
        );
      }
    }
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _startsAt = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Pharmacy licenses', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
        const SizedBox(height: 6),
        const Text(
          'License is for the whole pharmacy. When it expires, every staff member can still view records but cannot add sales, stock, or users until you grant a new token.',
          style: TextStyle(color: Color(0xff68807d), height: 1.45),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(width: 420, child: _buildIssuerCard()),
            SizedBox(width: 420, child: _buildGrantCard()),
          ],
        ),
        const SizedBox(height: 22),
        const Text('Activation tokens', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
        const SizedBox(height: 8),
        _buildCodesTable(),
        const SizedBox(height: 22),
        const Text('Pharmacies', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
        const SizedBox(height: 8),
        _buildPharmaciesTable(),
      ],
    );
  }

  Widget _pharmacySelector() {
    return StreamBuilder<List<PharmacyRecord>>(
      stream: _pharmacies.watchPharmacies(),
      builder: (context, snapshot) {
        final pharmacies = snapshot.data ?? const <PharmacyRecord>[];
        return DropdownButtonFormField<String>(
          initialValue: pharmacies.any((pharmacy) => pharmacy.id == _selectedPharmacyId) ? _selectedPharmacyId : null,
          decoration: const InputDecoration(labelText: 'Pharmacy'),
          items: [
            for (final pharmacy in pharmacies)
              DropdownMenuItem(value: pharmacy.id, child: Text(pharmacy.name)),
          ],
          onChanged: (value) => setState(() => _selectedPharmacyId = value),
        );
      },
    );
  }

  Widget _buildIssuerCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Generate token after payment', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),
            _pharmacySelector(),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _plan,
              decoration: const InputDecoration(labelText: 'Plan'),
              items: const [
                DropdownMenuItem(value: 'monthly', child: Text('Monthly · 30 days')),
                DropdownMenuItem(value: 'quarterly', child: Text('Quarterly · 90 days')),
                DropdownMenuItem(value: 'biannual', child: Text('6 months · 180 days')),
                DropdownMenuItem(value: 'yearly', child: Text('Yearly · 365 days')),
                DropdownMenuItem(value: 'custom', child: Text('Custom days')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _plan = value;
                  _durationDays = SubscriptionService.planDurations[value] ?? _durationDays;
                });
              },
            ),
            if (_plan == 'custom') ...[
              const SizedBox(height: 10),
              TextField(
                controller: _customDaysController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Duration (days)'),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _tokenEmailController,
              decoration: const InputDecoration(labelText: 'Customer email (note)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Payment note'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _pickStart,
              icon: const Icon(Icons.event_rounded),
              label: Text('Starts ${_startsAt.day}/${_startsAt.month}/${_startsAt.year}'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _creating ? null : _generateToken,
              icon: const Icon(Icons.vpn_key_rounded),
              label: Text(_creating ? 'Creating...' : 'Generate pharmacy token'),
            ),
            if (_lastToken != null) ...[
              const SizedBox(height: 12),
              SelectableText(_lastToken!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xff0f766e))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGrantCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Grant paid access', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Create shops under Pharmacies and logins. Here you only extend or unlock a shop after payment.', style: TextStyle(color: Color(0xff68807d), height: 1.4)),
            const SizedBox(height: 12),
            _pharmacySelector(),
            const SizedBox(height: 10),
            TextField(
              controller: _paymentRefController,
              decoration: const InputDecoration(labelText: 'Payment reference (M-Pesa / bank)'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _grantDirect,
              icon: const Icon(Icons.verified_rounded),
              label: const Text('Grant paid access to selected pharmacy'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodesTable() {
    return StreamBuilder<List<ActivationCodeRecord>>(
      stream: _service.watchCodes(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Text('Could not load tokens: ${snapshot.error}');
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final codes = snapshot.data!;
        if (codes.isEmpty) return const Text('No tokens yet.');
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Token')),
              DataColumn(label: Text('Plan')),
              DataColumn(label: Text('Days')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Pharmacy')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final code in codes.take(40))
                DataRow(
                  cells: [
                    DataCell(SelectableText(code.code, style: const TextStyle(fontWeight: FontWeight.w700))),
                    DataCell(Text(code.plan)),
                    DataCell(Text('${code.durationDays}')),
                    DataCell(Text(code.isUsed ? 'Used' : 'Unused')),
                    DataCell(Text(code.usedByPharmacyId ?? code.pharmacyId ?? '—')),
                    DataCell(
                      IconButton(
                        tooltip: 'Copy',
                        onPressed: () => Clipboard.setData(ClipboardData(text: code.code)),
                        icon: const Icon(Icons.copy_rounded, size: 18),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPharmaciesTable() {
    return StreamBuilder<List<PharmacyRecord>>(
      stream: _pharmacies.watchPharmacies(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Text('Could not load pharmacies: ${snapshot.error}');
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final pharmacies = snapshot.data!;
        if (pharmacies.isEmpty) return const Text('No pharmacies yet. Create one after a customer signs up.');
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Pharmacy')),
              DataColumn(label: Text('Plan')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Starts')),
              DataColumn(label: Text('Ends')),
              DataColumn(label: Text('Actions')),
            ],
            rows: [
              for (final pharmacy in pharmacies)
                DataRow(
                  cells: [
                    DataCell(Text(pharmacy.name)),
                    DataCell(Text(pharmacy.plan)),
                    DataCell(Text(pharmacy.isUnlocked ? pharmacy.status : 'locked')),
                    DataCell(Text(_fmt(pharmacy.startsAt))),
                    DataCell(Text(_fmt(pharmacy.expiresAt ?? pharmacy.trialEndsAt))),
                    DataCell(
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => _renamePharmacy(pharmacy),
                            child: const Text('Edit'),
                          ),
                          TextButton(
                            onPressed: () => _service.extendLicense(pharmacyId: pharmacy.id, extraDays: 30),
                            child: const Text('+30 days'),
                          ),
                          TextButton(
                            onPressed: () => _service.lockLicense(pharmacy.id),
                            child: const Text('Lock writes'),
                          ),
                          TextButton(
                            onPressed: () => _service.unlockLicense(pharmacy.id),
                            child: const Text('Unlock'),
                          ),
                          TextButton(
                            onPressed: () => _deletePharmacy(pharmacy),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _renamePharmacy(PharmacyRecord pharmacy) async {
    final controller = TextEditingController(text: pharmacy.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit pharmacy'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Pharmacy name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await _pharmacies.updatePharmacyProfile(pharmacyId: pharmacy.id, name: name, note: pharmacy.note);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pharmacy updated.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $error')));
      }
    }
  }

  Future<void> _deletePharmacy(PharmacyRecord pharmacy) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete pharmacy?'),
        content: Text('Remove ${pharmacy.name} from Firebase? Staff logins stay, but this shop record is deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _pharmacies.deletePharmacy(pharmacy.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pharmacy deleted.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $error')));
      }
    }
  }

  String _fmt(DateTime? value) {
    if (value == null) return '—';
    return '${value.day}/${value.month}/${value.year}';
  }
}
