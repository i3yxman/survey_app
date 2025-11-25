// lib/screens/assignments/survey_fill_page.dart

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'dart:typed_data';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../models/api_models.dart';
import '../../services/api_service.dart';

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

  // 某个题正在上传的整体进度（0.0 ~ 1.0）
  final Map<int, double> _uploadProgress = {};

  // 视频缩略图缓存：mediaFileId -> 缩略图二进制数据
  final Map<int, Uint8List> _videoThumbCache = {};

  // 是否已经做过初始化（拿到路由参数）
  bool _inited = false;

  // 当前这份问卷在后端的 Submission 记录
  int? _submissionId;
  String? _submissionStatus; // 'draft' / 'submitted' / 其他

  bool _savingDraft = false;
  bool _submitting = false;

  // 已提交的问卷只允许查看，不允许再编辑
  bool get _isReadOnly => _submissionStatus == 'submitted';

  // 是否存在正在上传媒体的题目
  bool get _hasUploadingMedia =>
      _answers.values.any((d) => d.isUploadingMedia);

  final ImagePicker _picker = ImagePicker();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;

    _assignment =
        ModalRoute.of(context)!.settings.arguments as Assignment;

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
      if (triggerOptId != null &&
          fromDraft.selectedOptionIds.contains(triggerOptId)) {
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
          d.selectedOptionIds =
              List<int>.from(ans.selectedOptionIds);
          d.mediaFileIds =
              List<int>.from(ans.mediaFileIds);
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
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '加载问卷失败：$e';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('有图片或视频正在上传，请稍候上传完成后再保存草稿'),
        ),
      );
      return;
    }

    setState(() {
      _savingDraft = true;
    });

    try {
      final api = ApiService();
      final dto = await api.saveSubmission(
        submissionId: _submissionId,
        assignmentId: _assignment.id,
        status: 'draft',
        answers: _answers,
        includeUnanswered: false, // 草稿也没必要传空题
      );

      if (!mounted) return;
      setState(() {
        _submissionId = dto.id;
        _submissionStatus = dto.status;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('草稿已保存')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存草稿失败：${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存草稿失败')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('有图片或视频正在上传，请稍候上传完成后再提交'),
        ),
      );
      return;
    }

    // 1. 校验必填
    final visibleQuestions =
        q.questions.where(_isQuestionVisible).toList();

    for (final qu in visibleQuestions) {
      if (!qu.required) continue;
      final draft = _answers[qu.id]!;
      if (!_hasAnswer(qu, draft)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('还有必答题未填写：${qu.text}'),
          ),
        );
        return;
      }
    }

    // 2. 提交
    setState(() {
      _submitting = true;
    });

    try {
      final api = ApiService();
      final dto = await api.saveSubmission(
        submissionId: _submissionId,
        assignmentId: _assignment.id,
        status: 'submitted',
        answers: _answers,
        includeUnanswered: false,
      );

      if (!mounted) return;
      setState(() {
        _submissionId = dto.id;
        _submissionStatus = dto.status;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('问卷已提交')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('提交失败：${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提交失败')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  /// 底部弹出选择：相机 / 相册
  Future<ImageSource?> _pickSource() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('拍摄'),
                onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('从相册选择'),
                onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 选择并上传媒体
  /// - 图片：相册支持多选，拍照单张
  /// - 视频：目前一次一段（可以多次点按钮）
  /// - 选择后先弹出“上传确认”对话框，再开始上传
  /// - 上传时会显示整体进度条
  Future<void> _pickAndUploadMedia(
    QuestionDto q,
    AnswerDraft draft,
    String mediaType,
  ) async {
    if (_isReadOnly) return;

    final source = await _pickSource();
    if (source == null) return;

    // 1. 选文件（图片相册支持多选）
    List<XFile> pickedFiles = [];

    try {
      if (mediaType == 'image') {
        if (source == ImageSource.gallery) {
          // 相册多选图片
          final files = await _picker.pickMultiImage(
            imageQuality: 85,
          );
          pickedFiles = files;
        } else {
          // 拍照单张
          final single = await _picker.pickImage(
            source: source,
            imageQuality: 85,
          );
          if (single != null) {
            pickedFiles = [single];
          }
        }
      } else {
        // 视频目前 image_picker 只支持单选
        final single = await _picker.pickVideo(
          source: source,
          maxDuration: const Duration(seconds: 60),
        );
        if (single != null) {
          pickedFiles = [single];
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开相机/相册失败：$e')),
      );
      return;
    }

    // 用户取消选择
    if (pickedFiles.isEmpty) return;

    // 2. 选择完之后，弹出“是否上传”对话框，有一个上传按钮
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(mediaType == 'image' ? '上传图片' : '上传视频'),
          content: Text('已选择 ${pickedFiles.length} 个文件，是否立即上传？'),
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

    // 3. 开始上传：
    //    先改状态 -> 回到问卷页面时立刻显示“正在上传”和进度条
    setState(() {
      draft.isUploadingMedia = true;
      _uploadProgress[q.id] = 0.0;
    });

    final total = pickedFiles.length;
    int successCount = 0;

    try {
      for (var i = 0; i < total; i++) {
        final file = pickedFiles[i];
        final bytes = await file.readAsBytes();
        final filename = file.name;

        final dto = await ApiService().uploadMedia(
          questionId: q.id,
          mediaType: mediaType,
          fileBytes: bytes,
          filename: filename,
        );

        if (!mounted) return;

        setState(() {
          // 加入缓存，方便显示缩略图
          _mediaCache[dto.id] = dto;
          // 加入当前题目的已上传列表
          draft.mediaFileIds.add(dto.id);
          // 整体进度：按已成功数量 / 总数量 来算
          successCount++;
          _uploadProgress[q.id] = successCount / total;
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mediaType == 'image'
                ? '成功上传 $successCount 张图片'
                : '成功上传 $successCount 段视频',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传失败：${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('上传失败')),
      );
    } finally {
      if (mounted) {
        setState(() {
          draft.isUploadingMedia = false;
          // 上传结束后把进度条去掉（缩略图已经出现）
          _uploadProgress.remove(q.id);
        });
      }
    }
  }

  /// 根据若干媒体 ID，确保它们已经加载到 _mediaCache 里
  Future<void> _ensureMediaLoaded(List<int> ids) async {
    // 需要加载但还没在缓存、也不在“正在加载”列表里的
    final needLoad = ids
        .where((id) => !_mediaCache.containsKey(id) && !_loadingMediaIds.contains(id))
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
      // 简单提示一下即可，不影响主流程
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载媒体信息失败：$e')),
      );
    } finally {
      _loadingMediaIds.removeAll(needLoad);
    }
  }

  /// 生成 / 获取某个视频的缩略图（带内存缓存）
  Future<Uint8List?> _loadVideoThumbnail(int mediaId, String videoUrl) async {
    // 已经有缓存，直接用
    if (_videoThumbCache.containsKey(mediaId)) {
      return _videoThumbCache[mediaId]!;
    }

    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: videoUrl,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 300, // 缩略图最大宽度
        quality: 75,   // 质量 0-100
      );

      if (bytes != null) {
        _videoThumbCache[mediaId] = bytes;
      }

      return bytes;
    } catch (e) {
      // 失败就返回 null，外面用默认占位图
      return null;
    }
  }

  /// 构建某题目的媒体缩略图区域（图片 / 视频共用）
  Widget _buildMediaThumbnails(
    QuestionDto q,
    AnswerDraft draft,
    String mediaType,
  ) {
    final ids = draft.mediaFileIds;
    if (ids.isEmpty) {
      return const SizedBox.shrink();
    }

    // 触发加载（异步，不会阻塞 build）
    _ensureMediaLoaded(ids);

    final mediaList = ids
        .map((id) => _mediaCache[id])
        .whereType<MediaFileDto>()
        .toList();

    if (mediaList.isEmpty) {
      // 数据还在加载中
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: SizedBox(
          height: 40,
          child: Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (mediaType == 'image') {
      // 图片缩略图 + 点击进入图片浏览
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < mediaList.length; i++)
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ImageGalleryPage(
                        images: mediaList,
                        initialIndex: i,
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    mediaList[i].fileUrl,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) => Container(
                      width: 80,
                      height: 80,
                      color: Colors.grey.shade300,
                      child: const Icon(Icons.broken_image),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    } else {
      // 视频缩略图：生成真实缩略图 + 播放按钮
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < mediaList.length; i++)
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => VideoGalleryPage(
                        videos: mediaList,
                        initialIndex: i,
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 100,
                    height: 60,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 缩略图
                        FutureBuilder<Uint8List?>(
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
                            } else {
                              // 缩略图还没生成出来时的占位
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
                            }
                          },
                        ),
                        // 播放按钮覆盖在上面
                        const Center(
                          child: Icon(
                            Icons.play_circle_fill,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
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
                          draft.selectedOptionIds =
                              v == null ? [] : [v];
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
                            if (!draft.selectedOptionIds
                                .contains(opt.id)) {
                              draft.selectedOptionIds.add(opt.id);
                            }
                          } else {
                            draft.selectedOptionIds
                                .remove(opt.id);
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
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
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
              '图片上传题目（可多次上传多张图片）',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey),
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
            // 当前题目正在上传时，显示一个整体进度条
            if (_uploadProgress.containsKey(q.id)) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _uploadProgress[q.id],
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: readOnly || draft.isUploadingMedia
                  ? null
                  : () => _pickAndUploadMedia(q, draft, 'image'),
              child: const Text('上传图片'),
            ),
            // 显示已上传的图片缩略图
            _buildMediaThumbnails(q, draft, 'image'),

            // 如果最近一次上传有错误，在题目下方显示红色提示
            if (draft.mediaError != null) ...[
              const SizedBox(height: 8),
              Text(
                draft.mediaError!,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        );

      case 'video':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '视频上传题目（可多次上传多段视频）',
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
            // 当前题目正在上传时，显示一个整体进度条
            if (_uploadProgress.containsKey(q.id)) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _uploadProgress[q.id],
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: readOnly || draft.isUploadingMedia
                  ? null
                  : () => _pickAndUploadMedia(q, draft, 'video'),
              child: const Text('上传视频'),
            ),
            // 显示已上传的视频缩略图
            _buildMediaThumbnails(q, draft, 'video'),

            // 如果最近一次上传有错误，在题目下方显示红色提示
            if (draft.mediaError != null) ...[
              const SizedBox(height: 8),
              Text(
                draft.mediaError!,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                ),
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('问卷填写'),
        ),
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
        appBar: AppBar(
          title: const Text('问卷填写'),
        ),
        body: const Center(
          child: Text('问卷数据为空'),
        ),
      );
    }

    final theme = Theme.of(context);

    // 只统计“可见”的题目
    final visibleQuestions =
        q.questions.where(_isQuestionVisible).toList();
    final total = visibleQuestions.length;

    int answeredCount = 0;
    for (final qu in visibleQuestions) {
      final d = _answers[qu.id];
      if (d != null && _hasAnswer(qu, d)) {
        answeredCount++;
      }
    }

    final progressValue =
        total == 0 ? 0.0 : answeredCount / total;

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

    return Scaffold(
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
                  color:
                      theme.colorScheme.onPrimary.withOpacity(0.8),
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
              // 顶部进度条
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: progressValue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('$answeredCount/$total'),
                ],
              ),
              const SizedBox(height: 16),

              // 题目列表
              Expanded(
                child: ListView.separated(
                  itemCount: visibleQuestions.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final qu = visibleQuestions[index];
                    final draft =
                        _answers[qu.id] ?? AnswerDraft(questionId: qu.id);

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
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
                                    style: theme
                                        .textTheme.titleMedium,
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

              if (_isReadOnly)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '当前状态：已提交（仅供查看）',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            (_savingDraft || _hasUploadingMedia) ? null : _saveDraft,
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
                        onPressed:
                            (_submitting || _hasUploadingMedia) ? null : _submit,
                        child: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation(
                                          Colors.white),
                                ),
                              )
                            : const Text('提交问卷'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _submissionStatus == 'draft'
                        ? '当前状态：草稿（尚未提交）'
                        : '当前状态：未保存',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ],
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

  const _InlineVideoPlayer({
    required this.videoUrl,
  });

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
            VideoProgressIndicator(
              _controller,
              allowScrubbing: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// 视频播放页面
class VideoPlayerPage extends StatefulWidget {
  final String videoUrl;

  const VideoPlayerPage({
    super.key,
    required this.videoUrl,
  });

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
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('视频播放'),
      ),
      body: Center(
        child: _initialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    VideoPlayer(_controller),
                    _PlayPauseOverlay(controller: _controller),
                    VideoProgressIndicator(
                      _controller,
                      allowScrubbing: true,
                    ),
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

  const _PlayPauseOverlay({
    required this.controller,
  });

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
          Positioned.fill(
            child: Container(
              color: Colors.black26,
            ),
          ),
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