import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart'; // 视频播放
import 'package:image_gallery_saver/image_gallery_saver.dart'; // 保存到相册
import 'dart:io'; // 用于本地文件
import 'package:path_provider/path_provider.dart'; // 用于获取临时目录

/// =====================
/// 配置区：后端地址
/// =====================
///
// Web / Mac 本机调试时用：
const String baseUrlLocalhost = 'http://127.0.0.1:8000';

// Android 模拟器用（Android 模拟器访问宿主机要用 10.0.2.2）
const String baseUrlAndroidEmu = 'http://10.0.2.2:8000';

// 真机（iOS / Android）用：把 <YOUR_IP> 换成你刚才查到的局域网 IP
const String baseUrlLan = 'http://192.168.3.29:8000';

// // 现在先指定一个实际使用的 baseUrl，比如先用 Android 模拟器：
// const String baseUrl = baseUrlAndroidEmu;

// iOS 模拟器 / Mac 上跑：后端在本机
const String baseUrl = baseUrlLan;

void main() {
  runApp(const MyApp());
}

/// 整个 App 根组件
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '调研 App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const LoginPage(),
    );
  }
}

/// =====================
/// API Service 封装
/// =====================

class ApiService {
  final String username;
  final String password;

  ApiService({
    required this.username,
    required this.password,
  });

  /// 生成带 Basic Auth 的 header
  /// json=true 时加上 Content-Type: application/json
  Map<String, String> _authHeaders({bool json = true}) {
    final authStr = '$username:$password';
    final bytes = utf8.encode(authStr);
    final base64Str = base64Encode(bytes);
    final headers = <String, String>{
      'Authorization': 'Basic $base64Str',
    };
    if (json) {
      headers['Content-Type'] = 'application/json';
    }
    return headers;
  }

  /// 登录：调用 /api/accounts/login/
  static Future<LoginResult> login({
    required String username,
    required String password,
  }) async {
    final url = Uri.parse('$baseUrl/api/accounts/login/');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return LoginResult.fromJson(data);
    } else if (response.statusCode == 400) {
      final data = jsonDecode(response.body);
      throw ApiException(
        message: data.toString(),
        statusCode: response.statusCode,
      );
    } else {
      throw ApiException(
        message: '登录失败：HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
  }

  /// 获取当前评估员的任务列表
  Future<List<Assignment>> getMyAssignments() async {
    final url = Uri.parse('$baseUrl/api/assignments/my-assignments/');

    final response = await http.get(
      url,
      headers: _authHeaders(),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is List) {
        return data.map((e) => Assignment.fromJson(e)).toList();
      } else {
        throw ApiException(
          message: '返回数据格式不是列表：$data',
          statusCode: response.statusCode,
        );
      }
    } else if (response.statusCode == 401 || response.statusCode == 403) {
      throw ApiException(
        message: '没有权限访问任务列表（请检查用户名密码或后端权限设置）',
        statusCode: response.statusCode,
      );
    } else {
      throw ApiException(
        message: '获取任务列表失败：HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
  }

  /// 拉取问卷结构：/api/survey/questionnaires/{id}/
  Future<QuestionnaireDto> fetchQuestionnaire(int questionnaireId) async {
    final url =
        Uri.parse('$baseUrl/api/survey/questionnaires/$questionnaireId/');

    final response = await http.get(
      url,
      headers: _authHeaders(),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return QuestionnaireDto.fromJson(data);
    } else if (response.statusCode == 404) {
      throw ApiException(
        message: '问卷不存在 (id=$questionnaireId)',
        statusCode: response.statusCode,
      );
    } else {
      throw ApiException(
        message: '获取问卷失败：HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
  }

  /// 获取当前评估员在某个任务下最近一次提交（如果有）
  Future<SubmissionDto?> fetchLatestSubmissionForAssignment(
      int assignmentId) async {
    final url = Uri.parse(
        '$baseUrl/api/assignments/submissions/?assignment=$assignmentId');

    final response = await http.get(
      url,
      headers: _authHeaders(),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is List && data.isNotEmpty) {
        // 后端已按 id 倒序，第一条就是最新一条
        final first = data[0] as Map<String, dynamic>;
        return SubmissionDto.fromJson(first);
      }
      return null; // 这个任务还没有任何提交记录
    } else {
      throw ApiException(
        message:
            '获取提交记录失败：HTTP ${response.statusCode}，body=${response.body}',
        statusCode: response.statusCode,
      );
    }
  }

  /// 保存提交（草稿或提交前的保存）
  ///
  /// - submissionId 为空：POST 创建
  /// - submissionId 不为空：PUT 更新
  ///
  /// 返回：submission 的 id
  Future<int> saveSubmission({
    int? submissionId,
    required int assignmentId,
    required String status, // "draft" 或 "submitted"
    required List<AnswerDraft> answers,
  }) async {
    final url = submissionId == null
        ? Uri.parse('$baseUrl/api/assignments/submissions/')
        : Uri.parse('$baseUrl/api/assignments/submissions/$submissionId/');

    final payload = {
      'assignment': assignmentId,
      'status': status,
      'answers': answers
          .map((a) => {
                'question': a.questionId,
                'text_value': a.textValue,
                'number_value': a.numberValue,
                'selected_option_ids': a.selectedOptionIds,
                'media_file_ids': a.mediaFileIds,
              })
          .toList(),
    };

    final response = await (submissionId == null
        ? http.post(
            url,
            headers: _authHeaders(),
            body: jsonEncode(payload),
          )
        : http.put(
            url,
            headers: _authHeaders(),
            body: jsonEncode(payload),
          ));

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final id = data['id'] as int?;
      if (id == null) {
        throw ApiException(
          message: '保存提交成功，但返回数据中没有 id：$data',
          statusCode: response.statusCode,
        );
      }
      return id;
    } else {
      throw ApiException(
        message:
            '保存提交失败：HTTP ${response.statusCode}，body=${response.body}',
        statusCode: response.statusCode,
      );
    }
  }

  /// 提交审核：/api/assignments/submissions/{id}/submit/
  Future<void> submitSubmission(int submissionId) async {
    final url = Uri.parse(
        '$baseUrl/api/assignments/submissions/$submissionId/submit/');

    final response = await http.post(
      url,
      headers: _authHeaders(),
    );

    if (response.statusCode != 200) {
      throw ApiException(
        message:
            '提交审核失败：HTTP ${response.statusCode}，body=${response.body}',
        statusCode: response.statusCode,
      );
    }
  }

  /// 上传媒体文件到 /api/assignments/upload-media/
  ///
  /// - mediaType: "image" or "video"
  /// - questionId: 题目 ID（后端用来关联合理）
  ///
  /// 返回：后端创建的 MediaFile.id
  Future<int> uploadMediaFile({
    required int questionId,
    required String mediaType,
    required XFile file,
  }) async {
    final url = Uri.parse('$baseUrl/api/assignments/upload-media/');

    final request = http.MultipartRequest('POST', url);

    // 只加 Authorization，不要加 Content-Type（由 MultipartRequest 自己处理）
    final authHeaders = _authHeaders(json: false);
    request.headers.addAll(authHeaders);

    request.fields['media_type'] = mediaType;
    request.fields['question'] = questionId.toString();

    final bytes = await file.readAsBytes();

    // 生成一个比较短、后端能接受的文件名（带上题目 ID 和时间戳）
    String originalName = file.name;
    String ext = '';
    if (originalName.contains('.')) {
      ext = originalName.split('.').last;
    }

    // 比如：q12_1700000000000.mp4
    String baseName = 'q${questionId}_${DateTime.now().millisecondsSinceEpoch}';
    String safeName = ext.isNotEmpty ? '$baseName.$ext' : baseName;

    // 再保险一点，如果还是超过 100，就截断到 100
    if (safeName.length > 100) {
      safeName = safeName.substring(0, 100);
    }

    final multipartFile = http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: safeName,
    );
    request.files.add(multipartFile);

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final id = data['id'] as int?;
      if (id == null) {
        throw ApiException(
          message: '上传成功但返回中没有 id：$data',
          statusCode: response.statusCode,
        );
      }
      return id;
    } else {
      throw ApiException(
        message:
            '上传媒体失败：HTTP ${response.statusCode}，body=${response.body}',
        statusCode: response.statusCode,
      );
    }
  }

