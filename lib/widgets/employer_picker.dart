import 'dart:async';

import 'package:flutter/material.dart';

import '../services/employer_catalog_service.dart';
import '../theme/paycheck_theme.dart';

const commonEmployers = <String>[
  'Accenture',
  'Adani Enterprises',
  'Adobe',
  'Air India',
  'American Express',
  'Amazon',
  'Axis Bank',
  'Bajaj Finserv',
  'Bharti Airtel',
  'Capgemini',
  'Cognizant',
  'CRED',
  'Deloitte',
  'Dr. Reddy\'s Laboratories',
  'EY',
  'Flipkart',
  'Freshworks',
  'Google',
  'Groww',
  'HCLTech',
  'HDFC Bank',
  'Hindustan Unilever',
  'ICICI Bank',
  'Infosys',
  'ITC',
  'Jio Platforms',
  'KPMG',
  'Larsen & Toubro',
  'MakeMyTrip',
  'Meesho',
  'Microsoft',
  'Myntra',
  'Navi',
  'Nestle India',
  'PhonePe',
  'PwC',
  'Razorpay',
  'Reliance Industries',
  'Salesforce',
  'Samsung India',
  'Siemens India',
  'State Bank of India',
  'Swiggy',
  'Tata Consultancy Services',
  'Tata Motors',
  'Tata Steel',
  'Tech Mahindra',
  'Uber India',
  'Unacademy',
  'Vedanta',
  'Wipro',
  'Zomato',
  'Zoho',
];

Future<String?> showEmployerPicker(
  BuildContext context, {
  String currentValue = '',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _EmployerPickerSheet(currentValue: currentValue),
  );
}

class _EmployerPickerSheet extends StatefulWidget {
  const _EmployerPickerSheet({required this.currentValue});

  final String currentValue;

  @override
  State<_EmployerPickerSheet> createState() => _EmployerPickerSheetState();
}

class _EmployerPickerSheetState extends State<_EmployerPickerSheet> {
  final _search = TextEditingController();
  final _other = TextEditingController();
  String _query = '';
  bool _showOther = false;
  bool _loading = true;
  bool _savingOther = false;
  List<String> _catalog = commonEmployers;
  Timer? _debounce;
  final _service = EmployerCatalogService();

  @override
  void initState() {
    super.initState();
    _loadCatalog('');
  }

  @override
  void dispose() {
    _search.dispose();
    _other.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadCatalog(String query) async {
    try {
      final results = await _service.search(query);
      if (!mounted) return;
      setState(() {
        _catalog = results.isEmpty ? commonEmployers : results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _catalog = commonEmployers;
        _loading = false;
      });
    }
  }

  void _searchChanged(String value) {
    final query = value.trim();
    setState(() => _query = query);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) _loadCatalog(query);
    });
  }

  Future<void> _useOther() async {
    final value = _other.text.trim();
    if (value.length < 2) return;
    setState(() => _savingOther = true);
    try {
      final saved = await _service.submit(value);
      if (mounted) Navigator.pop(context, saved);
    } catch (_) {
      if (!mounted) return;
      Navigator.pop(context, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _catalog
        .where((name) => name.toLowerCase().contains(_query.toLowerCase()))
        .toList(growable: false);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Select your employer', style: PaycheckType.h2()),
              const SizedBox(height: 6),
              Text(
                'This is saved to your profile. It does not connect to the company.',
                style:
                    PaycheckType.caption(color: PaycheckColors.textSecondary),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search companies',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: _searchChanged,
              ),
              const SizedBox(height: 10),
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: ListView(
                  children: [
                    for (final employer in filtered)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.business_outlined),
                        title: Text(employer),
                        trailing: employer == widget.currentValue
                            ? const Icon(Icons.check_rounded,
                                color: PaycheckColors.teal)
                            : null,
                        onTap: () => Navigator.pop(context, employer),
                      ),
                    ListTile(
                      key: const Key('employer_other'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.add_business_outlined),
                      title: const Text('Other'),
                      subtitle: const Text('Type a company not listed here'),
                      onTap: () => setState(() => _showOther = true),
                    ),
                  ],
                ),
              ),
              if (_showOther) ...[
                const SizedBox(height: 10),
                TextField(
                  key: const Key('employer_other_input'),
                  controller: _other,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Company name',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _savingOther ? null : _useOther,
                  icon: _savingOther
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_business_outlined),
                  label: Text(
                    _savingOther ? 'Saving company' : 'Use this company',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
