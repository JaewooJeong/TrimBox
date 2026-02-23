import 'package:flutter/material.dart';

/// 키보드 단축키 도움말 다이얼로그
class KeyboardShortcutsDialog extends StatelessWidget {
  const KeyboardShortcutsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF252525),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  const Icon(Icons.keyboard, color: Colors.white70, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '키보드 단축키',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF444444), height: 1),
            // 내용
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _categoryHeader('카메라'),
                    _shortcutRow(['Q'], '좌회전 (반시계)'),
                    _shortcutRow(['E'], '우회전 (시계)'),
                    _shortcutRow(['Wheel'], '줌 인/아웃'),
                    _shortcutRow(['우클릭', '드래그'], '패닝'),
                    _shortcutRow(['0'], '줌/패닝 리셋'),
                    const SizedBox(height: 16),
                    _categoryHeader('박스'),
                    _shortcutRow(['←', '→', '↑', '↓'], '이동 (그리드 단위)'),
                    _shortcutRow(['R'], '90° 회전'),
                    _shortcutRow(['Delete'], '삭제'),
                    const SizedBox(height: 16),
                    _categoryHeader('편집'),
                    _shortcutRow(['Ctrl', 'Z'], '실행 취소'),
                    _shortcutRow(['Ctrl', 'Y'], '다시 실행'),
                    _shortcutRow(['Ctrl', 'Shift', 'Z'], '다시 실행'),
                    _shortcutRow(['?'], '이 도움말 열기'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF4DA3FF),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _shortcutRow(List<String> keys, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Wrap(
              spacing: 4,
              children: keys.map((k) => _keyChip(k)).toList(),
            ),
          ),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _keyChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF3A3A3A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF555555), width: 0.5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