  /// 根据一组媒体 ID 获取详细信息（file_url / media_type）
  Future<List<MediaFileDto>> fetchMediaFilesByIds(List<int> ids) async {
    if (ids.isEmpty) {
      return [];
    }

    final idsParam = ids.join(',');
    final url =
        Uri.parse('$baseUrl/api/assignments/media-files/?ids=$idsParam');

    final response = await http.get(
      url,
      headers: _authHeaders(),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is List) {
        return data
            .map((e) => MediaFileDto.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        throw ApiException(
          message: '媒体文件返回数据格式不是列表：$data',
          statusCode: response.statusCode,
        );
      }
    } else {
      throw ApiException(
        message:
            '获取媒体文件失败：HTTP ${response.statusCode}，body=${response.body}',
        statusCode: response.statusCode,
      );
    }
  }
}

/// 登录成功返回的数据结构
class LoginResult {
  final int id;
  final String username;
  final String role;

  LoginResult({
    required this.id,
    required this.username,
    required this.role,
  });

  factory LoginResult.fromJson(Map<String, dynamic> json) {
    return LoginResult(
      id: json['id'] as int,
      username: json['username'] as String,
      role: json['role'] as String? ?? '',
    );
  }
}

/// 任务列表的模型
class Assignment {
  final int id;
  final String clientName;
  final int projectId;
  final String projectName;
  final int questionnaireId;
  final String questionnaireTitle;
  final String status;
  final String? deadline;
  final String createdAt;

  Assignment({
    required this.id,
    required this.clientName,
    required this.projectId,
    required this.projectName,
    required this.questionnaireId,
    required this.questionnaireTitle,
    required this.status,
    required this.createdAt,
    this.deadline,
  });

