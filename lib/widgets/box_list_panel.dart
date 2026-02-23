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
  final VoidCallback? onScreenshot;
  final ScrollController? scrollController;
  final bool showDragHandle;

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
    this.onScreenshot,
    this.scrollController,
    this.showDragHandle = false,
  });

  @override
  Widget build(BuildContext context) {
    if (scrollController != null) {
      return _buildScrollablePanel();
    }
    return _buildFixedPanel();
  }

  Widget _buildFixedPanel() {
    return Container(
      color: const Color(0xFF252525),
      child: Column(
        children: [
          _buildActionBar(),
          // 박스 리스트
          Expanded(
            child: boxes.isEmpty
                ? _buildEmptyState()
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

  Widget _buildScrollablePanel() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF252525),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: ListView(
        controller: scrollController,
        padding: EdgeInsets.zero,
        children: [
          if (showDragHandle) _buildDragHandle(),
          _buildActionBar(),
          if (boxes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: _buildEmptyState(),
            )
          else
            ...boxes.map((b) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _boxTile(b),
                )),
          if (boxes.isNotEmpty) _statsBar(),
        ],
      ),
    );
  }

  Widget _buildDragHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 4),
        width: 32,
        height: 4,
        decoration: BoxDecoration(
          color: const Color(0xFF666666),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    return Padding(
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
          if (onScreenshot != null) ...[
            const SizedBox(width: 8),
            _actionButton(Icons.photo_camera, '스크린샷', onScreenshot!),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined,
              color: Colors.grey[700], size: 48),
          const SizedBox(height: 12),
          const Text(
            '아직 박스가 없습니다',
            style: TextStyle(
                color: Colors.grey, fontSize: 14,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            '상단의 "박스 추가" 버튼으로\n시작하세요',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.grey[600], fontSize: 12),
          ),
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            box.label.isNotEmpty ? box.label : box.id,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isColliding) ...[
                          const SizedBox(width: 4),
                          const Tooltip(
                            message: '충돌 감지: 다른 박스 또는 경계와 겹침',
                            child: Icon(Icons.warning_amber_rounded,
                                color: Color(0xFFFF4D4D), size: 16),
                          ),
                        ],
                      ],
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
    // 면적 점유율
    final boxArea = boxes.fold<double>(
        0.0, (sum, b) => sum + b.effectiveW * b.effectiveD);
    final effectiveArea = space.w * space.d -
        (space.leftWheelhouse.w * space.leftWheelhouse.d) -
        (space.rightWheelhouse.w * space.rightWheelhouse.d);
    final areaRatio = effectiveArea > 0
        ? (boxArea / effectiveArea).clamp(0.0, 1.0)
        : 0.0;
    final areaPct = (areaRatio * 100).round();

    // 부피 점유율
    final totalBoxVol = boxes.fold<double>(
        0.0, (sum, b) => sum + b.effectiveW * b.effectiveD * b.h);
    final lhVol = space.leftWheelhouse.w *
        space.leftWheelhouse.d *
        space.leftWheelhouse.h;
    final rhVol = space.rightWheelhouse.w *
        space.rightWheelhouse.d *
        space.rightWheelhouse.h;
    final totalSpaceVol = space.w * space.d * space.h - lhVol - rhVol;
    final volRatio = totalSpaceVol > 0
        ? (totalBoxVol / totalSpaceVol).clamp(0.0, 1.0)
        : 0.0;
    final volPct = (volRatio * 100).round();
    final totalLiters = (totalBoxVol * 1000).round();

    // 최대 스택 높이 및 남은 높이
    double maxStackTop = 0;
    for (final b in boxes) {
      final top = b.y + b.h;
      if (top > maxStackTop) maxStackTop = top;
    }
    final remainH = ((space.h - maxStackTop) * 100).round();

    // 높이 초과 박스 찾기
    final overHeightBoxes = <String>[];
    for (final b in boxes) {
      final over = b.y + b.h - space.h;
      if (over > 0.001) {
        final name = b.label.isNotEmpty ? b.label : b.id;
        overHeightBoxes.add('$name (+${(over * 100).round()}cm)');
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF444444))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 박스 수 + 총 부피
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '박스: ${boxes.length}개',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              Text(
                '총 ${totalLiters}L · 남은 높이: ${remainH}cm',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 면적 점유율
          _progressRow('면적', areaPct, areaRatio),
          const SizedBox(height: 4),
          // 부피 점유율
          _progressRow('부피', volPct, volRatio),
          // 높이 초과 경고
          if (overHeightBoxes.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final msg in overHeightBoxes)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Color(0xFFFF4D4D), size: 14),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '$msg 높이 초과',
                        style: const TextStyle(
                          color: Color(0xFFFF6B6B),
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _progressRow(String label, int percent, double ratio) {
    return Row(
      children: [
        SizedBox(
          width: 62,
          child: Text(
            '$label: $percent%',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: LinearProgressIndicator(
            value: ratio,
            backgroundColor: const Color(0xFF444444),
            color: Color.lerp(
              const Color(0xFF6BD06B),
              const Color(0xFFFF4D4D),
              ratio,
            ),
            minHeight: 5,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ],
    );
  }
}
