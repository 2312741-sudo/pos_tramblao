import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/task_assignment_model.dart';
import '../../../models/member_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../attendance/providers/attendance_provider.dart';
import '../../store/providers/store_provider.dart';
import '../providers/task_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Màn hình Báo cáo công việc cho người nhận việc
/// Áp dụng cho cả Nhân viên, QL1, QL2 và Chủ cửa hàng.
class TaskReportScreen extends ConsumerStatefulWidget {
  final AssignedTask task;
  final String? workDate; // format: YYYY-MM-DD
  final TaskSubmission? initialSubmission;

  const TaskReportScreen({
    super.key,
    required this.task,
    this.workDate,
    this.initialSubmission,
  });

  @override
  ConsumerState<TaskReportScreen> createState() => _TaskReportScreenState();
}

class _TaskReportScreenState extends ConsumerState<TaskReportScreen> {
  late final TextEditingController _reportController;
  final List<String> _photoUrls = [];
  bool _isCompleted = false;
  DateTime? _completedAt;

  bool _isLoading = true;
  bool _isSavingDraft = false;
  bool _isSubmitting = false;
  bool _isUploadingPhoto = false;
  late final String _workDateStr;

  @override
  void initState() {
    super.initState();
    _reportController = TextEditingController();

    final vnNow = DateTime.now().toUtc().add(const Duration(hours: 7));
    final defaultDate =
        '${vnNow.year}-${vnNow.month.toString().padLeft(2, '0')}-${vnNow.day.toString().padLeft(2, '0')}';

    String resolvedDate = widget.workDate ?? defaultDate;
    if (widget.workDate == null) {
      final activeAtt = ref.read(todayAttendanceProvider).valueOrNull;
      if (activeAtt != null && activeAtt.checkOut == null && activeAtt.date.isNotEmpty) {
        resolvedDate = activeAtt.date;
      }
    }
    _workDateStr = resolvedDate;

    if (widget.initialSubmission != null) {
      _applySubmission(widget.initialSubmission!);
      _isLoading = false;
    } else {
      _loadExistingSubmission();
    }
  }

  void _applySubmission(TaskSubmission sub) {
    _reportController.text = sub.reportText;
    _photoUrls.clear();
    _photoUrls.addAll(sub.photoUrls);
    _isCompleted = sub.isCompleted;
    _completedAt = sub.completedAt;
  }

