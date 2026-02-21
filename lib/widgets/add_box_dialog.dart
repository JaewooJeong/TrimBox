import 'package:flutter/material.dart';

/// 박스 프리셋 데이터
class _BoxPreset {
  final String label;
  final int w, d, h;
  const _BoxPreset(this.label, this.w, this.d, this.h);
}

const _presets = [
  _BoxPreset('커스텀', 40, 30, 30),
  _BoxPreset('소형 캐리어', 36, 25, 55),
  _BoxPreset('중형 캐리어', 45, 28, 65),
  _BoxPreset('캠핑 박스', 60, 40, 40),
  _BoxPreset('아이스박스', 50, 35, 35),
  _BoxPreset('택배 소형', 30, 25, 20),
  _BoxPreset('택배 중형', 48, 38, 34),
];

/// 컬러 팔레트 (박스 색상 선택용)
const _colorPalette = [
  Color(0xFFFFB3BA),
  Color(0xFFBAE1FF),
  Color(0xFFBAFFC9),
  Color(0xFFFFFFBA),
  Color(0xFFE3BAFF),
  Color(0xFFFFD4A3),
  Color(0xFFA3FFE0),
  Color(0xFFFFA3D4),
];

/// 박스 추가 다이얼로그 — 프리셋 + W, D, H (cm 단위) + 컬러 선택
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
  int _selectedPresetIndex = 0;
  int? _selectedColorIndex; // null = 자동 (순서대로)

  @override
  void dispose() {
    _wCtrl.dispose();
    _dCtrl.dispose();
    _hCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  void _onPresetChanged(int? index) {
    if (index == null) return;
    setState(() {
      _selectedPresetIndex = index;
      final preset = _presets[index];
      _wCtrl.text = preset.w.toString();
      _dCtrl.text = preset.d.toString();
      _hCtrl.text = preset.h.toString();
      if (index > 0) {
        _labelCtrl.text = preset.label;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF252525),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text('박스 추가', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 프리셋 드롭다운
          DropdownButtonFormField<int>(
            initialValue: _selectedPresetIndex,
            dropdownColor: const Color(0xFF333333),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: const InputDecoration(
              labelText: '프리셋',
              labelStyle: TextStyle(color: Colors.grey),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF555555)),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF4DA3FF), width: 2),
              ),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            items: List.generate(_presets.length, (i) {
              final p = _presets[i];
              return DropdownMenuItem(
                value: i,
                child: Text(
                  i == 0 ? p.label : '${p.label} (${p.w}×${p.d}×${p.h})',
                ),
              );
            }),
            onChanged: _onPresetChanged,
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          // 컬러 선택기
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '색상',
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // "자동" 옵션
              _colorChip(null, '자동'),
              ...List.generate(_colorPalette.length, (i) => _colorChip(i, null)),
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

  Widget _colorChip(int? colorIndex, String? label) {
    final isSelected = _selectedColorIndex == colorIndex;
    final color = colorIndex != null ? _colorPalette[colorIndex] : null;

    return GestureDetector(
      onTap: () => setState(() => _selectedColorIndex = colorIndex),
      child: Container(
        width: label != null ? null : 28,
        height: 28,
        padding: label != null
            ? const EdgeInsets.symmetric(horizontal: 8)
            : null,
        decoration: BoxDecoration(
          color: color ?? const Color(0xFF444444),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
        child: label != null
            ? Center(
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              )
            : null,
      ),
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
      'w': w / 100.0,
      'd': d / 100.0,
      'h': h / 100.0,
      'label': _labelCtrl.text.isEmpty ? null : _labelCtrl.text,
      if (_selectedColorIndex != null)
        'color': _colorPalette[_selectedColorIndex!].toARGB32(),
    });
  }
}