  factory Assignment.fromJson(Map<String, dynamic> json) {
    return Assignment(
      id: json['id'] as int,
      clientName: json['client_name'] as String? ?? '',
      projectId: json['project'] as int,
      projectName: json['project_name'] as String? ?? '',
      questionnaireId: json['questionnaire'] as int,
      questionnaireTitle: json['questionnaire_title'] as String? ?? '',
      status: json['status'] as String? ?? '',
      deadline: json['deadline'] as String?,
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

/// 问卷 DTO
class QuestionnaireDto {
  final int id;
  final String title;
  final String? description;
  final int projectId;
  final List<QuestionDto> questions;

  QuestionnaireDto({
    required this.id,
    required this.title,
    required this.description,
    required this.projectId,
    required this.questions,
  });

  factory QuestionnaireDto.fromJson(Map<String, dynamic> json) {
    final questionsJson = json['questions'] as List<dynamic>? ?? [];
    final questions =
        questionsJson.map((e) => QuestionDto.fromJson(e)).toList();

    return QuestionnaireDto(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      projectId: json['project'] as int? ?? 0,
      questions: questions,
    );
  }
}

/// 题目跳转逻辑 DTO
/// 对应后端 question.outgoing_logics 里的每一条记录
class QuestionLogicDto {
  final int id;
  final int fromQuestionId;
  final int triggerOptionId;
  final int? gotoQuestionId;
  final bool gotoEnd;

  QuestionLogicDto({
    required this.id,
    required this.fromQuestionId,
    required this.triggerOptionId,
    required this.gotoQuestionId,
    required this.gotoEnd,
  });

  factory QuestionLogicDto.fromJson(Map<String, dynamic> json) {
    return QuestionLogicDto(
      id: json['id'] as int,
      fromQuestionId: json['from_question'] as int,
      triggerOptionId: json['trigger_option'] as int,
      gotoQuestionId: json['goto_question'] as int?,
      gotoEnd: json['goto_end'] as bool? ?? false,
    );
  }
}

/// 题目 DTO
class QuestionDto {
  final int id;
  final String text;
  final String type; // single / multi / image / video / text / number
  final bool required; // 是否必答
  final List<OptionDto> options;
  final List<QuestionLogicDto> outgoingLogics;

  QuestionDto({
    required this.id,
    required this.text,
    required this.type,
    required this.required,
    required this.options,
    required this.outgoingLogics,
  });

  factory QuestionDto.fromJson(Map<String, dynamic> json) {
    final optionsJson = json['options'] as List<dynamic>? ?? [];
    final options =
        optionsJson.map((e) => OptionDto.fromJson(e)).toList();

    final logicsJson = json['outgoing_logics'] as List<dynamic>? ?? [];
    final logics =
        logicsJson.map((e) => QuestionLogicDto.fromJson(e)).toList();

    return QuestionDto(
      id: json['id'] as int,
      text: json['text'] as String? ?? '',
      type: json['type'] as String? ?? '',
      required: json['required'] as bool? ?? false,
      options: options,
      outgoingLogics: logics,
    );
  }
}

/// 选项 DTO
class OptionDto {
  final int id;
  final String text;
  final String value;
  final int order;

  OptionDto({
    required this.id,
    required this.text,
    required this.value,
    required this.order,
  });

  factory OptionDto.fromJson(Map<String, dynamic> json) {
    return OptionDto(
      id: json['id'] as int,
      text: json['text'] as String? ?? '',
      value: json['value'] as String? ?? '',
      order: json['order'] as int? ?? 0,
    );
  }
}

class AnswerDto {
  final int questionId;
  final String? textValue;
  final double? numberValue;
  final List<int> selectedOptionIds;
  final List<int> mediaFileIds;

  AnswerDto({
    required this.questionId,
    this.textValue,
    this.numberValue,
    required this.selectedOptionIds,
    required this.mediaFileIds,
  });

  factory AnswerDto.fromJson(Map<String, dynamic> json) {
    final selectedIdsJson =
        json['selected_option_ids'] as List<dynamic>? ?? [];
    final mediaIdsJson =
        json['media_file_ids'] as List<dynamic>? ?? [];

    return AnswerDto(
      questionId: json['question'] as int,
      textValue: json['text_value'] as String?,
      numberValue: (json['number_value'] != null)
          ? double.tryParse(json['number_value'].toString())
          : null,
      selectedOptionIds:
          selectedIdsJson.map((e) => e as int).toList(),
      mediaFileIds:
          mediaIdsJson.map((e) => e as int).toList(),
    );
  }
}

class SubmissionDto {
  final int id;
  final int assignmentId;
  final String status;
  final int? version;
  final String? submittedAt;
  final List<AnswerDto> answers;

  SubmissionDto({
    required this.id,
    required this.assignmentId,
    required this.status,
    this.version,
    this.submittedAt,
    required this.answers,
  });

  factory SubmissionDto.fromJson(Map<String, dynamic> json) {
    final answersJson = json['answers'] as List<dynamic>? ?? [];
    final answers =
        answersJson.map((e) => AnswerDto.fromJson(e)).toList();

    return SubmissionDto(
      id: json['id'] as int,
      assignmentId: json['assignment'] as int,
      status: json['status'] as String? ?? '',
      version: json['version'] as int?,
      submittedAt: json['submitted_at'] as String?,
      answers: answers,
    );
  }
}

class MediaFileDto {
  final int id;
  final String fileUrl;
  final String mediaType;

  MediaFileDto({
    required this.id,
    required this.fileUrl,
    required this.mediaType,
  });

  factory MediaFileDto.fromJson(Map<String, dynamic> json) {
    return MediaFileDto(
      id: json['id'] as int,
      fileUrl: json['file_url'] as String? ?? '',
      mediaType: json['media_type'] as String? ?? '',
    );
  }
}

/// 本地“答案草稿”模型
class AnswerDraft {
  final int questionId;
  String? textValue;
  double? numberValue;
  List<int> selectedOptionIds;
  List<int> mediaFileIds; // 存放上传后返回的 media id

  /// 该题是否正在上传媒体（用于每题单独的 loading）
  bool isUploadingMedia;

  AnswerDraft({
    required this.questionId,
    this.textValue,
    this.numberValue,
    List<int>? selectedOptionIds,
    List<int>? mediaFileIds,
    this.isUploadingMedia = false,
  })  : selectedOptionIds = selectedOptionIds ?? [],
        mediaFileIds = mediaFileIds ?? [];
}

/// 通用 API 异常
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException({required this.message, this.statusCode});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// =====================
/// 登录页面
/// =====================

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _usernameController =
      TextEditingController(text: 'rhu');
  final TextEditingController _passwordController =
      TextEditingController(text: '123456');

  bool _isLoading = false;
  String? _error;

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result =
          await ApiService.login(username: username, password: password);

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AssignmentsPage(
            loginResult: result,
            username: username,
            password: password,
          ),
        ),
      );
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _error = '未知错误：$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录 - 调研 App'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: '用户名',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return '请输入用户名';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        decoration: const InputDecoration(
                          labelText: '密码',
                        ),
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return '请输入密码';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('登录'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 把后端的状态英文码映射成前端展示用的中文文案
String statusLabel(String status) {
  switch (status) {
    case 'pending':
      return '未开始';
    case 'draft':
      return '草稿';
    case 'submitted':
      return '已提交';
    case 'reviewed':
      return '已审核';
    default:
      return status; // 未知状态就先直接展示原值
  }
}

/// =====================
/// 任务列表页面
/// =====================

class AssignmentsPage extends StatefulWidget {
  final LoginResult loginResult;
  final String username;
  final String password;

  const AssignmentsPage({
    super.key,
    required this.loginResult,
    required this.username,
    required this.password,
  });

  @override
  State<AssignmentsPage> createState() => _AssignmentsPageState();
}

class _AssignmentsPageState extends State<AssignmentsPage> {
  late final ApiService _apiService;
  late Future<List<Assignment>> _futureAssignments;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService(
      username: widget.username,
      password: widget.password,
    );
    _futureAssignments = _apiService.getMyAssignments();
  }

  Future<void> _reload() async {
    setState(() {
      _futureAssignments = _apiService.getMyAssignments();
    });
  }

  /// 已提交 / 已审核 的任务被点击时的提示
  Future<void> _showReadonlyDialog(String status) async {
    String msg;
    if (status == 'submitted') {
      msg = '该任务已提交审核，不能再修改。';
    } else {
      msg = '该任务已审核完成，不能再修改。';
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('无法编辑'),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('我的任务 - ${widget.loginResult.username}'),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<Assignment>>(
        future: _futureAssignments,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            final err = snapshot.error;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  '加载任务失败：$err',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            );
          }

          final assignments = snapshot.data ?? [];

          if (assignments.isEmpty) {
            return const Center(
              child: Text('当前没有任务'),
            );
          }

          return ListView.builder(
            itemCount: assignments.length,
            itemBuilder: (context, index) {
              final a = assignments[index];
              final statusText = statusLabel(a.status);

              return Card(
                margin:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  title: Text('${a.clientName} - ${a.projectName}'),
                  subtitle: Text(
                    '${a.questionnaireTitle}\n状态：$statusText\n创建时间：${a.createdAt}',
                  ),
                  isThreeLine: true,
                  onTap: () async {
                    // 已提交 / 已审核 不允许再进入编辑
                    if (a.status == 'submitted' || a.status == 'reviewed') {
                      await _showReadonlyDialog(a.status);
                      return;
                    }

                    // 可编辑状态：pending / draft 等
                    final needRefresh = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => QuestionnairePage(
                          assignment: a,
                          username: widget.username,
                          password: widget.password,
                        ),
                      ),
                    );

                    if (needRefresh == true) {
                      _reload();
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// =====================
/// 问卷详情 + 作答页面（含历史答案回显）
/// =====================

class QuestionnairePage extends StatefulWidget {
  final Assignment assignment;
  final String username;
  final String password;

  const QuestionnairePage({
    super.key,
    required this.assignment,
    required this.username,
    required this.password,
  });

  @override
  State<QuestionnairePage> createState() => _QuestionnairePageState();
}

class _QuestionnairePageState extends State<QuestionnairePage> {
  late final ApiService _apiService;
  late Future<QuestionnaireDto> _futureQuestionnaire;

  /// 当前问卷对象（用于跳题计算等）
  QuestionnaireDto? _questionnaire;

  /// 当前可见的题目列表（默认是问卷的全部题目）
  List<QuestionDto> _visibleQuestions = [];

  /// questionId -> 在原始 questions 列表中的索引（后面可能还会用到）
  final Map<int, int> _questionIndexById = {};

  /// questionId -> AnswerDraft
  final Map<int, AnswerDraft> _answers = {};

  /// questionId -> 指向它的逻辑列表（例如：Q4 会被 Q1 的逻辑指向）
  final Map<int, List<QuestionLogicDto>> _incomingLogics = {};

  int? _submissionId;
  bool _isSaving = false;
  bool _isSubmitting = false;
  String? _error;

  final ImagePicker _picker = ImagePicker();

  /// 控制图片/视频选择器的忙碌状态（防止 already_active）
  bool _isPickingMedia = false;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService(
      username: widget.username,
      password: widget.password,
    );
    // 👉 初始化时：同时拉问卷 + 最近一次提交，并把答案填进 _answers
    _futureQuestionnaire = _loadQuestionnaireAndSubmission();
  }

  /// 根据题目对象获取/创建本地草稿
  AnswerDraft _getDraftForQuestion(QuestionDto q) {
    return _answers.putIfAbsent(
      q.id,
      () => AnswerDraft(questionId: q.id),
    );
  }

  /// 在一个问卷对象里，根据 questionId 找到对应 QuestionDto
  QuestionDto? _findQuestionById(QuestionnaireDto questionnaire, int qid) {
    for (final q in questionnaire.questions) {
      if (q.id == qid) return q;
    }
    return null;
  }

  /// 根据当前答案情况，重新计算哪些题目是可见的（条件显示）
  ///
  /// 规则：
  /// - 没有任何逻辑指向的题目：永远可见（例如普通题 Q1、Q2、Q3）
  /// - 有逻辑指向的题目（如 Q4）：
  ///     只要有一条逻辑的条件被满足（来源题的答案包含对应 trigger_option），就显示；
  ///     否则隐藏，并清理它的答案草稿。
  void _recalculateVisibleQuestions() {
    final questionnaire = _questionnaire;
    if (questionnaire == null) return;

    final List<QuestionDto> result = [];

    for (final q in questionnaire.questions) {
      // 找到所有 “跳到当前题目” 的逻辑
      final incoming = _incomingLogics[q.id];

      // 如果没有任何逻辑指向这个题目 -> 永远显示
      if (incoming == null || incoming.isEmpty) {
        result.add(q);
        continue;
      }

      bool shouldShow = false;

      // 只要有一条逻辑条件满足，就显示
      for (final logic in incoming) {
        // 找到逻辑来源题目的草稿答案
        final draft = _answers[logic.fromQuestionId];
        if (draft == null) continue;

        // 当前题只要命中了任意一条逻辑的 trigger_option，就显示
        if (draft.selectedOptionIds.contains(logic.triggerOptionId)) {
          shouldShow = true;
          break;
        }
      }

      if (shouldShow) {
        result.add(q);
      }
    }

    // 计算可见题目 ID 集合，清理被隐藏题目的答案，避免误提交
    final visibleIds = result.map((e) => e.id).toSet();
    _answers.removeWhere((questionId, _) => !visibleIds.contains(questionId));

    setState(() {
      _visibleQuestions = result;
    });
  }

  /// 拉取问卷 + 最近一次提交，并填充本地答案草稿 + 初始化跳题结构
  Future<QuestionnaireDto> _loadQuestionnaireAndSubmission() async {
    // 1. 先拉问卷结构
    final questionnaire =
        await _apiService.fetchQuestionnaire(widget.assignment.questionnaireId);

    // 初始化全局问卷引用和题目索引
    _questionnaire = questionnaire;

    _questionIndexById.clear();
    for (var i = 0; i < questionnaire.questions.length; i++) {
      _questionIndexById[questionnaire.questions[i].id] = i;
    }

    // 👉 构建 “指向某题目” 的逻辑表：questionId -> [logics]
    _incomingLogics.clear();
    for (final q in questionnaire.questions) {
      for (final logic in q.outgoingLogics) {
        final gotoId = logic.gotoQuestionId;
        if (gotoId != null) {
          _incomingLogics
              .putIfAbsent(gotoId, () => <QuestionLogicDto>[])
              .add(logic);
        }
      }
    }

    // 初始可见题目：先全部题目（后面会根据历史答案再算一遍）
    _visibleQuestions = List<QuestionDto>.from(questionnaire.questions);

    // 2. 再拉“当前任务最近一次提交”（如果有）
    SubmissionDto? submission;
    try {
      submission = await _apiService
          .fetchLatestSubmissionForAssignment(widget.assignment.id);
    } on ApiException catch (e) {
      debugPrint('获取历史提交失败: $e');
      submission = null;
    }

    if (submission != null) {
      _submissionId = submission.id;

      // 用 submission.answers 回填 _answers
      for (final ans in submission.answers) {
        final q = questionnaire.questions.firstWhere(
          (qq) => qq.id == ans.questionId,
          orElse: () => QuestionDto(
            id: -1,
            text: '',
            type: 'text',
            required: false,
            options: const [],
            outgoingLogics: const [],
          ),
        );

        if (q.id == -1) continue;

        final draft = _answers.putIfAbsent(
          q.id,
          () => AnswerDraft(questionId: q.id),
        );
        draft.textValue = ans.textValue;
        draft.numberValue = ans.numberValue;
        draft.selectedOptionIds = List<int>.from(ans.selectedOptionIds);
        draft.mediaFileIds = List<int>.from(ans.mediaFileIds);
      }

      // 回填完答案后，根据当前答案计算一次可见题目（防止历史答案已经触发逻辑）
      _recalculateVisibleQuestions();
    }

    return questionnaire;
  }

  Future<void> _handleSaveDraft() async {
    final questionnaire = await _futureQuestionnaire;
    final answers =
        questionnaire.questions.map((q) => _getDraftForQuestion(q)).toList();

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final newId = await _apiService.saveSubmission(
        submissionId: _submissionId,
        assignmentId: widget.assignment.id,
        status: 'draft',
        answers: answers,
      );
      setState(() {
        _submissionId = newId;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('草稿已保存')),
      );
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _error = '保存草稿时出错：$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

    /// 提交前做必答题校验
  ///
  /// 只校验当前“可见”的题目：
  /// - 如果有跳题逻辑生效，_visibleQuestions 里就是过滤后的题目
  /// - 如果还没计算可见题目（例如没有跳题），则退回到全部题目
  bool _validateBeforeSubmit(QuestionnaireDto questionnaire) {
    final missingQuestions = <String>[];

    // 优先用当前可见题目列表；如果为空，说明还没经过可见性计算，就用全部题目
    final questionsToCheck =
        _visibleQuestions.isNotEmpty ? _visibleQuestions : questionnaire.questions;

    for (final q in questionsToCheck) {
      if (!q.required) continue;

      final draft = _getDraftForQuestion(q);
      bool ok = false;

      switch (q.type) {
        case 'text':
          ok = draft.textValue != null && draft.textValue!.trim().isNotEmpty;
          break;
        case 'number':
          ok = draft.numberValue != null;
          break;
        case 'single':
          ok = draft.selectedOptionIds.isNotEmpty;
          break;
        case 'multi':
          ok = draft.selectedOptionIds.isNotEmpty;
          break;
        case 'image':
        case 'video':
          ok = draft.mediaFileIds.isNotEmpty;
          break;
        default:
          ok = true;
      }

      if (!ok) {
        missingQuestions.add('「${q.text}」');
      }
    }

    if (missingQuestions.isNotEmpty) {
      final msg = '以下必答题尚未填写：\n${missingQuestions.join('，')}';

      setState(() {
        _error = msg;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      return false;
    }

    return true;
  }

  Future<void> _handleSubmit() async {
    final questionnaire = await _futureQuestionnaire;

    // 先做必答题校验
    if (!_validateBeforeSubmit(questionnaire)) {
      return;
    }

    final answers =
        questionnaire.questions.map((q) => _getDraftForQuestion(q)).toList();

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      // 1）先保存一次，状态设为 submitted
      final newId = await _apiService.saveSubmission(
        submissionId: _submissionId,
        assignmentId: widget.assignment.id,
        status: 'submitted',
        answers: answers,
      );
      _submissionId = newId;

      // 2）再调用 /submit/ 接口
      await _apiService.submitSubmission(newId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已提交审核')),
      );

      // 带 true 返回，通知上一页刷新列表
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _error = '提交时出错：$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  /// 让用户选择图片/视频来源：相机 或 相册
  Future<ImageSource?> _chooseMediaSource() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('使用相机拍摄'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('从相册选择'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );
  }

    /// 处理图片 / 视频上传（含：
  /// - 防止 already_active（一次只允许一个 picker）
  /// - 选择相机 / 相册
  /// - 每题单独的上传进度
  Future<void> _handlePickAndUploadMedia(
      QuestionDto question, String mediaType) async {
    // 如果正在选择，直接提示，防止重复触发
    if (_isPickingMedia) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在处理文件，请稍候…')),
      );
      return;
    }

    _isPickingMedia = true;

    try {
      // 1）先让用户选择来源（相机 / 相册）
      final source = await _chooseMediaSource();
      if (source == null) {
        // 用户取消
        return;
      }

      XFile? file;

      if (mediaType == 'image') {
        file = await _picker.pickImage(source: source);
      } else {
        file = await _picker.pickVideo(source: source);
      }

      if (file == null) {
        // 用户在系统选择器里取消，或者权限被拒绝 / 录制失败
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未获取到视频文件（可能是权限被拒绝或录制被取消）')),
        );
        return;
      }

      // 2）开始上传，标记当前题正在上传
      final draft = _getDraftForQuestion(question);
      setState(() {
        draft.isUploadingMedia = true;
        _error = null;
      });

      final mediaId = await _apiService.uploadMediaFile(
        questionId: question.id,
        mediaType: mediaType,
        file: file,
      );

      setState(() {
        draft.mediaFileIds.add(mediaId);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件上传成功')),
      );
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _error = '上传文件时出错：$e';
      });
    } finally {
      // 无论成功失败，都要恢复状态
      _isPickingMedia = false;
      if (mounted) {
        setState(() {
          _getDraftForQuestion(question).isUploadingMedia = false;
        });
      } else {
        _getDraftForQuestion(question).isUploadingMedia = false;
      }
    }
  }


  /// 把后端返回的 fileUrl 变成当前环境下可访问的完整 URL
  /// 处理几种情况：
  /// 1）相对路径：/media/xx -> 拼到 baseUrl 后面
  /// 2）host 是 127.0.0.1 / localhost：替换成当前 baseUrl 的 host + 端口（比如 10.0.2.2:8000）
  String _normalizeFileUrl(String rawUrl) {
    if (rawUrl.isEmpty) return rawUrl;

    // 先解析当前 baseUrl，方便拿到 host / port
    final baseUri = Uri.parse(baseUrl);

    // 1）相对路径：/media/xxx
    if (!rawUrl.startsWith('http')) {
      if (rawUrl.startsWith('/')) {
        return '${baseUri.scheme}://${baseUri.host}:${baseUri.port}$rawUrl';
      } else {
        return '${baseUri.scheme}://${baseUri.host}:${baseUri.port}/$rawUrl';
      }
    }

    // 2）绝对路径，但 host 是 127.0.0.1 / localhost，需要替换成 baseUrl 对应的 host
    final uri = Uri.parse(rawUrl);
    if (uri.host == '127.0.0.1' || uri.host == 'localhost') {
      final fixed = uri.replace(
        scheme: baseUri.scheme,
        host: baseUri.host,
        port: baseUri.port,
      );
      return fixed.toString();
    }

    // 其他情况直接用原来的
    return rawUrl;
  }

  /// 从某道题里移除一个已上传的媒体（只是在当前答案中移除，不会删服务器文件）
  void _handleRemoveMedia(QuestionDto question, int mediaId) {
    final draft = _getDraftForQuestion(question);
    setState(() {
      draft.mediaFileIds.remove(mediaId);
    });
  }

  /// 每题的已上传媒体列表（带缩略图 / 预览 / 删除）
  Widget _buildMediaPreviewList(QuestionDto question, List<int> mediaIds) {
    if (mediaIds.isEmpty) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<List<MediaFileDto>>(
      future: _apiService.fetchMediaFilesByIds(mediaIds),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 4.0),
            child: LinearProgressIndicator(),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              '加载已上传文件失败：${snapshot.error}',
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          );
        }

        final files = snapshot.data ?? [];
        if (files.isEmpty) {
          return const SizedBox.shrink();
        }

        // 当前题目下所有图片的 URL（用于左右滑）
        final imageFiles = files.where((f) => f.mediaType == 'image').toList();
        final imageUrls = imageFiles
            .map((f) => _normalizeFileUrl(f.fileUrl))
            .toList(growable: false);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: files.map((f) {
            final isImage = f.mediaType == 'image';

            // 统一修正一下 URL
            final fixedUrl = _normalizeFileUrl(f.fileUrl);

            // 如果是图片，找一下它在 imageUrls 里的 index，用于预览页初始页
            int initialIndex = 0;
            if (isImage) {
              final idx = imageFiles.indexWhere((img) => img.id == f.id);
              if (idx >= 0) {
                initialIndex = idx;
              }
            }

            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: isImage
                  ? GestureDetector(
                      onTap: () {
                        // 👉 点击缩略图：App 内全屏图片预览 + 左右滑
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ImagePreviewPage(
                              imageUrls: imageUrls,
                              initialIndex: initialIndex,
                            ),
                          ),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(
                          fixedUrl,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                  : GestureDetector(
                      onTap: () {
                        // 👉 点击视频图标：App 内全屏视频播放
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VideoPreviewPage(
                              videoUrl: fixedUrl,
                            ),
                          ),
                        );
                      },
                      child: const Icon(Icons.videocam, size: 28),
                    ),
              title: Text(
                '文件 #${f.id}',
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                fixedUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    // 👉 这里保留原有行为：浏览器打开
                    onPressed: () async {
                      final uri = Uri.parse(fixedUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      } else {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('无法打开链接')),
                        );
                      }
                    },
                    child: Text(isImage ? '在浏览器中查看图片' : '在浏览器中查看视频'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: '从本题中删除',
                    onPressed: () => _handleRemoveMedia(question, f.id),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildQuestionWidget(QuestionDto q) {
    final draft = _getDraftForQuestion(q);

    Widget child;

    switch (q.type) {
      case 'text':
        child = TextField(
          decoration: const InputDecoration(
            hintText: '请输入文本答案',
            border: OutlineInputBorder(),
          ),
          maxLines: null,
          onChanged: (value) {
            draft.textValue = value;
          },
        );
        break;
      case 'number':
        child = TextField(
          decoration: const InputDecoration(
            hintText: '请输入数字答案',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          onChanged: (value) {
            if (value.trim().isEmpty) {
              draft.numberValue = null;
            } else {
              final parsed = double.tryParse(value);
              draft.numberValue = parsed;
            }
          },
        );
        break;
      case 'single':
        int? selectedId = draft.selectedOptionIds.isNotEmpty
            ? draft.selectedOptionIds.first
            : null;
        child = Column(
          children: q.options
              .map(
                (opt) => RadioListTile<int>(
                  title: Text(opt.text),
                  value: opt.id,
                  groupValue: selectedId,
                  onChanged: (value) {
                    if (value == null) return;
                    // 更新答案 + 重新计算可见题目
                    draft.selectedOptionIds = [value];
                    _recalculateVisibleQuestions();
                  },
                ),
              )
              .toList(),
        );
        break;
      case 'multi':
        child = Column(
          children: q.options
              .map(
                (opt) => CheckboxListTile(
                  title: Text(opt.text),
                  value: draft.selectedOptionIds.contains(opt.id),
                  onChanged: (checked) {
                    // 更新答案列表
                    if (checked == true) {
                      if (!draft.selectedOptionIds.contains(opt.id)) {
                        draft.selectedOptionIds.add(opt.id);
                      }
                    } else {
                      draft.selectedOptionIds.remove(opt.id);
                    }
                    // 选项变化后，重新计算可见题目
                    _recalculateVisibleQuestions();
                  },
                ),
              )
              .toList(),
        );
        break;
      case 'image':
        child = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton.icon(
              onPressed: (_isPickingMedia || draft.isUploadingMedia)
                  ? null
                  : () => _handlePickAndUploadMedia(q, 'image'),
              icon: const Icon(Icons.photo),
              label: const Text('选择图片并上传'),
            ),
            const SizedBox(height: 8),
            Text('已上传文件数量：${draft.mediaFileIds.length}'),
            const SizedBox(height: 4),
            if (draft.isUploadingMedia)
              const Padding(
                padding: EdgeInsets.only(bottom: 4.0),
                child: LinearProgressIndicator(),
              ),
            _buildMediaPreviewList(q, draft.mediaFileIds),
          ],
        );
        break;
      case 'video':
        child = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton.icon(
              onPressed: (_isPickingMedia || draft.isUploadingMedia)
                  ? null
                  : () => _handlePickAndUploadMedia(q, 'video'),
              icon: const Icon(Icons.videocam),
              label: const Text('选择视频并上传'),
            ),
            const SizedBox(height: 8),
            Text('已上传文件数量：${draft.mediaFileIds.length}'),
            const SizedBox(height: 4),
            if (draft.isUploadingMedia)
              const Padding(
                padding: EdgeInsets.only(bottom: 4.0),
                child: LinearProgressIndicator(),
              ),
            _buildMediaPreviewList(q, draft.mediaFileIds),
          ],
        );
        break;
      default:
        child = const Text('暂不支持的题型');
    }

    final titleSuffix = q.required ? ' *' : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Q${q.id}. ${q.text}$titleSuffix',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('问卷详情 - ${widget.assignment.questionnaireTitle}'),
      ),
      body: FutureBuilder<QuestionnaireDto>(
        future: _futureQuestionnaire,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            final err = snapshot.error;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  '加载问卷失败：$err',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            );
          }

          final questionnaire = snapshot.data!;

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16.0),
                  children: [
                    Text(
                      questionnaire.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (questionnaire.description != null &&
                        questionnaire.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(
                            top: 8.0, bottom: 16.0),
                        child: Text(
                          questionnaire.description!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    const Divider(),
                    ...(_visibleQuestions.isNotEmpty
                            ? _visibleQuestions
                            : questionnaire.questions)
                        .map(_buildQuestionWidget),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 4.0),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSaving ? null : _handleSaveDraft,
                        child: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
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
                        onPressed: _isSubmitting ? null : _handleSubmit,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('提交审核'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}


/// =====================
/// App 内全屏图片预览页（支持左右滑 + 保存到相册）
/// =====================
class ImagePreviewPage extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const ImagePreviewPage({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
  });

  @override
  State<ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<ImagePreviewPage> {
  late PageController _pageController;
  late int _currentIndex;
  bool _isSaving = false;

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

  Future<void> _saveCurrentImage() async {
    if (_isSaving) return;
    final url = widget.imageUrls[_currentIndex];

    setState(() {
      _isSaving = true;
    });

    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final bytes = Uint8List.fromList(resp.bodyBytes);
        await ImageGallerySaver.saveImage(bytes);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('图片已保存到相册')),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载图片失败：HTTP ${resp.statusCode}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存图片出错：$e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.imageUrls.length;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_currentIndex + 1} / $total',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            onPressed: _isSaving ? null : _saveCurrentImage,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download),
            tooltip: '保存到相册',
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (idx) {
          setState(() {
            _currentIndex = idx;
          });
        },
        itemCount: widget.imageUrls.length,
        itemBuilder: (context, index) {
          final url = widget.imageUrls[index];
          return Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Image.network(url),
            ),
          );
        },
      ),
    );
  }
}


