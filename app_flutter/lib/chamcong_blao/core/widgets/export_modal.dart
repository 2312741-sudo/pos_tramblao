import 'package:flutter/material.dart';
import '../../models/member_model.dart';
import '../constants/app_colors.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ExportModal extends StatefulWidget {
  final List<MemberModel> members;
  final Function({
    String? memberId,
    required bool isMonth,
    DateTime? monthDate,
    DateTime? startDate,
    DateTime? endDate,
  }) onExport;
  final String title;

  const ExportModal({
    super.key,
    required this.members,
    required this.onExport,
    required this.title,
  });

  @override
  State<ExportModal> createState() => _ExportModalState();
}

class _ExportModalState extends State<ExportModal> {
  String _selectedMemberId = 'all';
  bool _isMonth = true;
  DateTime _monthDate = DateTime.now();
  DateTime? _startDate;
  DateTime? _endDate;

  Future<void> _selectMonth(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _monthDate,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) {
      setState(() => _monthDate = picked);
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'BeVietnamPro')),
          const SizedBox(height: 24),
          
          const Text('Nhân viên', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'BeVietnamPro')),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _selectedMemberId,
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('Tất cả nhân viên', style: TextStyle(fontFamily: 'BeVietnamPro'))),
                  ...widget.members.map((m) => DropdownMenuItem(value: m.userId, child: Text(m.name, style: const TextStyle(fontFamily: 'BeVietnamPro')))),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _selectedMemberId = val);
                },
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          const Text('Thời gian', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'BeVietnamPro')),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: RadioListTile<bool>(
                  title: const Text('Theo tháng', style: TextStyle(fontSize: 14, fontFamily: 'BeVietnamPro')),
                  value: true,
                  groupValue: _isMonth,
                  onChanged: (val) => setState(() => _isMonth = val!),
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppColors.primary,
                ),
              ),
              Expanded(
                child: RadioListTile<bool>(
                  title: const Text('Khoảng ngày', style: TextStyle(fontSize: 14, fontFamily: 'BeVietnamPro')),
                  value: false,
                  groupValue: _isMonth,
                  onChanged: (val) => setState(() => _isMonth = val!),
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppColors.primary,
                ),
              ),
            ],
          ),
          
          if (_isMonth)
            InkWell(
              onTap: () => _selectMonth(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Tháng ${_monthDate.month}/${_monthDate.year}', style: const TextStyle(fontFamily: 'BeVietnamPro')),
                    const Icon(LucideIcons.calendarDays, color: AppColors.textSecondary, size: 20),
                  ],
                ),
              ),
            )
          else
            InkWell(
              onTap: () => _selectDateRange(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_startDate != null && _endDate != null
                        ? '${_startDate!.day}/${_startDate!.month}/${_startDate!.year} - ${_endDate!.day}/${_endDate!.month}/${_endDate!.year}'
                        : 'Chọn khoảng ngày', style: const TextStyle(fontFamily: 'BeVietnamPro')),
                    const Icon(LucideIcons.calendarRange, color: AppColors.textSecondary, size: 20),
                  ],
                ),
              ),
            ),
            
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: (!_isMonth && (_startDate == null || _endDate == null)) ? null : () {
                Navigator.pop(context);
                widget.onExport(
                  memberId: _selectedMemberId == 'all' ? null : _selectedMemberId,
                  isMonth: _isMonth,
                  monthDate: _monthDate,
                  startDate: _startDate,
                  endDate: _endDate,
                );
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Xuất Excel', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'BeVietnamPro')),
            ),
          ),
        ],
      ),
    );
  }
}
