import 'package:flutter/material.dart';

import '../models/trunk_space.dart';

/// 커스텀 트렁크 크기 입력 다이얼로그
class TrunkSizeDialog extends StatefulWidget {
  const TrunkSizeDialog({super.key});

  @override
  State<TrunkSizeDialog> createState() => _TrunkSizeDialogState();
}

class _TrunkSizeDialogState extends State<TrunkSizeDialog> {
  final _wCtrl = TextEditingController(text: '100');
  final _dCtrl = TextEditingController(text: '100');
  final _hCtrl = TextEditingController(text: '80');

  // 휠하우스
  final _lwwCtrl = TextEditingController(text: '0');
  final _lwdCtrl = TextEditingController(text: '0');
  final _lwhCtrl = TextEditingController(text: '0');
  final _rwwCtrl = TextEditingController(text: '0');
  final _rwdCtrl = TextEditingController(text: '0');
  final _rwhCtrl = TextEditingController(text: '0');

  String? _error;

  @override
  void dispose() {
    _wCtrl.dispose();
    _dCtrl.dispose();
    _hCtrl.dispose();
    _lwwCtrl.dispose();
    _lwdCtrl.dispose();
    _lwhCtrl.dispose();
    _rwwCtrl.dispose();
    _rwdCtrl.dispose();
    _rwhCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF252525),
      title:
          const Text('커스텀 트렁크', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: _buildField('가로(cm)', _wCtrl)),
                const SizedBox(width: 8),
                Expanded(child: _buildField('세로(cm)', _dCtrl)),
                const SizedBox(width: 8),
                Expanded(child: _buildField('높이(cm)', _hCtrl)),
              ],
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              title: const Text('휠하우스 (선택)',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
              collapsedIconColor: Colors.grey,
              iconColor: Colors.grey,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('왼쪽 휠하우스',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(child: _buildField('W(cm)', _lwwCtrl)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildField('D(cm)', _lwdCtrl)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildField('H(cm)', _lwhCtrl)),
                  ],
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('오른쪽 휠하우스',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(child: _buildField('W(cm)', _rwwCtrl)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildField('D(cm)', _rwdCtrl)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildField('H(cm)', _rwhCtrl)),
                  ],
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style:
                      const TextStyle(color: Color(0xFFFF4D4D), fontSize: 12)),
            ],
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
          child: const Text('확인'),
        ),
      ],
    );
  }

  Widget _buildField(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 12),
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
      setState(() => _error = '트렁크 가로/세로/높이는 양수를 입력하세요');
      return;
    }

    double parseCm(TextEditingController ctrl) {
      final v = double.tryParse(ctrl.text);
      return (v != null && v >= 0) ? v / 100.0 : 0;
    }

    final space = TrunkSpace.custom(
      w: w / 100.0,
      d: d / 100.0,
      h: h / 100.0,
      leftWheelhouse: Wheelhouse(
        w: parseCm(_lwwCtrl),
        d: parseCm(_lwdCtrl),
        h: parseCm(_lwhCtrl),
      ),
      rightWheelhouse: Wheelhouse(
        w: parseCm(_rwwCtrl),
        d: parseCm(_rwdCtrl),
        h: parseCm(_rwhCtrl),
      ),
    );

    Navigator.pop(context, space);
  }
}
