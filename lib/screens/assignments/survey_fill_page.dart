// lib/screens/assignments/survey_fill_page.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:wechat_camera_picker/wechat_camera_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/api_models.dart';
import '../../repositories/questionnaire_repository.dart';
import '../../repositories/submission_repository.dart';
import '../../utils/error_message.dart';
import '../../utils/snackbar.dart';
import '../../utils/status_format.dart';
import 'submission_comments_page.dart';
import '../../widgets/app_button_styles.dart';

class _ChinesePickerTextDelegate extends AssetPickerTextDelegate {
  const _ChinesePickerTextDelegate();

  @override
  String get languageCode => 'zh';

  @override
  String get confirm => '确认';
  @override
  String get cancel => '取消';
  @override
  String get preview => '预览';
  @override
  String get select => '选择';
  @override
  String get emptyList => '暂无内容';
  @override
  String get original => '原图';
  @override
  String get unableToAccessAll => '无法访问所有照片';
  @override
  String get viewingLimitedAssetsTip => '应用当前只能访问部分照片，如需完整访问，请前往系统设置修改权限。';
  @override
  String get changeAccessibleLimitedAssets => '管理可访问的照片';
  @override
  String get accessAllTip => '允许访问“所有照片”以完整选择图片和视频。';
  @override
  String get goToSystemSettings => '前往系统设置';
  @override
  String get accessLimitedAssets => '保持有限访问';
  @override
  String get accessiblePathName => '可访问的资源';
  @override
  String get sTypeImageLabel => '图片';
  @override
  String get sTypeVideoLabel => '视频';
  @override
  String get sTypeAudioLabel => '音频';
  @override
  String get sTypeOtherLabel => '其他';
  @override
  String get loadFailed => '加载失败';
  @override
  String get edit => '编辑';
  @override
  String get gifIndicator => 'GIF';
}

class _DerivedQuestionState {
  final bool visible;
  final bool required;

  _DerivedQuestionState({
    required this.visible,
    required this.required,
  });
}

class _PendingUpload {
  final String path;
  final String mediaType;
  double progress;

  _PendingUpload({
    required this.path,
    required this.mediaType,
    this.progress = 0.0,
  });
}

class SurveyFillPage extends StatefulWidget {
  const SurveyFillPage({super.key});

  @override
  State<SurveyFillPage> createState() => _SurveyFillPageState();
}

class _SurveyFillPageState extends State<SurveyFillPage> {
  late final Assignment _assignment;
  final _qRepo = QuestionnaireRepository();
  final _subRepo = SubmissionRepository();

  QuestionnaireDto? _questionnaire;
  bool _loading = true;
  String? _error;

  final Map<int, AnswerDraft> _answers = {};
  final Map<int, MediaFileDto> _mediaCache = {};
  final Set<int> _loadingMediaIds = {};
  final Map<int, List<_PendingUpload>> _pendingUploads = {};
  final Map<int, Uint8List> _videoThumbCache = {};

  final Map<int, TextEditingController> _textControllers = {};
  final Map<int, TextEditingController> _numberControllers = {};

  bool _inited = false;

  int? _submissionId;
  String? _submissionStatus;

  bool _savingDraft = false;
  bool _submitting = false;

  bool _shouldRefreshOnPop = false;

  DateTime? _extractPlannedVisitDate() {
    final q = _questionnaire;
    if (q == null) return null;
    for (final qu in q.questions) {
      if (qu.type != 'visit_date') continue;
      final draft = _answers[qu.id];
      final raw = draft?.dateValue?.trim();
      if (raw == null || raw.isEmpty) continue;
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }
    return null;
  }

  bool _sameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<bool> _syncPlannedVisitDate() async {
    final planned = _extractPlannedVisitDate();
    if (planned == null) return true;
    final current = _assignment.plannedVisitDate;
    if (current != null && _sameDate(current, planned)) return true;
    try {
      await _subRepo.updatePlannedVisitDate(
        assignmentId: _assignment.id,
        plannedVisitDate: planned,
      );
      _shouldRefreshOnPop = true;
      return true;
    } catch (e) {
      if (!mounted) return false;
      showErrorSnackBar(context, e, fallback: '计划走访日期同步失败');
      return false;
    }
  }

  bool get _isReadOnly =>
      _submissionStatus == 'submitted' ||
      _submissionStatus == 'resubmitted' ||
      _submissionStatus == 'approved' ||
      _submissionStatus == 'cancelled';

  bool get _hasUploadingMedia => _answers.values.any((d) => d.isUploadingMedia);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;