  Future<void> _loadExistingSubmission() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final repo = ref.read(taskRepositoryProvider);
      final sub = await repo.getUserSubmission(
        widget.task.storeId,
        widget.task.id,
        userId,
        _workDateStr,
      );
      if (sub != null && mounted) {
        _applySubmission(sub);
      }
    } catch (_) {
      // Bỏ qua lỗi mạng/tải ban đầu nếu có
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _reportController.dispose();
    super.dispose();
  }

  String _resolveUserName(String userId) {
    final members = ref.read(storeMembersProvider).valueOrNull ?? [];
    final currentMember =
        members.where((m) => m.userId == userId).firstOrNull;
    if (currentMember != null && currentMember.name.isNotEmpty) {
      return currentMember.name;
    }
    final userModel = ref.read(currentUserProvider).valueOrNull;
    if (userModel != null && userModel.name.isNotEmpty) {
      return userModel.name;
    }
    return 'Nhân viên';
  }

  /// Chụp ảnh trực tiếp từ camera tại thời điểm hoàn thành (đã khóa chọn từ thư viện)
  Future<void> _pickAndUploadPhoto([ImageSource source = ImageSource.camera]) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng đăng nhập lại để tải ảnh.')),
      );
      return;
    }

    try {
      final picker = ImagePicker();
      // Bắt buộc chụp trực tiếp từ camera, không cho phép chọn từ thư viện
      final pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      if (pickedFile == null || !mounted) return;

      setState(() => _isUploadingPhoto = true);

      final bytes = await pickedFile.readAsBytes();
      final ext = pickedFile.name.split('.').lastOrNull ?? 'jpg';

      final repo = ref.read(taskRepositoryProvider);
      final downloadUrl = await repo.uploadTaskPhoto(
        widget.task.storeId,
        widget.task.id,
        userId,
        _workDateStr,
        bytes,
        ext,
      );

      if (mounted) {
        setState(() {
          _photoUrls.add(downloadUrl);
          _isUploadingPhoto = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tải ảnh minh chứng thành công!'),
            backgroundColor: AppColors.success,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi tải ảnh: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _saveDraft() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    setState(() => _isSavingDraft = true);
    try {
      final userName = _resolveUserName(userId);
      final submission = TaskSubmission(
        id: '${userId}_$_workDateStr',
        taskId: widget.task.id,
        storeId: widget.task.storeId,
        userId: userId,
        userName: userName,
        workDate: _workDateStr,
        reportText: _reportController.text.trim(),
        photoUrls: _photoUrls,
        isCompleted: false,
        completedAt: null,
        lastSavedAt: DateTime.now(),
      );

      await ref.read(taskRepositoryProvider).saveSubmission(submission);

      ref.invalidate(todayUserTasksProvider);
      ref.invalidate(unfinishedUserTasksProvider);

      if (mounted) {
        setState(() {
          _isCompleted = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã lưu nháp tiến độ công việc thành công!'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi lưu nháp: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingDraft = false);
    }
  }

  Future<void> _submitComplete() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    // Kiểm tra ràng buộc ảnh minh chứng
    if (widget.task.requirePhoto && _photoUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Công việc này bắt buộc chụp ảnh minh chứng. Vui lòng chụp hoặc tải ảnh trước khi hoàn thành!',
          ),
          backgroundColor: AppColors.danger,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final userName = _resolveUserName(userId);
      final now = DateTime.now();
      final submission = TaskSubmission(
        id: '${userId}_$_workDateStr',
        taskId: widget.task.id,
        storeId: widget.task.storeId,
        userId: userId,
        userName: userName,
        workDate: _workDateStr,
        reportText: _reportController.text.trim(),
        photoUrls: _photoUrls,
        isCompleted: true,
        completedAt: now,
        lastSavedAt: now,
      );

      await ref.read(taskRepositoryProvider).saveSubmission(submission);

      ref.invalidate(todayUserTasksProvider);
      ref.invalidate(unfinishedUserTasksProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chúc mừng! Bạn đã hoàn thành báo cáo công việc.'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi nộp hoàn thành: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showImagePreview(String imageUrl) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: const Color(0xDD000000),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                  maxWidth: MediaQuery.of(context).size.width,
                ),
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorWidget: (_, __, ___) => const Center(
                      child: Icon(LucideIcons.imageOff,
                          color: Colors.white70, size: 48),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: GestureDetector(
                onTap: () => Navigator.pop(dialogCtx),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0x8A000000),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.x,
                      color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Báo Cáo Công Việc',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontFamily: 'BeVietnamPro',
            color: AppColors.neutral,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft,
              color: AppColors.neutral),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              // 1. Thẻ Thông tin Công việc
              _buildTaskInfoCard(),
              const SizedBox(height: 16),

              // 2. Thẻ Báo cáo Tiến độ/Kết quả
              _buildReportTextCard(),
              const SizedBox(height: 16),

              // 3. Thẻ Hình ảnh minh chứng
              _buildPhotosCard(),
              const SizedBox(height: 24),

              // 4. Các nút hành động
              _buildActionButtons(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    ),
  );
  }

  Widget _buildTaskInfoCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardOutline, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.task.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'BeVietnamPro',
                    color: AppColors.neutral,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildStatusBadge(),
            ],
          ),
          if (widget.task.description.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              widget.task.description,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                fontFamily: 'BeVietnamPro',
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 12),
          // Người giao & Ngày thực hiện
          Row(
            children: [
              const Icon(LucideIcons.user,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Người giao: ${widget.task.createdByName.isNotEmpty ? widget.task.createdByName : 'Quản lý'} (${widget.task.createdByRole.label})',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    fontFamily: 'BeVietnamPro',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(LucideIcons.calendar,
                  size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Flexible(child: Text(
                'Ngày thực hiện: $_workDateStr',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                  fontFamily: 'BeVietnamPro',
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )),
            ],
          ),
          if (_isCompleted && _completedAt != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(LucideIcons.circleCheck,
                    size: 15, color: AppColors.success),
                const SizedBox(width: 6),
                Flexible(child: Text(
                  'Hoàn thành lúc: ${DateFormat('HH:mm - dd/MM/yyyy').format(_completedAt!.toLocal())}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.success,
                    fontFamily: 'BeVietnamPro',
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )),
              ],
            ),
          ],
          const SizedBox(height: 10),
          // Yêu cầu ảnh badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: widget.task.requirePhoto
                  ? const Color(0xFFFFF3E0)
                  : AppColors.paperInk.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.task.requirePhoto
                    ? const Color(0xFFFFB74D)
                    : AppColors.border,
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.task.requirePhoto
                      ? LucideIcons.camera
                      : LucideIcons.images,
                  size: 14,
                  color: widget.task.requirePhoto
                      ? const Color(0xFFE65100)
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Flexible(child: Text(
                  widget.task.requirePhoto
                      ? 'Yêu cầu có ảnh minh chứng'
                      : 'Không bắt buộc ảnh',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'BeVietnamPro',
                    color: widget.task.requirePhoto
                        ? const Color(0xFFE65100)
                        : AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    if (_isCompleted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.circleCheck,
                color: AppColors.success, size: 14),
            SizedBox(width: 4),
            Text(
              'Đã xong',
              style: TextStyle(
                color: AppColors.success,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFamily: 'BeVietnamPro',
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.clipboardClock,
              color: AppColors.warning, size: 14),
          SizedBox(width: 4),
          Text(
            'Chưa xong',
            style: TextStyle(
              color: AppColors.warning,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFamily: 'BeVietnamPro',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportTextCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardOutline, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.notebookPen,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Nội dung báo cáo / Tiến độ',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'BeVietnamPro',
                    color: AppColors.neutral,
                  ),
                ),
              ),
              InkWell(
                onTap: () => FocusScope.of(context).unfocus(),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.paperInk.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border, width: 0.8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.keyboardOff,
                          size: 15, color: AppColors.textSecondary),
                      SizedBox(width: 4),
                      Text(
                        'Ẩn phím',
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'BeVietnamPro',
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reportController,
            minLines: 4,
            maxLines: 8,
            style: const TextStyle(
              fontSize: 14,
              fontFamily: 'BeVietnamPro',
              color: AppColors.neutral,
            ),
            decoration: InputDecoration(
              hintText:
                  'Mô tả tiến độ thực hiện, kết quả đạt được hoặc ghi chú phát sinh trong ca làm việc...',
              hintStyle: const TextStyle(
                fontSize: 13,
                color: AppColors.textDisabled,
                fontFamily: 'BeVietnamPro',
              ),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotosCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardOutline, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.camera,
                      color: AppColors.primary, size: 19),
                  const SizedBox(width: 8),
                  Text(
                    'Hình ảnh minh chứng (${_photoUrls.length})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'BeVietnamPro',
                      color: AppColors.neutral,
                    ),
                  ),
                ],
              ),
              if (widget.task.requirePhoto)
                const Text(
                  '* Bắt buộc',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.danger,
                    fontFamily: 'BeVietnamPro',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Nút Chụp ảnh trực tiếp từ Camera (Đã khóa chọn từ Thư viện)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isUploadingPhoto
                  ? null
                  : () => _pickAndUploadPhoto(ImageSource.camera),
              icon: const Icon(LucideIcons.camera, size: 20),
              label: const Text(
                'Chụp ảnh trực tiếp tại thời điểm hoàn thành',
                style: TextStyle(
                  fontFamily: 'BeVietnamPro',
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2),
              ),
            ),
            child: const Row(
              children: [
                Icon(
                  LucideIcons.lock,
                  size: 16,
                  color: AppColors.primary,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Đã khóa chọn từ thư viện. Bắt buộc chụp ảnh trực tiếp tại thời điểm hoàn thành để xác thực.',
                    style: TextStyle(
                      fontFamily: 'BeVietnamPro',
                      fontSize: 11.5,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_isUploadingPhoto) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(width: 12),
                  Flexible(child: Text(
                    'Đang tải ảnh lên hệ thống...',
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'BeVietnamPro',
                      color: AppColors.textSecondary,
                    ),
                  )),
                ],
              ),
            ),
          ],

          if (_photoUrls.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: List.generate(_photoUrls.length, (index) {
                final url = _photoUrls[index];
                return Stack(
                  children: [
                    GestureDetector(
                      onTap: () => _showImagePreview(url),
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                          color: Colors.black12,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            errorWidget: (_, __, ___) => const Center(
                              child: Icon(LucideIcons.imageOff,
                                  color: Colors.grey),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _photoUrls.removeAt(index);
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Color(0xB3000000),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            LucideIcons.x,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        // Nút Hoàn thành công việc
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_isSubmitting || _isSavingDraft || _isUploadingPhoto)
                ? null
                : _submitComplete,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(LucideIcons.circleCheck, size: 20),
            label: Text(
              _isSubmitting ? 'Đang lưu...' : 'Hoàn thành công việc',
              style: const TextStyle(
                fontFamily: 'BeVietnamPro',
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Nút Lưu nháp
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: (_isSubmitting || _isSavingDraft || _isUploadingPhoto)
                ? null
                : _saveDraft,
            icon: _isSavingDraft
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : const Icon(LucideIcons.bookmark, size: 18),
            label: Text(
              _isSavingDraft ? 'Đang lưu nháp...' : 'Lưu nháp tiến độ',
              style: const TextStyle(
                fontFamily: 'BeVietnamPro',
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary, width: 1.2),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
