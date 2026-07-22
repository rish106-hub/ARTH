import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const commonEmployers = <String>[
  'Accenture',
  'Amazon',
  'Axis Bank',
  'CRED',
  'Deloitte',
  'EY',
  'Flipkart',
  'Google',
  'Groww',
  'HCLTech',
  'HDFC Bank',
  'ICICI Bank',
  'Infosys',
  'KPMG',
  'Microsoft',
  'PwC',
  'Razorpay',
  'Reliance Industries',
  'State Bank of India',
  'Swiggy',
  'Tata Consultancy Services',
  'Tech Mahindra',
  'Wipro',
  'Zomato',
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

  @override
  void dispose() {
    _search.dispose();
    _other.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = commonEmployers
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
              Text('Select your employer', style: AppTextStyles.h2()),
              const SizedBox(height: 6),
              Text(
                'This is saved to your profile. It does not connect to the company.',
                style: AppTextStyles.caption(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search companies',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
              const SizedBox(height: 10),
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
                                color: AppColors.teal)
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
                FilledButton(
                  onPressed: () {
                    final value = _other.text.trim();
                    if (value.isNotEmpty) Navigator.pop(context, value);
                  },
                  child: const Text('Use this company'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
