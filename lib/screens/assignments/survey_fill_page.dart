// lib/screens/assignments/survey_fill_page.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:wechat_camera_picker/wechat_camera_picker.dart';

import '../../models/api_models.dart';
import '../../services/api_service.dart';
import '../../utils/error_message.dart';
import '../../utils/snackbar.dart';
import 'submission_comments_page.dart';

/// 自定义中文文案，让底部按钮和提示都显示中文
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

class _PendingUpload {
  final String path; // 本地文件路径
  final String mediaType; // 'image' / 'video'
  double progress; // 0.0 ~ 1.0

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

  QuestionnaireDto? _questionnaire;
  bool _loading = true;
  String? _error;

  // 每题一个草稿 AnswerDraft
  final Map<int, AnswerDraft> _answers = {};

  // 媒体缓存：mediaFileId -> MediaFileDto（包含 fileUrl、mediaType）
  final Map<int, MediaFileDto> _mediaCache = {};

  // 当前正在加载信息的媒体 ID（避免重复重复请求）
  final Set<int> _loadingMediaIds = {};

  // 某个题目正在上传的本地文件列表（用于画缩略图上的圈圈）
  final Map<int, List<_PendingUpload>> _pendingUploads = {};

  // 视频缩略图缓存：mediaFileId -> 缩略图二进制数据
  final Map<int, Uint8List> _videoThumbCache = {};

  // 是否已经做过初始化（拿到路由参数）
  bool _inited = false;

  // 当前这份问卷在后端的 Submission 记录
  int? _submissionId;
  String?
  _submissionStatus; // 'draft' / 'submitted' / 'needs_revision' / 'resubmitted' / ...

  bool _savingDraft = false;
  bool _submitting = false;

  // 用于告诉上一个页面“我这边有更新，需要刷新列表”
  bool _shouldRefreshOnPop = false;

  // 已提交 / 已重新提交 / 已通过 / 已作废 的问卷只允许查看
  bool get _isReadOnly =>
      _submissionStatus == 'submitted' ||
      _submissionStatus == 'resubmitted' ||
      _submissionStatus == 'approved' ||
      _submissionStatus == 'cancelled';

  // 是否存在正在上传媒体的题目
  bool get _hasUploadingMedia => _answers.values.any((d) => d.isUploadingMedia);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;

    _assignment = ModalRoute.of(context)!.settings.arguments as Assignment;