/// =====================
/// App 内全屏视频预览页
/// =====================
class VideoPreviewPage extends StatefulWidget {
  final String videoUrl;

  const VideoPreviewPage({
    super.key,
    required this.videoUrl,
  });

  @override
  State<VideoPreviewPage> createState() => _VideoPreviewPageState();
}

class _VideoPreviewPageState extends State<VideoPreviewPage> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isDownloading = true;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _prepareVideo();
  }

  /// 先把远程视频下载到本地临时文件，再用 file 播放
  Future<void> _prepareVideo() async {
    try {
      final uri = Uri.parse(widget.videoUrl);

      // 1）先把整个视频文件下载下来
      final resp = await http.get(uri);
      if (resp.statusCode != 200) {
        setState(() {
          _errorMsg = '下载视频失败：HTTP ${resp.statusCode}';
          _isDownloading = false;
        });
        return;
      }

      final bytes = resp.bodyBytes;

      // 2）保存到临时目录
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/video_${DateTime.now().millisecondsSinceEpoch}.mp4',
      );
      await file.writeAsBytes(bytes);

      // 3）用本地文件初始化 VideoPlayerController
      final ctrl = VideoPlayerController.file(file);
      await ctrl.initialize();

      if (!mounted) return;

      setState(() {
        _controller = ctrl;
        _isInitialized = true;
        _isDownloading = false;
      });

      // 自动播放
      _controller!.play();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = e.toString();
        _isDownloading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white), // 返回按钮变白
        title: const Text(
          '视频预览',
          style: TextStyle(color: Colors.white), // 标题白色
        ),
      ),
      body: _errorMsg != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  '视频加载失败：\n$_errorMsg',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _isDownloading
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text(
                        '正在下载视频，请稍候…',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                )
              : (!_isInitialized || _controller == null)
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        // 上面这块是“可伸缩”的视频区域，自动占满剩余空间
                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: _controller!.value.aspectRatio,
                              child: ClipRect(
                                child: FittedBox(
                                  fit: BoxFit.cover, // 填满，无黑边
                                  child: SizedBox(
                                    width: _controller!.value.size.width,
                                    height: _controller!.value.size.height,
                                    child: VideoPlayer(_controller!),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // 底部控制区，占固定高度，不会再把内容顶出屏幕
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              color: Colors.white,
                              iconSize: 32,
                              icon: Icon(
                                _controller!.value.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                              ),
                              onPressed: () {
                                setState(() {
                                  if (_controller!.value.isPlaying) {
                                    _controller!.pause();
                                  } else {
                                    _controller!.play();
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
    );
  }
}