import 'package:flutter/material.dart';

import '../models/trim_box.dart';
import '../models/trunk_space.dart';
import '../models/packing_advisor.dart';
import '../utils/collision.dart';
import '../utils/load_stats.dart';

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
  final VoidCallback? onAutoLayout;
  final VoidCallback? onQuickCheck;
  final VoidCallback? onStepView;
  final VoidCallback? onShareCard;

  /// 실행 취소 / 다시 실행. 둘 다 null 이면 버튼을 숨기고, 하나만 null 이면 그쪽만 비활성.
  /// (터치 기기에는 Ctrl+Z 가 없으므로 버튼이 유일한 되돌리기 수단이다.)
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
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
    this.onAutoLayout,
    this.onQuickCheck,
    this.onStepView,
    this.onShareCard,
    this.onUndo,
    this.onRedo,
    this.scrollController,
    this.showDragHandle = false,
  });

  @override
  Widget build(BuildContext context) {
    if (scrollController != null) {
      return _buildScrollablePanel(context);
    }
    return _buildFixedPanel(context);
  }

  Widget _buildFixedPanel(BuildContext context) {
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
          // 히어로 자동 배치 버튼
          if (boxes.isNotEmpty && onAutoLayout != null) _heroAutoLayoutButton(),
          // 적재 순서 가이드 버튼
          if (boxes.isNotEmpty && onStepView != null && _hasLoadOrders()) _stepViewButton(),
          // 하단 통계
          if (boxes.isNotEmpty) _statsBar(context),
        ],
      ),
    );
  }

  Widget _buildScrollablePanel(BuildContext context) {
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
          // 모바일: 시트를 조금만 올려도 핵심 동작이 보이도록 위쪽에 배치
          if (boxes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _buildEmptyState(),
            )
          else ...[
            if (onAutoLayout != null) _heroAutoLayoutButton(),
            if (onStepView != null && _hasLoadOrders()) _stepViewButton(),
            _statsBar(context),
          ],
          _buildActionBar(),
          ...boxes.map((b) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _boxTile(b),
              )),
          const SizedBox(height: 24),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.start,
        children: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4DA3FF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onAddBox,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('박스 추가', style: TextStyle(fontSize: 13)),
          ),
          _actionButton(Icons.save, '배치 저장', onSave),
          _actionButton(Icons.folder_open, '불러오기', onLoad),
          if (onScreenshot != null)
            _actionButton(Icons.photo_camera, '스크린샷', onScreenshot!),
          if (onAutoLayout != null)
            _actionButton(Icons.auto_fix_high, '자동 배치', onAutoLayout!),
          if (onShareCard != null)
            _actionButton(Icons.share, '공유 카드', onShareCard!),
          // 맨 끝에 붙인다: 기존 버튼 위치가 바뀌지 않는다
          if (onUndo != null || onRedo != null) ...[
            _actionButton(Icons.undo, '실행 취소', onUndo),
            _actionButton(Icons.redo, '다시 실행', onRedo),
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
          const SizedBox(height: 16),
          const Text(
            '캠핑 장비를 선택하고\n트렁크에 들어가는지 확인하세요',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.grey, fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.5),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4DA3FF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: onAddBox,
            icon: const Icon(Icons.backpack, size: 20),
            label: const Text('캠핑 장비 선택하기', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _heroAutoLayoutButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Quick check button
          if (onQuickCheck != null)
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6BD06B),
                  side: const BorderSide(color: Color(0xFF6BD06B), width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: onQuickCheck,
                icon: const Icon(Icons.check_circle_outline, size: 20),
                label: const Text(
                  '들어갈까?',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          if (onQuickCheck != null) const SizedBox(width: 8),
          // Auto layout button
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4DA3FF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 2,
                ),
                onPressed: onAutoLayout,
                icon: const Icon(Icons.auto_fix_high, size: 22),
                label: const Text(
                  '자동 배치',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _hasLoadOrders() {
    return boxes.any((b) => b.loadOrder != null);
  }

  Widget _stepViewButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: SizedBox(
        width: double.infinity,
        height: 36,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF00E676),
            side: const BorderSide(color: Color(0xFF00E676), width: 1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: onStepView,
          icon: const Icon(Icons.format_list_numbered, size: 18),
          label: const Text(
            '적재 순서 가이드',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }

  Widget _actionButton(IconData icon, String tooltip, VoidCallback? onTap) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon,
          color: onTap == null ? const Color(0xFF555555) : Colors.grey,
          size: 22),
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
              // Load order badge or color indicator
              if (box.loadOrder != null)
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: box.color.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: box.color, width: 1),
                  ),
                  child: Text(
                    '${box.loadOrder}',
                    style: TextStyle(
                      color: box.color,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
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
                      '$wCm × $dCm × ${hCm}cm  R:${box.rotY}°${_badges(box)}',
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
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

  /// 무게·연질·세움·접근성 배지 (있는 것만)
  static String _badges(TrimBox box) {
    final parts = <String>[];
    if (box.weightKg > 0) {
      parts.add(box.weightKg == box.weightKg.roundToDouble()
          ? '${box.weightKg.round()}kg'
          : '${box.weightKg.toStringAsFixed(1)}kg');
    }
    if (box.isSquashed) {
      parts.add('눌림 ${(box.squashAmount * 100).round()}%');
    } else if (box.soft) {
      parts.add('연질');
    }
    if (box.keepUpright) parts.add('세움');
    if (box.accessPriority) parts.add('자주 꺼냄');
    return parts.isEmpty ? '' : ' · ${parts.join(' · ')}';
  }

  Widget _statsBar(BuildContext context) {
    // 트렁크 밖에 세워 둔(못 넣은) 짐은 통계에서 뺀다 — 오버레이·판정과 같은 기준
    final stats = LoadStats.of(boxes, space);
    final areaRatio = stats.areaRatio;
    final areaPct = (areaRatio * 100).round();
    final volRatio = (stats.volumePercent / 100).clamp(0.0, 1.0);
    final volPct = (volRatio * 100).round();
    final totalLiters = stats.usedLiters;
    final remainH = stats.remainingHeightCm;

    // 배치 불가 사유 (천장·테일게이트·개구부·경계·겹침) — CollisionDetector 가 단일 진실
    final detector = CollisionDetector(space);
    final warnings = <String>[];
    for (final b in boxes) {
      final reasons = detector.describe(b, boxes);
      if (reasons.isEmpty) continue;
      final name = b.label.isNotEmpty ? b.label : b.id;
      warnings.add('$name: ${reasons.join(', ')}');
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
          const SizedBox(height: 6),
          // 배치 상태 — 항상 한 줄 (레이아웃이 흔들리지 않게). 탭하면 전체 사유.
          _statusRow(context, warnings,
              PackingAdvisor.advise(boxes, space).map((a) => a.message).toList()),
        ],
      ),
    );
  }

  Widget _statusRow(
      BuildContext context, List<String> warnings, List<String> advice) {
    if (warnings.isEmpty && advice.isNotEmpty) {
      final more = advice.length > 1 ? ' (+${advice.length - 1})' : '';
      return InkWell(
        onTap: () => _showWarningsDialog(context, advice,
            title: '적재 조언', isAdvice: true),
        child: Row(
          children: [
            const Icon(Icons.lightbulb_outline,
                color: Color(0xFFFFC46B), size: 14),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '${advice.first}$more',
                style: const TextStyle(color: Color(0xFFFFC46B), fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFFFC46B), size: 14),
          ],
        ),
      );
    }
    if (warnings.isEmpty) {
      return const Row(
        children: [
          Icon(Icons.check_circle_outline, color: Color(0xFF6BD06B), size: 14),
          SizedBox(width: 4),
          Expanded(
            child: Text(
              '배치 문제 없음 · 테일게이트 닫힘',
              style: TextStyle(color: Color(0xFF6BD06B), fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    final more = warnings.length > 1 ? ' (+${warnings.length - 1})' : '';
    return InkWell(
      onTap: () => _showWarningsDialog(context, warnings),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFFF4D4D), size: 14),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '${warnings.first}$more',
              style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.chevron_right, color: Color(0xFFFF6B6B), size: 14),
        ],
      ),
    );
  }

  void _showWarningsDialog(BuildContext context, List<String> warnings,
      {String title = '배치 문제', bool isAdvice = false}) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: Text('$title ${warnings.length}개',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: SizedBox(
          width: 360,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final w in warnings)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                          isAdvice
                              ? Icons.lightbulb_outline
                              : Icons.warning_amber_rounded,
                          color: isAdvice
                              ? const Color(0xFFFFC46B)
                              : const Color(0xFFFF4D4D),
                          size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(w,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인'),
          ),
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