    _assignment = ModalRoute.of(context)!.settings.arguments as Assignment;
    _loadQuestionnaireAndSubmission();
  }

  @override
  void dispose() {
    for (final c in _textControllers.values) {
      c.dispose();
    }
    for (final c in _numberControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<QuestionLogicDto> _getIncomingLogics(QuestionDto q) {
    final questionnaire = _questionnaire;
    if (questionnaire == null) return const [];

    final List<QuestionLogicDto> result = [];
    for (final src in questionnaire.questions) {
      for (final lg in src.outgoingLogics) {
        if (lg.gotoQuestionId == q.id) {
          result.add(lg);
        }
      }
    }
    return result;
  }

  QuestionDto? _findQuestionById(int id) {
    final questionnaire = _questionnaire;
    if (questionnaire == null) return null;
    for (final q in questionnaire.questions) {
      if (q.id == id) return q;
    }
    return null;
  }

  bool _matchLogic(QuestionLogicDto lg) {
    final fromDraft = _answers[lg.fromQuestionId];
    if (fromDraft == null) return false;

    bool ok = true;
    if (lg.triggerOptionId != null) {
      ok = ok && fromDraft.selectedOptionIds.contains(lg.triggerOptionId);
    }
    if (lg.triggerText != null && lg.triggerText!.trim().isNotEmpty) {
      final hay = (fromDraft.textValue ?? '').toLowerCase();
      ok = ok && hay.contains(lg.triggerText!.toLowerCase());
    }
    if (lg.triggerNumber != null) {
      ok = ok && fromDraft.numberValue != null && fromDraft.numberValue == lg.triggerNumber;
    }
    if (lg.triggerOptionId == null &&
        (lg.triggerText == null || lg.triggerText!.trim().isEmpty) &&
        lg.triggerNumber == null) {
      ok = true;
    }
    return ok;
  }

  _DerivedQuestionState _deriveQuestionState(QuestionDto q) {
    final incoming = _getIncomingLogics(q)..sort((a, b) => a.order.compareTo(b.order));
    bool visible = true;
    bool required = q.required;

    for (final lg in incoming) {
      if (!_matchLogic(lg)) continue;
      switch (lg.effect) {
        case 'hide':
          visible = false;
          break;
        case 'show':
          visible = true;
          break;
        case 'require':
          required = true;
          break;
        case 'optional':
          required = false;
          break;
      }
    }

    return _DerivedQuestionState(
      visible: visible,
      required: required,
    );
  }

  bool _isQuestionVisible(QuestionDto q) {
    return _deriveQuestionState(q).visible;
  }

  bool _isQuestionRequired(QuestionDto q) {
    final derived = _deriveQuestionState(q);
    return derived.required;
  }

  bool _hasAnswer(QuestionDto q, AnswerDraft draft) {
    switch (q.type) {
      case 'single':
      case 'multi':
        return draft.selectedOptionIds.isNotEmpty;
      case 'text':
      case 'short_text':
      case 'long_text':
        return (draft.textValue?.trim().isNotEmpty ?? false);
      case 'number':
        return draft.numberValue != null;
      case 'date':
      case 'visit_date':
        return draft.dateValue != null && draft.dateValue!.isNotEmpty;
      case 'time':
      case 'visit_time':
        return draft.timeValue != null && draft.timeValue!.isNotEmpty;
      case 'location':
        return draft.locationLat != null && draft.locationLng != null;
      case 'image':
      case 'video':
      case 'audio':
      case 'file':
        return draft.mediaFileIds.isNotEmpty;
      default:
        return false;
    }
  }

  void _ensureControllersForQuestion(QuestionDto q, AnswerDraft draft) {
    if (q.type == 'text' || q.type == 'short_text' || q.type == 'long_text') {
      _textControllers.putIfAbsent(q.id, () {
        final c = TextEditingController(text: draft.textValue ?? '');
        c.addListener(() {
          draft.textValue = c.text;
        });
        return c;
      });
      final c = _textControllers[q.id]!;
      final desired = draft.textValue ?? '';
      if (c.text != desired) {
        c.text = desired;
      }
    }

    if (q.type == 'number') {
      _numberControllers.putIfAbsent(q.id, () {
        final c = TextEditingController(
          text: draft.numberValue?.toString() ?? '',
        );
        c.addListener(() {
          final v = c.text.trim();
          draft.numberValue = v.isEmpty ? null : double.tryParse(v);
        });
        return c;
      });
      final c = _numberControllers[q.id]!;
      final desired = draft.numberValue?.toString() ?? '';
      if (c.text != desired) {
        c.text = desired;
      }
    }
  }

  Future<void> _loadQuestionnaireAndSubmission() async {
    final qId = _assignment.questionnaire;
    if (qId == null) {
      setState(() {
        _loading = false;
        _error = '任务缺少 questionnaire id';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _qRepo.fetchDetail(qId, assignmentId: _assignment.id),
        _subRepo.getSubmissions(_assignment.id),
      ]);

      final q = results[0] as QuestionnaireDto;
      final submissions = results[1] as List<SubmissionDto>;

      final draftMap = <int, AnswerDraft>{};
      for (final qu in q.questions) {
        draftMap[qu.id] = AnswerDraft(questionId: qu.id);
      }
      if (_assignment.plannedVisitDate != null) {
        final planned = _assignment.plannedVisitDate!;
        final plannedDate =
            '${planned.year.toString().padLeft(4, '0')}-${planned.month.toString().padLeft(2, '0')}-${planned.day.toString().padLeft(2, '0')}';
        for (final qu in q.questions) {
          if (qu.type == 'visit_date') {
            final d = draftMap[qu.id];
            if (d != null && (d.dateValue == null || d.dateValue!.isEmpty)) {
              d.dateValue = plannedDate;
            }
          }
        }
      }

      SubmissionDto? latest;
      if (submissions.isNotEmpty) {
        submissions.sort((a, b) {
          final va = a.version ?? 0;
          final vb = b.version ?? 0;
          if (va != vb) return va.compareTo(vb);
          return a.id.compareTo(b.id);
        });
        latest = submissions.last;

        for (final ans in latest.answers) {
          final d = draftMap[ans.questionId];
          if (d == null) continue;
          d.textValue = ans.textValue;
          d.numberValue = ans.numberValue;
          d.dateValue = ans.dateValue;
          d.timeValue = ans.timeValue;
          d.locationLat = ans.locationLat;
          d.locationLng = ans.locationLng;
          d.locationAddress = ans.locationAddress;
          d.selectedOptionIds = List<int>.from(ans.selectedOptionIds);
          d.mediaFileIds = List<int>.from(ans.mediaFileIds);
        }
      }

      setState(() {
        _questionnaire = q;
        _answers
          ..clear()
          ..addAll(draftMap);
        _submissionId = latest?.id;
        _submissionStatus = latest?.status;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = userMessageFrom(e, fallback: '加载问卷失败，请稍后重试');
      });
    }
  }

  Future<void> _saveDraft() async {
    final q = _questionnaire;
    if (q == null) return;

    if (_answers.values.any((d) => d.isUploadingMedia)) {
      showErrorSnackBar(context, '有图片或视频正在上传，请稍候上传完成后再保存草稿');
      return;
    }

    setState(() {
      _savingDraft = true;
    });

    try {
      final ok = await _syncPlannedVisitDate();
      if (!ok) return;
      final dto = await _subRepo.saveSubmission(
        submissionId: _submissionId,
        assignmentId: _assignment.id,
        answers: _answers,
        includeUnanswered: false,
      );

      if (!mounted) return;
      setState(() {
        _submissionId = dto.id;
        _submissionStatus = dto.status;
        _shouldRefreshOnPop = true;
      });

      showSuccessSnackBar(context, '草稿已保存');
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e, fallback: '保存草稿失败，请稍后重试');
    } finally {
      if (mounted) {
        setState(() {
          _savingDraft = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    final q = _questionnaire;
    if (q == null) return;

    if (_answers.values.any((d) => d.isUploadingMedia)) {
      showErrorSnackBar(context, '有图片或视频正在上传，请稍候上传完成后再提交');
      return;
    }

    final visibleQuestions = q.questions.where(_isQuestionVisible).toList();
    for (final qu in visibleQuestions) {
      if (!_isQuestionRequired(qu)) continue;
      final draft = _answers[qu.id]!;
      if (!_hasAnswer(qu, draft)) {
        showErrorSnackBar(context, '还有必答题未填写：${qu.text}');
        return;
      }
    }

    setState(() {
      _submitting = true;
    });

    try {
      final ok = await _syncPlannedVisitDate();
      if (!ok) return;
      if (_submissionId == null) {
        final created = await _subRepo.saveSubmission(
          submissionId: null,
          assignmentId: _assignment.id,
          answers: _answers,
          includeUnanswered: false,
        );
        _submissionId = created.id;
        _submissionStatus = created.status;
      } else {
        final saved = await _subRepo.saveSubmission(
          submissionId: _submissionId,
          assignmentId: _assignment.id,
          answers: _answers,
          includeUnanswered: false,
        );
        _submissionStatus = saved.status;
      }

      final dto = await _subRepo.submitSubmission(_submissionId!);

      if (!mounted) return;
      setState(() {
        _submissionStatus = dto.status;
        _shouldRefreshOnPop = true;
      });

      if (!mounted) return;
      showSuccessSnackBar(context, '问卷已提交');
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e, fallback: '提交失败，请稍后重试');
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<AssetEntity?> _captureMediaByType(String mediaType) async {
    final bool isImage = mediaType == 'image';

    final config = CameraPickerConfig(
      enableRecording: !isImage,
      onlyEnableRecording: !isImage,
      enableAudio: !isImage,
    );

    final AssetEntity? entity = await CameraPicker.pickFromCamera(
      context,
      pickerConfig: config,
    );

    return entity;
  }

  Future<List<AssetEntity>?> _pickAssetsByType(String mediaType) {
    final AssetType assetType = mediaType == 'image'
        ? AssetType.image
        : mediaType == 'video'
            ? AssetType.video
            : AssetType.audio;

    final filterOptions = FilterOptionGroup()
      ..setOption(
        assetType,
        const FilterOption(),
      );

    final RequestType requestType = mediaType == 'image'
        ? RequestType.image
        : mediaType == 'video'
            ? RequestType.video
            : RequestType.audio;

    return AssetPicker.pickAssets(
      context,
      pickerConfig: AssetPickerConfig(
        requestType: requestType,
        maxAssets: 20,
        filterOptions: filterOptions,
        textDelegate: const _ChinesePickerTextDelegate(),
      ),
    );
  }

  Future<void> _uploadPickedAssets(
    QuestionDto q,
    AnswerDraft draft,
    String mediaType,
    List<AssetEntity> assets,
  ) async {
    if (assets.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final label = mediaType == 'image'
            ? '图片'
            : mediaType == 'video'
                ? '视频'
                : '音频';
        return AlertDialog(
          title: Text('上传$label'),
          content: Text('已选择 ${assets.length} 个文件，是否立即上传？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('上传'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      draft.isUploadingMedia = true;
      _pendingUploads.putIfAbsent(q.id, () => []);
    });

    final uploadedDtos = <MediaFileDto>[];
    int successFiles = 0;

    try {
      for (final asset in assets) {
        final file = await asset.file;
        if (file == null) continue;

        final pending = _PendingUpload(
          path: file.path,
          mediaType: mediaType,
          progress: 0.0,
        );
        setState(() {
          _pendingUploads[q.id]!.add(pending);
        });

        final bytes = await file.readAsBytes();
        final filename = file.path.split('/').last;

        final dto = await _subRepo.uploadMedia(
          questionId: q.id,
          mediaType: mediaType,
          fileBytes: bytes,
          filename: filename,
          onProgress: (sent, totalBytes) {
            if (!mounted || totalBytes == 0) return;
            final p = sent / totalBytes;
            setState(() {
              pending.progress = p.clamp(0.0, 1.0);
            });
          },
        );

        if (!mounted) return;

        uploadedDtos.add(dto);
        successFiles++;
      }

      if (!mounted) return;

      setState(() {
        _pendingUploads.remove(q.id);
        for (final dto in uploadedDtos) {
          _mediaCache[dto.id] = dto;
          if (!draft.mediaFileIds.contains(dto.id)) {
            draft.mediaFileIds.add(dto.id);
          }
        }
      });

      final successMsg = mediaType == 'image'
          ? '成功上传 $successFiles 张图片'
          : mediaType == 'video'
              ? '成功上传 $successFiles 段视频'
              : '成功上传 $successFiles 段音频';
      showSuccessSnackBar(context, successMsg);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pendingUploads.remove(q.id);
      });
      showErrorSnackBar(context, e, fallback: '上传失败，请稍后重试');
    } finally {
      if (mounted) {
        setState(() {
          draft.isUploadingMedia = false;
        });
      }
    }
  }

  Future<void> _pickAndUploadMedia(
    QuestionDto q,
    AnswerDraft draft,
    String mediaType,
  ) async {
    if (_isReadOnly ||
        draft.isUploadingMedia ||
        _pendingUploads[q.id]?.isNotEmpty == true) {
      return;
    }

    final String? choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        final isAudio = mediaType == 'audio';
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isAudio)
                ListTile(
                  leading: Icon(
                    mediaType == 'image' ? Icons.photo_camera : Icons.videocam,
                  ),
                  title: Text(mediaType == 'image' ? '拍照上传' : '拍摄视频上传'),
                  onTap: () => Navigator.of(ctx).pop('camera'),
                ),
              ListTile(
                leading: Icon(isAudio ? Icons.audiotrack : Icons.photo_library),
                title: Text(
                  mediaType == 'image'
                      ? '从相册选择图片'
                      : mediaType == 'video'
                          ? '从相册选择视频'
                          : '选择音频文件',
                ),
                onTap: () => Navigator.of(ctx).pop('gallery'),
              ),
              const Divider(height: 0),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('取消'),
                onTap: () => Navigator.of(ctx).pop(null),
              ),
            ],
          ),
        );
      },
    );

    if (choice == null) return;

    List<AssetEntity> assets = [];

    if (choice == 'camera') {
      final entity = await _captureMediaByType(mediaType);
      if (entity != null) assets = [entity];
    } else if (choice == 'gallery') {
      final picked = await _pickAssetsByType(mediaType);
      if (picked != null && picked.isNotEmpty) assets = picked;
    }

    if (assets.isEmpty) return;
    await _uploadPickedAssets(q, draft, mediaType, assets);
  }

  Future<void> _ensureMediaLoaded(List<int> ids) async {
    final needLoad = ids
        .where(
          (id) =>
              !_mediaCache.containsKey(id) && !_loadingMediaIds.contains(id),
        )
        .toList();
    if (needLoad.isEmpty) return;

    _loadingMediaIds.addAll(needLoad);

    try {
      final list = await _subRepo.fetchMediaFilesByIds(needLoad);
      if (!mounted) return;
      setState(() {
        for (final m in list) {
          _mediaCache[m.id] = m;
        }
      });
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e, fallback: '加载媒体信息失败，请稍后再试');
    } finally {
      _loadingMediaIds.removeAll(needLoad);
    }
  }

  Future<Uint8List?> _loadVideoThumbnail(int mediaId, String videoUrl) async {
    if (_videoThumbCache.containsKey(mediaId)) {
      return _videoThumbCache[mediaId]!;
    }

    try {
      final bytes = await vt.VideoThumbnail.thumbnailData(
        video: videoUrl,
        imageFormat: vt.ImageFormat.JPEG,
        maxWidth: 300,
        quality: 75,
      );

      if (bytes != null) {
        _videoThumbCache[mediaId] = bytes;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  void _removeMedia(QuestionDto q, AnswerDraft draft, int mediaId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('删除媒体'),
          content: const Text('确定要删除这个文件吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: AppButtonStyles.dangerFilled(ctx),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (confirmed != true) return;

    setState(() {
      draft.mediaFileIds.remove(mediaId);
      _mediaCache.remove(mediaId);
      _videoThumbCache.remove(mediaId);
    });

    showSuccessSnackBar(context, '已删除');
  }

  Widget _buildMediaThumbnails(
    QuestionDto q,
    AnswerDraft draft,
    String mediaType,
  ) {
    final ids = draft.mediaFileIds;
    final pendingList = _pendingUploads[q.id] ?? [];

    if (ids.isEmpty && pendingList.isEmpty) {
      return const SizedBox.shrink();
    }

    if (ids.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureMediaLoaded(ids);
      });
    }

    final mediaList = ids
        .map((id) => _mediaCache[id])
        .whereType<MediaFileDto>()
        .toList();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < mediaList.length; i++)
            GestureDetector(
              onTap: () {
                if (mediaType == "image") {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ImageGalleryPage(images: mediaList, initialIndex: i),
                    ),
                  );
                } else if (mediaType == "video") {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          VideoGalleryPage(videos: mediaList, initialIndex: i),
                    ),
                  );
                } else if (mediaType == "audio") {
                  final url = mediaList[i].fileUrl;
                  if (url.isNotEmpty) {
                    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  }
                }
              },
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: mediaType == 'image' ? 80 : 100,
                      height: mediaType == 'image' ? 80 : 60,
                      child: mediaType == 'image'
                          ? Image.network(
                              mediaList[i].fileUrl,
                              fit: BoxFit.cover,
                            )
                          : mediaType == 'video'
                              ? FutureBuilder<Uint8List?>(
                                  future: _loadVideoThumbnail(
                                    mediaList[i].id,
                                    mediaList[i].fileUrl,
                                  ),
                                  builder: (context, snapshot) {
                                    if (snapshot.hasData && snapshot.data != null) {
                                      return Image.memory(
                                        snapshot.data!,
                                        fit: BoxFit.cover,
                                      );
                                    }
                                    return Container(
                                      color: Colors.black87,
                                      child: const Center(
                                        child: Icon(
                                          Icons.videocam,
                                          color: Colors.white54,
                                          size: 28,
                                        ),
                                      ),
                                    );
                                  },
                                )
                              : Container(
                                  color: Colors.blueGrey.shade900,
                                  child: const Center(
                                    child: Icon(
                                      Icons.audiotrack,
                                      color: Colors.white70,
                                      size: 28,
                                    ),
                                  ),
                                ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: GestureDetector(
                      onTap: () => _removeMedia(q, draft, mediaList[i].id),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(2),
                        child: const Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          for (final pending in pendingList)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: mediaType == 'image' ? 80 : 100,
                    height: mediaType == 'image' ? 80 : 60,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (pending.mediaType == 'image')
                          Image.file(File(pending.path), fit: BoxFit.cover)
                        else if (pending.mediaType == 'video')
                          Container(
                            color: Colors.black87,
                            child: const Center(
                              child: Icon(
                                Icons.videocam,
                                color: Colors.white54,
                                size: 28,
                              ),
                            ),
                          )
                        else
                          Container(
                            color: Colors.blueGrey.shade900,
                            child: const Center(
                              child: Icon(
                                Icons.audiotrack,
                                color: Colors.white54,
                                size: 28,
                              ),
                            ),
                          ),
                        Container(color: Colors.black26),
                      ],
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          ),
                          SizedBox(width: 6),
                          Text(
                            '上传中…',
                            style: TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SizedBox(
                    height: 4,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                      child: LinearProgressIndicator(
                        value: pending.progress.clamp(0.0, 1.0),
                        backgroundColor: Colors.white12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildQuestionBody(QuestionDto q, AnswerDraft draft) {
    final readOnly = _isReadOnly;
    _ensureControllersForQuestion(q, draft);

    switch (q.type) {
      case 'title':
        return Text(
          q.text,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        );
      case 'single':
        return Column(
          children: [
            for (final opt in q.options)
              RadioListTile<int>(
                value: opt.id,
                groupValue: draft.selectedOptionIds.isNotEmpty
                    ? draft.selectedOptionIds.first
                    : null,
                onChanged: readOnly
                    ? null
                    : (v) {
                        setState(() {
                          draft.selectedOptionIds = v == null ? [] : [v];
                        });
                      },
                title: Text(opt.text),
              ),
          ],
        );
      case 'multi':
        return Column(
          children: [
            for (final opt in q.options)
              CheckboxListTile(
                value: draft.selectedOptionIds.contains(opt.id),
                onChanged: readOnly
                    ? null
                    : (checked) {
                        setState(() {
                          if (checked == true) {
                            if (!draft.selectedOptionIds.contains(opt.id)) {
                              draft.selectedOptionIds.add(opt.id);
                            }
                          } else {
                            draft.selectedOptionIds.remove(opt.id);
                          }
                        });
                      },
                title: Text(opt.text),
              ),
          ],
        );
      case 'text':
      case 'short_text':
        return TextFormField(
          controller: _textControllers[q.id],
          maxLines: 1,
          readOnly: readOnly,
          decoration: const InputDecoration(
            hintText: '请输入内容',
          ),
        );
      case 'long_text':
        return TextFormField(
          controller: _textControllers[q.id],
          maxLines: 4,
          readOnly: readOnly,
          decoration: const InputDecoration(
            hintText: '请输入详细内容',
          ),
        );
      case 'number':
        return TextFormField(
          controller: _numberControllers[q.id],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          readOnly: readOnly,
          decoration: const InputDecoration(
            hintText: '请输入数字',
          ),
        );
      case 'date':
      case 'visit_date':
        return Row(
          children: [
            Expanded(
              child: TextFormField(
                readOnly: true,
                decoration: const InputDecoration(
                  hintText: '选择日期',
                ),
                controller: TextEditingController(text: draft.dateValue ?? ''),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: readOnly
                  ? null
                  : () async {
                      final now = DateTime.now();
                      DateTime first = DateTime(now.year - 1);
                      DateTime last = DateTime(now.year + 2);
                      Set<DateTime> avoidDates = {};

                      if (q.type == 'visit_date') {
                        final projectStart = _assignment.projectStartDate;
                        final projectEnd = _assignment.projectEndDate;
                        if (projectStart != null && projectEnd != null) {
                          final start = DateTime(
                            projectStart.year,
                            projectStart.month,
                            projectStart.day,
                          );
                          final end = DateTime(
                            projectEnd.year,
                            projectEnd.month,
                            projectEnd.day,
                          );
                          first = start.isAfter(now)
                              ? start
                              : DateTime(now.year, now.month, now.day);
                          last = end;
                        }
                        avoidDates = _assignment.avoidVisitDates
                            .map((e) => DateTime.parse(e))
                            .map((d) => DateTime(d.year, d.month, d.day))
                            .toSet();
                      }

                      if (first.isAfter(last)) {
                        if (!context.mounted) return;
                        showErrorSnackBar(context, '项目周期已结束，无法选择日期');
                        return;
                      }

                      DateTime? findFirstSelectable(
                        DateTime start,
                        DateTime end,
                        Set<DateTime> blocked,
                      ) {
                        var cur = DateTime(start.year, start.month, start.day);
                        final lastDate = DateTime(end.year, end.month, end.day);
                        while (!cur.isAfter(lastDate)) {
                          if (!blocked.contains(cur)) return cur;
                          cur = cur.add(const Duration(days: 1));
                        }
                        return null;
                      }

                      final today = DateTime.now();
                      final todayDate = DateTime(today.year, today.month, today.day);
                      final isVisitDate = q.type == 'visit_date';
                      final maxDate = isVisitDate && last.isAfter(todayDate) ? todayDate : last;

                      if (maxDate.isBefore(first)) {
                        if (!context.mounted) return;
                        showErrorSnackBar(context, '走访日期不能选择未来日期');
                        return;
                      }

                      DateTime? initialDate;
                      if (draft.dateValue != null && draft.dateValue!.isNotEmpty) {
                        final parsed = DateTime.tryParse(draft.dateValue!);
                        if (parsed != null &&
                            !parsed.isBefore(first) &&
                            !parsed.isAfter(maxDate) &&
                            !avoidDates.contains(DateTime(parsed.year, parsed.month, parsed.day))) {
                          initialDate = DateTime(parsed.year, parsed.month, parsed.day);
                        }
                      }
                      initialDate ??= findFirstSelectable(first, maxDate, avoidDates);
                      if (initialDate == null) {
                        if (!context.mounted) return;
                        showErrorSnackBar(context, '项目周期内无可选日期');
                        return;
                      }

                      final picked = await showDatePicker(
                        context: context,
                        initialDate: initialDate,
                        firstDate: first,
                        lastDate: maxDate,
                        selectableDayPredicate: isVisitDate
                            ? (day) {
                                final d = DateTime(day.year, day.month, day.day);
                                if (d.isAfter(todayDate)) return false;
                                return !avoidDates.contains(d);
                              }
                            : null,
                        builder: (context, child) {
                          final theme = Theme.of(context);
                          return Theme(
                            data: theme.copyWith(
                              dialogTheme: DialogThemeData(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked == null) return;
                      setState(() {
                        draft.dateValue =
                            '${picked.year.toString().padLeft(4, '0')}-'
                            '${picked.month.toString().padLeft(2, '0')}-'
                            '${picked.day.toString().padLeft(2, '0')}';
                      });
                    },
              child: const Text('选择日期'),
            ),
          ],
        );
      case 'time':
      case 'visit_time':
        return Row(
          children: [
            Expanded(
              child: TextFormField(
                readOnly: true,
                decoration: const InputDecoration(
                  hintText: '选择时间',
                ),
                controller: TextEditingController(text: draft.timeValue ?? ''),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: readOnly
                  ? null
                  : () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                        builder: (context, child) {
                          final theme = Theme.of(context);
                          return Theme(
                            data: theme.copyWith(
                              dialogTheme: DialogThemeData(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked == null) return;
                      setState(() {
                        draft.timeValue =
                            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                      });
                    },
              child: const Text('选择时间'),
            ),
          ],
        );
      case 'location':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    draft.locationLat != null && draft.locationLng != null
                        ? '已定位：${draft.locationLat}, ${draft.locationLng}'
                        : '未定位',
                  ),
                ),
                OutlinedButton(
                  onPressed: readOnly
                      ? null
                      : () async {
                          final perm = await Geolocator.checkPermission();
                          if (perm == LocationPermission.denied ||
                              perm == LocationPermission.deniedForever) {
                            final req = await Geolocator.requestPermission();
                            if (req == LocationPermission.denied ||
                                req == LocationPermission.deniedForever) {
                              showErrorSnackBar(context, '定位权限被拒绝');
                              return;
                            }
                          }
                          final pos = await Geolocator.getCurrentPosition();
                          setState(() {
                            draft.locationLat = pos.latitude;
                            draft.locationLng = pos.longitude;
                          });
                        },
                  child: const Text('获取定位'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: draft.locationAddress ?? '',
              readOnly: readOnly,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: '地址描述（可选）',
              ),
              onChanged: (v) {
                draft.locationAddress = v;
              },
            ),
          ],
        );
      case 'image':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '图片上传题目（可上传多张图片）',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('已上传：${draft.mediaFileIds.length} 张'),
                const SizedBox(width: 8),
                if (draft.isUploadingMedia)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: readOnly || draft.isUploadingMedia
                  ? null
                  : () => _pickAndUploadMedia(q, draft, 'image'),
              child: const Text('上传图片'),
            ),
            _buildMediaThumbnails(q, draft, 'image'),
            if (draft.mediaError != null) ...[
              const SizedBox(height: 8),
              Text(
                draft.mediaError!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ],
        );
      case 'video':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '视频上传题目（可上传多段视频）',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('已上传：${draft.mediaFileIds.length} 段'),
                const SizedBox(width: 8),
                if (draft.isUploadingMedia)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: readOnly || draft.isUploadingMedia
                  ? null
                  : () => _pickAndUploadMedia(q, draft, 'video'),
              child: const Text('上传视频'),
            ),
            _buildMediaThumbnails(q, draft, 'video'),
            if (draft.mediaError != null) ...[
              const SizedBox(height: 8),
              Text(
                draft.mediaError!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ],
        );
      case 'audio':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '音频上传题目（可上传多段音频）',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('已上传：${draft.mediaFileIds.length} 段'),
                const SizedBox(width: 8),
                if (draft.isUploadingMedia)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: readOnly || draft.isUploadingMedia
                  ? null
                  : () => _pickAndUploadMedia(q, draft, 'audio'),
              child: const Text('上传音频'),
            ),
            _buildMediaThumbnails(q, draft, 'audio'),
            if (draft.mediaError != null) ...[
              const SizedBox(height: 8),
              Text(
                draft.mediaError!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ],
        );
      default:
        return Text(
          '暂不支持的题目类型：${q.type}',
          style: const TextStyle(color: Colors.red),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('问卷填写')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loadQuestionnaireAndSubmission,
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final q = _questionnaire;
    if (q == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('问卷填写')),
        body: const Center(child: Text('问卷数据为空')),
      );
    }

    final theme = Theme.of(context);

    final visibleQuestions = q.questions.where(_isQuestionVisible).toList();
    final progressQuestions =
        visibleQuestions.where((item) => item.type != 'title').toList();
    final total = progressQuestions.length;

    int answeredCount = 0;
    for (final qu in progressQuestions) {
      final d = _answers[qu.id];
      if (d != null && _hasAnswer(qu, d)) {
        answeredCount++;
      }
    }

    final progressValue = total == 0 ? 0.0 : answeredCount / total;

    final subtitleParts = <String>[];
    if ((_assignment.clientName ?? '').isNotEmpty) {
      subtitleParts.add(_assignment.clientName!);
    }
    if ((_assignment.projectName ?? '').isNotEmpty) {
      subtitleParts.add(_assignment.projectName!);
    }
    if ((_assignment.storeName ?? '').isNotEmpty) {
      subtitleParts.add(_assignment.storeName!);
    }
    final subtitleText = subtitleParts.join(' · ');

    return PopScope(
      canPop: !_shouldRefreshOnPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_shouldRefreshOnPop) {
          Navigator.of(context).pop(true);
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          backgroundColor: theme.colorScheme.surface,
          foregroundColor: theme.colorScheme.onSurface,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _assignment.questionnaireTitle ?? '问卷填写',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitleText.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitleText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: CustomScrollView(
              slivers: [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(value: progressValue),
                        ),
                        const SizedBox(width: 12),
                        Text('$answeredCount/$total'),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final qu = visibleQuestions[index];
                    final draft =
                        _answers[qu.id] ?? AnswerDraft(questionId: qu.id);
                    final derived = _deriveQuestionState(qu);

                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == visibleQuestions.length - 1 ? 0 : 12,
                      ),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (qu.type == 'title')
                                Text(
                                  qu.text,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontSize: qu.fontSize.toDouble(),
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              else ...[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (derived.required)
                                      const Text(
                                        '* ',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    Expanded(
                                      child: Text(
                                        qu.text,
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontSize: qu.fontSize.toDouble(),
                                        ),
                                      ),
                                    ),
                                    if (qu.score > 0)
                                      Container(
                                        margin: const EdgeInsets.only(left: 6, top: 2),
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          '${qu.score}分',
                                          style: TextStyle(
                                            color: Colors.blue.shade700,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _buildQuestionBody(qu, draft),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: visibleQuestions.length,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              if (!_isReadOnly)
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: (_savingDraft || _hasUploadingMedia)
                                  ? null
                                  : _saveDraft,
                              child: _savingDraft
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('保存草稿'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: (_submitting || _hasUploadingMedia)
                                  ? null
                                  : _submit,
                              child: _submitting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation(
                                          Colors.white,
                                        ),
                                      ),
                                    )
                                  : const Text('提交问卷'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    () {
                      final baseText = _submissionStatus == null
                          ? '当前状态：未保存'
                          : '当前状态：${formatStatusLabel(_submissionStatus)}';
                      return _isReadOnly ? '$baseText（仅供查看）' : baseText;
                    }(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
              if (_submissionId != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('查看审核沟通'),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SubmissionCommentsPage(
                                submissionId: _submissionId!,
                                title:
                                    _assignment.questionnaireTitle ?? '审核沟通',
                                status: _submissionStatus,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ImageGalleryPage extends StatefulWidget {
  final List<MediaFileDto> images;
  final int initialIndex;

  const ImageGalleryPage({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  @override
  State<ImageGalleryPage> createState() => _ImageGalleryPageState();
}

class _ImageGalleryPageState extends State<ImageGalleryPage> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('${_currentIndex + 1}/${widget.images.length}'),
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemCount: widget.images.length,
        itemBuilder: (context, index) {
          final media = widget.images[index];
          return InteractiveViewer(
            child: Center(
              child: Image.network(
                media.fileUrl,
                fit: BoxFit.contain,
                errorBuilder: (ctx, err, stack) => const Icon(
                  Icons.broken_image,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class VideoGalleryPage extends StatefulWidget {
  final List<MediaFileDto> videos;
  final int initialIndex;

  const VideoGalleryPage({
    super.key,
    required this.videos,
    required this.initialIndex,
  });

  @override
  State<VideoGalleryPage> createState() => _VideoGalleryPageState();
}

class _VideoGalleryPageState extends State<VideoGalleryPage> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('${_currentIndex + 1}/${widget.videos.length}'),
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemCount: widget.videos.length,
        itemBuilder: (context, index) {
          final media = widget.videos[index];
          return _InlineVideoPlayer(videoUrl: media.fileUrl);
        },
      ),
    );
  }
}

class _InlineVideoPlayer extends StatefulWidget {
  final String videoUrl;

  const _InlineVideoPlayer({required this.videoUrl});

  @override
  State<_InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<_InlineVideoPlayer> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _initialized = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            VideoPlayer(_controller),
            _PlayPauseOverlay(controller: _controller),
            VideoProgressIndicator(_controller, allowScrubbing: true),
          ],
        ),
      ),
    );
  }
}

class VideoPlayerPage extends StatefulWidget {
  final String videoUrl;

  const VideoPlayerPage({super.key, required this.videoUrl});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _initialized = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: const Text('视频播放')),
      body: Center(
        child: _initialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    VideoPlayer(_controller),
                    _PlayPauseOverlay(controller: _controller),
                    VideoProgressIndicator(_controller, allowScrubbing: true),
                  ],
                ),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}

class _PlayPauseOverlay extends StatefulWidget {
  final VideoPlayerController controller;

  const _PlayPauseOverlay({required this.controller});

  @override
  State<_PlayPauseOverlay> createState() => _PlayPauseOverlayState();
}

class _PlayPauseOverlayState extends State<_PlayPauseOverlay> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          if (widget.controller.value.isPlaying) {
            widget.controller.pause();
          } else {
            widget.controller.play();
          }
        });
      },
      child: Stack(
        children: [
          Positioned.fill(child: Container(color: Colors.black26)),
          Center(
            child: Icon(
              widget.controller.value.isPlaying
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_fill,
              color: Colors.white,
              size: 64,
            ),
          ),
        ],
      ),
    );
  }
}
