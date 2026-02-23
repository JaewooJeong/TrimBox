import 'package:flutter/material.dart';

import '../models/trim_box.dart';

/// 박스 프리셋 카테고리
enum _PresetCategory { custom, carrier, camping, moving }

extension on _PresetCategory {
  String get label => switch (this) {
        _PresetCategory.custom => '직접 입력',
        _PresetCategory.carrier => '캐리어',
        _PresetCategory.camping => '캠핑',
        _PresetCategory.moving => '이사박스',
      };
}

/// 박스 프리셋 데이터
class _BoxPreset {
  final String label;
  final int w, d, h;
  final _PresetCategory category;
  const _BoxPreset(this.label, this.w, this.d, this.h, this.category);
}

const _presets = [
  // 직접 입력
  _BoxPreset('커스텀', 40, 30, 30, _PresetCategory.custom),
  // 캐리어
  _BoxPreset('기내용 캐리어 (20")', 36, 23, 55, _PresetCategory.carrier),
  _BoxPreset('중형 캐리어 (24")', 45, 28, 65, _PresetCategory.carrier),
  _BoxPreset('대형 캐리어 (28")', 48, 30, 75, _PresetCategory.carrier),
  // 캠핑
  _BoxPreset('소형 아이스박스 (25L)', 38, 25, 35, _PresetCategory.camping),
  _BoxPreset('중형 아이스박스 (50L)', 60, 40, 42, _PresetCategory.camping),
  _BoxPreset('대형 아이스박스 (70L)', 70, 45, 45, _PresetCategory.camping),
  _BoxPreset('접이식 테이블 (2인)', 60, 45, 5, _PresetCategory.camping),
  _BoxPreset('접이식 테이블 (4인)', 120, 60, 7, _PresetCategory.camping),
  // 이사박스
  _BoxPreset('소형 이사박스', 31, 26, 31, _PresetCategory.moving),
  _BoxPreset('중형 이사박스', 46, 41, 46, _PresetCategory.moving),
  _BoxPreset('대형 이사박스', 46, 46, 61, _PresetCategory.moving),
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

/// S7: 카테고리별 기본 색상 팔레트
const _categoryColors = {
  _PresetCategory.carrier: [
    Color(0xFF2C3E50), // 다크 네이비
    Color(0xFFC0392B), // 레드
    Color(0xFF1A1A2E), // 블랙
    Color(0xFF34495E), // 슬레이트
  ],
  _PresetCategory.moving: [
    Color(0xFFB8956A), // 골판지
    Color(0xFFD4A574), // 밝은 골판지
    Color(0xFFA0826D), // 어두운 골판지
  ],
  _PresetCategory.camping: [
    Color(0xFF556B2F), // 올리브
    Color(0xFF2F4F4F), // 다크 슬레이트
    Color(0xFFFF6B35), // 오렌지
    Color(0xFF1B4332), // 다크 그린
  ],
};

/// 박스 추가 다이얼로그 — 카테고리별 프리셋 + W, D, H (cm 단위) + 컬러 선택
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

  /// S7: 프리셋 카운터 (카테고리별 색상 순환용)
  final _categoryCounter = <_PresetCategory, int>{};

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
      // S7: 카테고리 색상 자동 선택 (자동 모드일 때)
      if (_selectedColorIndex == null && preset.category != _PresetCategory.custom) {
        // 카테고리별 색상 팔레트에서 순환 선택
        final colors = _categoryColors[preset.category];
        if (colors != null && colors.isNotEmpty) {
          final count = _categoryCounter[preset.category] ?? 0;
          _categoryCounter[preset.category] = count + 1;
          _autoCategoryColor = colors[count % colors.length];
        }
      } else {
        _autoCategoryColor = null;
      }
    });
  }

  /// S7: 자동 카테고리 색상 (null이면 기존 순서대로)
  Color? _autoCategoryColor;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF252525),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text('박스 추가', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 카테고리별 프리셋 드롭다운
            DropdownButtonFormField<int>(
              initialValue: _selectedPresetIndex,
              dropdownColor: const Color(0xFF333333),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              isExpanded: true,
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
              items: _buildPresetMenuItems(),
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
                ...List.generate(
                    _colorPalette.length, (i) => _colorChip(i, null)),
              ],
            ),
          ],
        ),
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

  /// 카테고리 구분 헤더가 포함된 프리셋 드롭다운 항목 생성
  List<DropdownMenuItem<int>> _buildPresetMenuItems() {
    final items = <DropdownMenuItem<int>>[];
    _PresetCategory? lastCategory;

    for (int i = 0; i < _presets.length; i++) {
      final p = _presets[i];

      // 카테고리 변경 시 구분선 + 헤더 표시
      if (p.category != lastCategory && p.category != _PresetCategory.custom) {
        items.add(DropdownMenuItem<int>(
          enabled: false,
          value: -1 - p.category.index, // 고유 비활성 값
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (lastCategory != null && lastCategory != _PresetCategory.custom)
                const Divider(color: Color(0xFF555555), height: 1),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 2),
                child: Text(
                  p.category.label,
                  style: const TextStyle(
                    color: Color(0xFF999999),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ));
      }
      lastCategory = p.category;

      items.add(DropdownMenuItem(
        value: i,
        child: Text(
          i == 0 ? p.label : '${p.label} (${p.w}×${p.d}×${p.h})',
          overflow: TextOverflow.ellipsis,
        ),
      ));
    }
    return items;
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

  /// _PresetCategory → BoxCategory 매핑
  static const _categoryMap = {
    _PresetCategory.custom: BoxCategory.custom,
    _PresetCategory.carrier: BoxCategory.carrier,
    _PresetCategory.camping: BoxCategory.camping,
    _PresetCategory.moving: BoxCategory.moving,
  };

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
    final presetCat = _presets[_selectedPresetIndex].category;
    final boxCat = _categoryMap[presetCat] ?? BoxCategory.custom;
    // S7: 색상 결정 — 수동 선택 > 카테고리 자동 > 순서대로
    int? colorValue;
    if (_selectedColorIndex != null) {
      colorValue = _colorPalette[_selectedColorIndex!].toARGB32();
    } else if (_autoCategoryColor != null) {
      colorValue = _autoCategoryColor!.toARGB32();
    }

    Navigator.pop(context, {
      'w': w / 100.0,
      'd': d / 100.0,
      'h': h / 100.0,
      'label': _labelCtrl.text.isEmpty ? null : _labelCtrl.text,
      if (colorValue != null) 'color': colorValue,
      'category': boxCat.index,
    });
  }
}