    _loadQuestionnaireAndSubmission();
  }

  /// 找出所有指向某题的逻辑（谁的 outgoing_logics 里 goto_question == q.id）
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

  /// 判断一题是否“应该显示”
  /// - 没有逻辑：默认显示
  /// - 有逻辑：只要有一条逻辑的触发条件被满足，就显示；否则隐藏
  bool _isQuestionVisible(QuestionDto q) {
    final incoming = _getIncomingLogics(q);
    if (incoming.isEmpty) return true;

    for (final lg in incoming) {
      final fromDraft = _answers[lg.fromQuestionId];
      if (fromDraft == null) continue;
      final triggerOptId = lg.triggerOptionId;
      if (fromDraft.selectedOptionIds.contains(triggerOptId)) {
        return true;
      }
    }
    return false;
  }

  /// 题目是否已经作答（用于提交时的必填校验）
  bool _hasAnswer(QuestionDto q, AnswerDraft draft) {
    switch (q.type) {
      case 'single':
      case 'multi':
        return draft.selectedOptionIds.isNotEmpty;
      case 'text':
        return (draft.textValue?.trim().isNotEmpty ?? false);
      case 'number':
        return draft.numberValue != null;
      case 'image':
      case 'video':
      case 'file':
        return draft.mediaFileIds.isNotEmpty;
      default:
        return false;
    }
  }

  /// 一次性加载：问卷详情 + 已有提交（回填）
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
      final api = ApiService();

      // 并行请求：问卷 + 该任务所有提交记录
      final results = await Future.wait([
        api.fetchQuestionnaireDetail(qId),
        api.getSubmissions(_assignment.id),
      ]);

      final q = results[0] as QuestionnaireDto;
      final submissions = results[1] as List<SubmissionDto>;

      // 先为每个题目准备一个空草稿
      final draftMap = <int, AnswerDraft>{};
      for (final qu in q.questions) {
        draftMap[qu.id] = AnswerDraft(questionId: qu.id);
      }

      // 找出最新一条提交（按 version 优先，其次 id）
      SubmissionDto? latest;
      if (submissions.isNotEmpty) {
        submissions.sort((a, b) {
          final va = a.version ?? 0;
          final vb = b.version ?? 0;
          if (va != vb) return va.compareTo(vb);
          return a.id.compareTo(b.id);
        });
        latest = submissions.last;

        // 回填答案到 draftMap 里
        for (final ans in latest.answers) {
          final d = draftMap[ans.questionId];
          if (d == null) continue;
          d.textValue = ans.textValue;
          d.numberValue = ans.numberValue;
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
    } on ApiException catch (e) {
      setState(() {
        _loading = false;
        _error = userMessageFrom(e, fallback: '加载问卷失败，请稍后重试');
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = userMessageFrom(e, fallback: '加载问卷失败，请稍后重试');
      });
    }
  }

  /// 保存草稿：不校验必填，任何情况都允许
  Future<void> _saveDraft() async {
    final q = _questionnaire;
    if (q == null) return;

    // 0. 如果还有图片/视频正在上传，禁止保存草稿
    final hasUploading = _answers.values.any((d) => d.isUploadingMedia);
    if (hasUploading) {
      showErrorSnackBar(context, '有图片或视频正在上传，请稍候上传完成后再保存草稿');
      return;
    }

    setState(() {
      _savingDraft = true;
    });

    try {
      final api = ApiService();

      // 草稿就是草稿，状态始终是 draft
      final dto = await api.saveSubmission(
        submissionId: _submissionId,
        assignmentId: _assignment.id,
        status: 'draft',
        answers: _answers,
        includeUnanswered: false, // 草稿没必要传空题
      );

      if (!mounted) return;
      setState(() {
        _submissionId = dto.id;
        _submissionStatus = dto.status;
        _shouldRefreshOnPop = true; // 草稿保存成功后，需要刷新列表
      });

      showSuccessSnackBar(context, '草稿已保存');
    } on ApiException catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e, fallback: '保存草稿失败，请稍后重试');
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

  /// 提交问卷：只对“可见 + 必填”的题做校验
  Future<void> _submit() async {
    final q = _questionnaire;
    if (q == null) return;

    // 0. 如果还有图片/视频正在上传，禁止提交
    final hasUploading = _answers.values.any((d) => d.isUploadingMedia);
    if (hasUploading) {
      showErrorSnackBar(context, '有图片或视频正在上传，请稍候上传完成后再提交');
      return;
    }

    // 1. 校验必填
    final visibleQuestions = q.questions.where(_isQuestionVisible).toList();

    for (final qu in visibleQuestions) {
      if (!qu.required) continue;
      final draft = _answers[qu.id]!;
      if (!_hasAnswer(qu, draft)) {
        showErrorSnackBar(context, '还有必答题未填写：${qu.text}');
        return;
      }
    }

    // 2. 提交
    setState(() {
      _submitting = true;
    });

    try {
      final api = ApiService();

      // 如果当前状态是待修改（needs_revision），这次就是“重新提交”
      final statusToSend = (_submissionStatus == 'needs_revision')
          ? 'resubmitted'
          : 'submitted';

      final dto = await api.saveSubmission(
        submissionId: _submissionId,
        assignmentId: _assignment.id,
        status: statusToSend,
        answers: _answers,
        includeUnanswered: false,
      );

      if (!mounted) return;
      setState(() {
        _submissionId = dto.id;
        _submissionStatus = dto.status;
        _shouldRefreshOnPop = true; // 提交成功后，需要刷新列表
      });

      showSuccessSnackBar(context, '问卷已提交');
    } on ApiException catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e, fallback: '提交失败，请稍后重试');
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

  /// 使用相机拍摄一张照片或一段视频
  Future<AssetEntity?> _captureMediaByType(String mediaType) async {
    final bool isImage = mediaType == 'image';

    final config = CameraPickerConfig(
      enableRecording: !isImage, // 图片题：不启用录像；视频题：启用录像
      onlyEnableRecording: !isImage, // 视频题：只录制视频，不拍照
      enableAudio: !isImage, // 视频需要声音
    );

    final AssetEntity? entity = await CameraPicker.pickFromCamera(
      context,
      pickerConfig: config,
    );

    return entity;
  }

  /// 使用 wechat_assets_picker 选择图片或视频（支持多选）
  /// 根据 mediaType 只显示图片或视频，并统一中文文案
  Future<List<AssetEntity>?> _pickAssetsByType(String mediaType) {
    final bool pickImage = mediaType == 'image';

    // 只保留一种资源类型的筛选规则
    final filterOptions = FilterOptionGroup()
      ..setOption(
        pickImage ? AssetType.image : AssetType.video,
        const FilterOption(),
      );

    final RequestType requestType = pickImage
        ? RequestType.image
        : RequestType.video;

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

  /// 把从 wechat_assets_picker 选到的 AssetEntity 顺序上传（一个完成再下一个）
  Future<void> _uploadPickedAssets(
    QuestionDto q,
    AnswerDraft draft,
    String mediaType,
    List<AssetEntity> assets,
  ) async {
    if (assets.isEmpty) return;

    // 1. 选择完之后，弹出“是否上传”对话框，有一个上传按钮
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(mediaType == 'image' ? '上传图片' : '上传视频'),
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

    // 2. 标记该题目处于“正在上传”状态
    setState(() {
      draft.isUploadingMedia = true;
      _pendingUploads.putIfAbsent(q.id, () => []);
    });

    final uploadedDtos = <MediaFileDto>[];
    int successFiles = 0;

    try {
      for (final asset in assets) {
        final file = await asset.file;
        if (file == null) {
          continue;
        }

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

        final dto = await ApiService().uploadMedia(
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
          draft.mediaFileIds.add(dto.id);
        }
      });

      final successMsg = mediaType == 'image'
          ? '成功上传 $successFiles 张图片'
          : '成功上传 $successFiles 段视频';
      showSuccessSnackBar(context, successMsg);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _pendingUploads.remove(q.id);
      });
      showErrorSnackBar(context, e, fallback: '上传失败，请稍后重试');
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

  /// 选择并上传媒体
  Future<void> _pickAndUploadMedia(
    QuestionDto q,
    AnswerDraft draft,
    String mediaType,
  ) async {
    if (_isReadOnly || draft.isUploadingMedia) return;

    final String? choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  mediaType == 'image' ? Icons.photo_camera : Icons.videocam,
                ),
                title: Text(mediaType == 'image' ? '拍照上传' : '拍摄视频上传'),
                onTap: () => Navigator.of(ctx).pop('camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text(mediaType == 'image' ? '从相册选择图片' : '从相册选择视频'),
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
      if (entity != null) {
        assets = [entity];
      }
    } else if (choice == 'gallery') {
      final picked = await _pickAssetsByType(mediaType);
      if (picked != null && picked.isNotEmpty) {
        assets = picked;
      }
    }

    if (assets.isEmpty) return;

    await _uploadPickedAssets(q, draft, mediaType, assets);
  }

  /// 根据若干媒体 ID，确保它们已经加载到 _mediaCache 里
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
      final api = ApiService();
      final list = await api.fetchMediaFilesByIds(needLoad);
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

  /// 生成 / 获取某个视频的缩略图（带内存缓存）
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

  // 删除某个媒体文件（仅前端解绑）
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
              child: const Text('删除'),
            ),
          ],
        );
      },
    );

    // ⭐ async gap 之后，先检查 mounted，防止页面已经销毁
    if (!mounted) return;

    if (confirmed != true) return;

    setState(() {
      draft.mediaFileIds.remove(mediaId);
      _mediaCache.remove(mediaId);
      _videoThumbCache.remove(mediaId);
    });

    showSuccessSnackBar(context, '已删除');
  }

  /// 构建某题目的媒体缩略图区域（图片 / 视频共用）
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
      _ensureMediaLoaded(ids);
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
          // 已上传
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
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          VideoGalleryPage(videos: mediaList, initialIndex: i),
                    ),
                  );
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
                          : FutureBuilder<Uint8List?>(
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

          // 正在上传
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
                        else
                          Container(
                            color: Colors.black87,
                            child: const Center(
                              child: Icon(
                                Icons.videocam,
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

  /// 构建不同题型的输入控件
  Widget _buildQuestionBody(QuestionDto q, AnswerDraft draft) {
    final readOnly = _isReadOnly;
    switch (q.type) {
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
        return TextFormField(
          initialValue: draft.textValue ?? '',
          maxLines: null,
          readOnly: readOnly,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '请输入内容',
          ),
          onChanged: readOnly
              ? null
              : (v) {
                  draft.textValue = v;
                },
        );
      case 'number':
        return TextFormField(
          initialValue: draft.numberValue?.toString() ?? '',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          readOnly: readOnly,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '请输入数字',
          ),
          onChanged: readOnly
              ? null
              : (v) {
                  draft.numberValue = double.tryParse(v);
                },
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
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
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
    final total = visibleQuestions.length;

    int answeredCount = 0;
    for (final qu in visibleQuestions) {
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

    return WillPopScope(
      onWillPop: () async {
        if (_shouldRefreshOnPop) {
          Navigator.of(context).pop(true);
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _assignment.questionnaireTitle ?? '问卷填写',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitleText.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitleText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
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
                Expanded(
                  child: ListView.separated(
                    itemCount: visibleQuestions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final qu = visibleQuestions[index];
                      final draft =
                          _answers[qu.id] ?? AnswerDraft(questionId: qu.id);

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (qu.required)
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
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _buildQuestionBody(qu, draft),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),

                // 非只读状态：显示按钮
                if (!_isReadOnly) ...[
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

                // 总是显示状态文案
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    () {
                      final baseText = () {
                        switch (_submissionStatus) {
                          case 'draft':
                            return '当前状态：草稿（尚未提交）';
                          case 'submitted':
                            return '当前状态：已提交（待审核）';
                          case 'needs_revision':
                            return '当前状态：待修改（请查看审核说明）';
                          case 'resubmitted':
                            return '当前状态：已重新提交（待审核）';
                          case 'approved':
                            return '当前状态：已通过审核';
                          case 'cancelled':
                            return '当前状态：已作废';
                          default:
                            return '当前状态：未保存';
                        }
                      }();
                      return _isReadOnly ? '$baseText（仅供查看）' : baseText;
                    }(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ),

                // 有 submissionId 就显示“查看审核沟通”
                if (_submissionId != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('查看审核沟通'),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SubmissionCommentsPage(
                              submissionId: _submissionId!,
                              title: _assignment.questionnaireTitle ?? '审核沟通',
                              status: _submissionStatus,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 全屏图片浏览页面，可左右滑动
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
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
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

/// 全屏视频浏览页面，可左右滑动
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
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemCount: widget.videos.length,
        itemBuilder: (context, index) {
          final media = widget.videos[index];
          return _InlineVideoPlayer(videoUrl: media.fileUrl);
        },
      ),
    );
  }
}

/// 单个视频播放器，用于 VideoGalleryPage 的每一页
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
    _controller = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {
          _initialized = true;
        });
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

/// 单独的视频播放页面（如果以后需要单页播放）
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
    _controller = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {
          _initialized = true;
        });
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
