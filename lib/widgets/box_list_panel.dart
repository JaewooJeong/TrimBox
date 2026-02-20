import 'package:flutter/material.dart';

import '../models/trim_box.dart';
import '../models/trunk_space.dart';

/// 박스 리스트 패널 — 각 박스 정보 + 회전/삭제 버튼
class BoxListPanel extends StatelessWidget {
  final List<TrimBox> boxes;
  final TrunkSpace space;
  final String? selectedBoxId;
  final Set<String> collidingBoxIds;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onRotate;
  final ValueChanged<String> onDelete;
  final VoidCallback onAddBox;
  final VoidCallback onSave;
  final VoidCallback onLoad;

  const BoxListPanel({
    super.key,
    required this.boxes,
    required this.space,
    this.selectedBoxId,
    this.collidingBoxIds = const {},
    required this.onSelect,
    required this.onRotate,
    required this.onDelete,
    required this.onAddBox,
    required this.onSave,
    required this.onLoad,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF252525),
      child: Column(
        children: [
          // 상단 액션 버튼들
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4DA3FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: onAddBox,
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('박스 추가'),
                  ),
                ),
                const SizedBox(width: 8),
                _actionButton(Icons.save, '저장', onSave),
                const SizedBox(width: 8),
                _actionButton(Icons.folder_open, '불러오기', onLoad),
              ],
            ),
          ),

          // 박스 리스트
          Expanded(
            child: boxes.isEmpty
                ? const Center(
                    child: Text(
                      '박스를 추가하세요',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: boxes.length,
                    itemBuilder: (_, i) => _boxTile(boxes[i]),
                  ),
          ),

          // 하단 통계
          if (boxes.isNotEmpty) _statsBar(),
        ],
      ),
    );
  }

  Widget _actionButton(IconData icon, String tooltip, VoidCallback onTap) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, color: Colors.grey, size: 22),
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xFF333333),
        padding: const EdgeInsets.all(10),
      ),
    );
  }

  Widget _boxTile(TrimBox box) {
    final isSelected = box.id == selectedBoxId;
    final isColliding = collidingBoxIds.contains(box.id);
    final wCm = (box.w * 100).round();
    final dCm = (box.d * 100).round();
    final hCm = (box.h * 100).round();

    return Card(
      color: isSelected ? const Color(0xFF333344) : const Color(0xFF2E2E2E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isColliding
              ? const Color(0xFFFF4D4D)
              : isSelected
                  ? const Color(0xFF4DA3FF)
                  : Colors.transparent,
          width: isColliding || isSelected ? 1.5 : 0,
        ),
      ),
      child: InkWell(
        onTap: () => onSelect(box.id),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // 색상 인디케이터
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: box.color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              // 정보
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      box.label.isNotEmpty ? box.label : box.id,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '$wCm × $dCm × ${hCm}cm  R:${box.rotY}°',
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
              // 회전 버튼
              IconButton(
                icon: const Icon(Icons.rotate_right,
                    color: Colors.white70, size: 20),
                tooltip: '90° 회전',
                onPressed: () => onRotate(box.id),
                visualDensity: VisualDensity.compact,
              ),
              // 삭제 버튼
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Color(0xFFFF6B6B), size: 20),
                tooltip: '삭제',
                onPressed: () => onDelete(box.id),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statsBar() {
    final totalVolume = boxes.fold<double>(
        0.0, (sum, b) => sum + b.effectiveW * b.effectiveD * b.h);
    final boxArea = boxes.fold<double>(
        0.0, (sum, b) => sum + b.effectiveW * b.effectiveD);
    final effectiveArea = space.w * space.d -
        (space.leftWheelhouse.w * space.leftWheelhouse.d) -
        (space.rightWheelhouse.w * space.rightWheelhouse.d);
    final ratio = effectiveArea > 0
        ? (boxArea / effectiveArea).clamp(0.0, 1.0)
        : 0.0;
    final percent = (ratio * 100).round();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF444444))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '박스: ${boxes.length}개',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              Text(
                '총 부피: ${(totalVolume * 1e6).round()}cm³',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '점유율: $percent%',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LinearProgressIndicator(
                  value: ratio,
                  backgroundColor: const Color(0xFF444444),
                  color: Color.lerp(
                    const Color(0xFFFF4D4D),
                    const Color(0xFF6BD06B),
                    ratio,
                  ),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
