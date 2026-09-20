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

  /// 낮고 넓은 화면(폰 가로)용 압축 배치: 액션바 한 줄, 낮은 히어로 버튼 한 줄,
  /// 통계 한 줄 + 상태 줄 — 목록에 최소 3행이 남도록.
  final bool compact;

  /// 시트(폰 세로) 맨 아래 여백 — 시스템 제스처 바·노치의 `viewPadding.bottom`.
  final double bottomPadding;

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
    this.compact = false,
    this.bottomPadding = 0,
  });

  /// 폰 세로의 아래 시트인가 (스크롤 컨트롤러를 시트가 준다)
  bool get _isSheet => scrollController != null;

  @override
  Widget build(BuildContext context) {
    if (scrollController != null) {
      return _buildScrollablePanel(context);
    }
    if (compact) return _buildCompactPanel(context);
    return _buildFixedPanel(context);
  }

  // ──── 압축 배치 (폰 가로) ────

  Widget _buildCompactPanel(BuildContext context) {
    return Container(
      color: const Color(0xFF252525),
      child: Column(
        children: [
          _buildCompactActionBar(),
          Expanded(
            child: boxes.isEmpty
                ? SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: _buildEmptyState(showIcon: false),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: boxes.length,
                    itemBuilder: (_, i) => _boxTile(boxes[i]),
                  ),
          ),
          if (boxes.isNotEmpty && onAutoLayout != null) _compactHeroRow(),
          if (boxes.isNotEmpty) _compactStats(context),
        ],
      ),
    );
  }

  /// 한 줄 액션바 (넘치면 가로 스크롤). 자동 배치는 아래 히어로 줄에 있으므로 뺀다.
  Widget _buildCompactActionBar() {
    Widget small(IconData icon, String tooltip, VoidCallback? onTap) {
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          icon: Icon(icon,
              color: onTap == null ? const Color(0xFF555555) : Colors.grey,
              size: 20),
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFF333333),
            padding: const EdgeInsets.all(8),
            minimumSize: const Size(36, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4DA3FF),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onAddBox,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('박스 추가', style: TextStyle(fontSize: 13)),
            ),
            small(Icons.save, '배치 저장', onSave),
            small(Icons.folder_open, '불러오기', onLoad),
            if (onUndo != null || onRedo != null) ...[
              small(Icons.undo, '실행 취소', onUndo),
              small(Icons.redo, '다시 실행', onRedo),
            ],
            if (onScreenshot != null)
              small(Icons.photo_camera, '스크린샷', onScreenshot),
            if (onShareCard != null) small(Icons.share, '공유 카드', onShareCard),
          ],
        ),
      ),
    );
  }

  /// 낮은(36px) 히어로 버튼 한 줄: 들어갈까? · 자동 배치 · (순서 가이드)
  Widget _compactHeroRow() {
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            if (onQuickCheck != null) ...[
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6BD06B),
                  side: const BorderSide(color: Color(0xFF6BD06B), width: 1.5),
                  shape: shape,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: onQuickCheck,
                child: const Text('들어갈까?',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4DA3FF),
                  foregroundColor: Colors.white,
                  shape: shape,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: onAutoLayout,
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: const Text('자동 배치',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
            if (onStepView != null && _hasLoadOrders()) ...[
              const SizedBox(width: 6),
              IconButton(
                tooltip: '적재 순서 가이드',
                onPressed: onStepView,
                icon: const Icon(Icons.format_list_numbered,
                    color: Color(0xFF00E676), size: 20),
                style: IconButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF00E676)),
                  shape: shape,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(36, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 통계 한 줄 + 상태 줄
  /// "박스 18/32개" (못 실은 짐이 있을 때) 또는 "박스 16개"
  static String countText(LoadStats stats, int total) =>
      stats.parked.isEmpty ? '박스 $total개' : '박스 ${stats.inside.length}/$total개';

  Widget _compactStats(BuildContext context) {
    final stats = LoadStats.of(boxes, space);
    final volPct = stats.volumePercent.clamp(0, 100).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF444444))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${countText(stats, boxes.length)} · 부피 $volPct% · 남은 높이 ${stats.remainingHeightCm}cm',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 4),
          _statusRow(context, _placementWarnings(), _adviceMessages()),
        ],
      ),
    );
  }

  /// 배치 불가 사유 (천장·테일게이트·개구부·경계·겹침) — CollisionDetector 가 단일 진실
  List<String> _placementWarnings() {
    final detector = CollisionDetector(space);
    final warnings = <String>[];
    for (final b in boxes) {
      final name = b.label.isNotEmpty ? b.label : b.id;
      // 앱이 트렁크 밖에 세워 둔(못 실은) 짐은 "경계 밖" 충돌이 아니라 못 실은 짐이다
      if (LoadStats.isParked(b, space)) {
        warnings.add('$name: 안 들어감 (트렁크 밖에 둠)');
        continue;
      }
      final reasons = detector.describe(b, boxes);
      if (reasons.isEmpty) continue;
      warnings.add('$name: ${reasons.join(', ')}');
    }
    return warnings;
  }

  List<String> _adviceMessages() =>
      PackingAdvisor.advise(boxes, space).map((a) => a.message).toList();

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

  /// 폰 세로의 아래 시트. 위 → 아래: 손잡이 → 히어로 줄(들어갈까? · 자동 배치) →
  /// 도구 한 줄(박스 추가 · 순서 가이드 · 실행 취소 · 다시 실행 · ⋯) → 상태 두 줄 → 목록.
  /// 시트를 조금만 올려도 핵심 동작이 보이고, 도구는 한 줄이라 목록이 바로 나온다.
  /// 빈 상태: 안내 + CTA + "저장된 배치 불러오기" 만 (도구 줄 없음).
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
          if (boxes.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: _buildEmptyState(iconSize: 36, gap: 12),
            ),
            Center(
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onLoad,
                icon: const Icon(Icons.folder_open, size: 16, color: Colors.grey),
                label: const Text('저장된 배치 불러오기',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
              ),
            ),
          ] else ...[
            if (onAutoLayout != null) _heroAutoLayoutButton(),
            _buildSheetToolRow(),
            _compactStats(context),
            ...boxes.map((b) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _boxTile(b),
                )),
          ],
          // 빈 상태는 초기 시트 높이(220px + 아래 인셋) 안에 다 들어가야 한다 (숨은 스크롤 없음)
          SizedBox(height: (boxes.isEmpty ? 8 : 16) + bottomPadding),
        ],
      ),
    );
  }

  /// 시트의 도구 한 줄: 박스 추가 · 순서 가이드(순서가 있을 때) · 실행 취소 · 다시 실행 · ⋯(저장·불러오기·이미지)
  Widget _buildSheetToolRow() {
    Widget tool(IconData icon, String tooltip, VoidCallback? onTap,
        {Color color = Colors.grey}) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon,
            color: onTap == null ? const Color(0xFF777777) : color, size: 22),
        style: IconButton.styleFrom(
          backgroundColor:
              onTap == null ? const Color(0xFF2A2A2A) : const Color(0xFF333333),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4DA3FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: onAddBox,
                icon: const Icon(Icons.add, size: 20),
                label: const Text('박스 추가',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          if (onStepView != null && _hasLoadOrders()) ...[
            const SizedBox(width: 6),
            tool(Icons.format_list_numbered, '적재 순서 가이드', onStepView,
                color: const Color(0xFF00E676)),
          ],
          if (onUndo != null || onRedo != null) ...[
            const SizedBox(width: 6),
            tool(Icons.undo, '실행 취소', onUndo),
            const SizedBox(width: 6),
            tool(Icons.redo, '다시 실행', onRedo),
          ],
          const SizedBox(width: 6),
          PopupMenuButton<VoidCallback>(
            tooltip: '더 보기',
            color: const Color(0xFF333333),
            onSelected: (fn) => fn(),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF333333),
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
            ),
            icon: const Icon(Icons.more_horiz, color: Colors.grey, size: 22),
            itemBuilder: (_) => [
              _menuItem(Icons.save, '배치 저장', onSave),
              _menuItem(Icons.folder_open, '불러오기', onLoad),
              if (onScreenshot != null)
                _menuItem(Icons.photo_camera, '스크린샷', onScreenshot!),
              if (onShareCard != null)
                _menuItem(Icons.share, '공유 카드', onShareCard!),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<VoidCallback> _menuItem(
      IconData icon, String label, VoidCallback fn) {
    return PopupMenuItem<VoidCallback>(
      value: fn,
      child: Row(
        children: [
          Icon(icon, color: Colors.grey, size: 18),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
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

  Widget _buildEmptyState(
      {bool showIcon = true, double iconSize = 48, double gap = 16}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(Icons.inventory_2_outlined,
                color: Colors.grey[700], size: iconSize),
            SizedBox(height: gap),
          ],
          const Text(
            '캠핑 장비를 선택하고\n트렁크에 들어가는지 확인하세요',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.grey, fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.5),
          ),
          SizedBox(height: gap),
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
      // 압축 배치: 행 사이·안쪽 여백을 줄여 낮은 화면에서 한 행이라도 더 보이게
      margin: compact
          ? const EdgeInsets.symmetric(horizontal: 2, vertical: 2)
          : null,
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
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 12, vertical: compact ? 3 : 8),
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
                        if (LoadStats.isParked(box, space)) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: '트렁크에 넣을 자리가 없어 밖에 두었습니다',
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0x33FF6B6B),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('안 들어감',
                                  style: TextStyle(
                                      color: Color(0xFFFF6B6B), fontSize: 10)),
                            ),
                          ),
                        ] else if (isColliding) ...[
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
              // 회전 버튼 (폰 시트에서는 48px 탭 영역 — M3 기본 40px 는 손가락에 작다, 그 외는 조밀)
              IconButton(
                icon: const Icon(Icons.rotate_right,
                    color: Colors.white70, size: 20),
                tooltip: '90° 회전',
                onPressed: () => onRotate(box.id),
                visualDensity:
                    _isSheet ? VisualDensity.standard : VisualDensity.compact,
                constraints: _isSheet
                    ? const BoxConstraints.tightFor(width: 48, height: 48)
                    : null,
                padding: _isSheet ? EdgeInsets.zero : null,
              ),
              // 삭제 버튼
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Color(0xFFFF6B6B), size: 20),
                tooltip: '삭제',
                onPressed: () => onDelete(box.id),
                visualDensity:
                    _isSheet ? VisualDensity.standard : VisualDensity.compact,
                constraints: _isSheet
                    ? const BoxConstraints.tightFor(width: 48, height: 48)
                    : null,
                padding: _isSheet ? EdgeInsets.zero : null,
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

    final warnings = _placementWarnings();

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
          _statusRow(context, warnings, _adviceMessages()),
        ],
      ),
    );
  }

  Widget _statusRow(
      BuildContext context, List<String> warnings, List<String> advice) {
    if (warnings.isEmpty && advice.isNotEmpty) {
      final more = advice.length > 1 ? ' 외 ${advice.length - 1}건' : '';
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
    final more = warnings.length > 1 ? ' 외 ${warnings.length - 1}건' : '';
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
