import 'package:flutter/material.dart';

/// 박스 추가 다이얼로그 — W, D, H (cm 단위) 입력
class AddBoxDialog extends StatefulWidget {
  const AddBoxDialog({super.key});

  @override
  State<AddBoxDialog> createState() => _AddBoxDialogState();
}

class _AddBoxDialogState extends State<AddBoxDialog> {
  final _wCtrl = TextEditingController(text: '40');
  final _dCtrl = TextEditingController(text: '30');
  final _hCtrl = TextEditingController(text: '30');
  final _labelCtrl = TextEditingController();

  @override
  void dispose() {
    _wCtrl.dispose();
    _dCtrl.dispose();
    _hCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF252525),
      title: const Text('박스 추가', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildField('라벨', _labelCtrl, '예: 캠핑 박스'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildField('가로(cm)', _wCtrl, '40')),
              const SizedBox(width: 8),
              Expanded(child: _buildField('세로(cm)', _dCtrl, '30')),
              const SizedBox(width: 8),
              Expanded(child: _buildField('높이(cm)', _hCtrl, '30')),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4DA3FF),
          ),
          onPressed: _onConfirm,
          child: const Text('추가'),
        ),
      ],
    );
  }

  Widget _buildField(
      String label, TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF666666)),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF4DA3FF)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF4DA3FF), width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
  }

  void _onConfirm() {
    final w = double.tryParse(_wCtrl.text);
    final d = double.tryParse(_dCtrl.text);
    final h = double.tryParse(_hCtrl.text);
    if (w == null || d == null || h == null || w <= 0 || d <= 0 || h <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('유효한 크기를 입력하세요')),
      );
      return;
    }
    Navigator.pop(context, {
      'w': w / 100.0, // cm → m
      'd': d / 100.0,
      'h': h / 100.0,
      'label': _labelCtrl.text.isEmpty ? null : _labelCtrl.text,
    });
  }
}
