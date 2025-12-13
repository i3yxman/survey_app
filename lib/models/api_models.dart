// lib/models/api_models.dart

/// 登录成功返回的数据结构
class LoginResult {
  final int id;
  final String username;
  final String role;
  final String status;
  final String? applicationStatus;

  LoginResult({
    required this.id,
    required this.username,
    required this.role,
    required this.status,
    this.applicationStatus,
  });

  factory LoginResult.fromJson(Map<String, dynamic> json) {
    return LoginResult(
      id: json['id'] as int,
      username: json['username'] as String,
      role: json['role'] as String? ?? '',
      status: json['status'] as String? ?? '',
      applicationStatus: json['application_status'] as String?,
    );
  }
}

/// 任务列表的模型
class Assignment {
  final int id;
  final String status;
  final String createdAt;

  final int? jobPosting;

  /// 后端字段叫 project
  final int? project;
  final String? projectName;

  /// 后端字段叫 questionnaire
  final int? questionnaire;
  final String? questionnaireTitle;
  final String? clientName;

  final int? store;
  final int? storeId;
  final String? storeCode;
  final String? storeName;
  final String? storeAddress;
  final String? storeCity;
  final double? storeLatitude;
  final double? storeLongitude;

  Assignment({
    required this.id,
    required this.status,
    required this.createdAt,
    this.jobPosting,

    /// 新写法：同时兼容 project / projectId 两个名字
    int? project,
    int? projectId,
    this.projectName,

    int? questionnaire,
    int? questionnaireId,
    this.questionnaireTitle,
    this.clientName,
    this.store,
    this.storeId,
    this.storeCode,
    this.storeName,
    this.storeAddress,
    this.storeCity,
    this.storeLatitude,
    this.storeLongitude,
  }) : project = project ?? projectId,
       questionnaire = questionnaire ?? questionnaireId;

  factory Assignment.fromJson(Map<String, dynamic> json) {
    double? toDouble(dynamic v) {
      if (v == null) return null;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return Assignment(
      id: json['id'] as int,
      status: json['status'] as String,
      createdAt: json['created_at']?.toString() ?? '',

      jobPosting: json['job_posting'] as int?,

      // 这里仍然用后端原始字段名 project / questionnaire
      project: json['project'] as int?,
      projectName: json['project_name']?.toString(),
      questionnaire: json['questionnaire'] as int?,
      questionnaireTitle: json['questionnaire_title']?.toString(),
      clientName: json['client_name']?.toString(),

      store: json['store'] as int?,
      storeId: json['store_id'] as int?,
      storeCode: json['store_code']?.toString(),
      storeName: json['store_name']?.toString(),
      storeAddress: json['store_address']?.toString(),
      storeCity: json['store_city']?.toString(),
      storeLatitude: toDouble(json['store_latitude']),
      storeLongitude: toDouble(json['store_longitude']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'status': status,
      'created_at': createdAt,
      'job_posting': jobPosting,
      'project': project,
      'project_name': projectName,
      'questionnaire': questionnaire,
      'questionnaire_title': questionnaireTitle,
      'client_name': clientName,
      'store': store,
      'store_id': storeId,
      'store_code': storeCode,
      'store_name': storeName,
      'store_address': storeAddress,
      'store_city': storeCity,
      'store_latitude': storeLatitude,
      'store_longitude': storeLongitude,
    };
  }
}

/// 任务大厅里的“可申请任务”模型
class JobPosting {
  final int id;
  final String title;
  final String description;

  /// JobPosting 本身的状态（open / assigned / closed）
  final String status;

  /// 当前登录用户对这条任务的申请状态（applied / cancelled / approved / null）
  /// 对应后端 serializer 里的 application_status 字段
  final String? applicationStatus;

  final int clientId;
  final String clientName;

  final int projectId;
  final String projectName;

  final int questionnaireId;
  final String questionnaireTitle;

  final int? storeId;
  final String? storeCode;
  final String? storeName;
  final String? storeAddress;
  final String? storeCity;
  final double? storeLatitude;
  final double? storeLongitude;

  final String createdAt;

  JobPosting({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    this.applicationStatus, // ⭐ 不是 required
    required this.clientId,
    required this.clientName,
    required this.projectId,
    required this.projectName,
    required this.questionnaireId,
    required this.questionnaireTitle,
    required this.createdAt,
    this.storeId,
    this.storeCode,
    this.storeName,
    this.storeAddress,
    this.storeCity,
    this.storeLatitude,
    this.storeLongitude,
  });

  factory JobPosting.fromJson(Map<String, dynamic> json) {
    return JobPosting(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      status: json['status'] as String? ?? '',
      applicationStatus: json['application_status'] as String?, // ⭐ 新字段
      clientId: json['client'] as int,
      clientName: json['client_name'] as String? ?? '',
      projectId: json['project'] as int,
      projectName: json['project_name'] as String? ?? '',
      questionnaireId: json['questionnaire'] as int,
      questionnaireTitle: json['questionnaire_title'] as String? ?? '',
      storeId: json['store_id'] as int?,
      storeCode: json['store_code'] as String?,
      storeName: json['store_name'] as String?,
      storeAddress: json['store_address'] as String?,
      storeCity: json['store_city'] as String?,
      storeLatitude: (json['store_latitude'] as num?)?.toDouble(),
      storeLongitude: (json['store_longitude'] as num?)?.toDouble(),
      createdAt: json['created_at'] as String? ?? '',
    );
  }

  /// 方便本地修改 status / applicationStatus
  JobPosting copyWith({
    int? id,
    String? title,
    String? description,
    String? status,
    String? applicationStatus,
    int? clientId,
    String? clientName,
    int? projectId,
    String? projectName,
    int? questionnaireId,
    String? questionnaireTitle,
    int? storeId,
    String? storeCode,
    String? storeName,
    String? storeAddress,
    String? storeCity,
    double? storeLatitude,
    double? storeLongitude,
    String? createdAt,
  }) {
    return JobPosting(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      applicationStatus: applicationStatus ?? this.applicationStatus,
      clientId: clientId ?? this.clientId,
      clientName: clientName ?? this.clientName,
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      questionnaireId: questionnaireId ?? this.questionnaireId,
      questionnaireTitle: questionnaireTitle ?? this.questionnaireTitle,
      storeId: storeId ?? this.storeId,
      storeCode: storeCode ?? this.storeCode,
      storeName: storeName ?? this.storeName,
      storeAddress: storeAddress ?? this.storeAddress,
      storeCity: storeCity ?? this.storeCity,
      storeLatitude: storeLatitude ?? this.storeLatitude,
      storeLongitude: storeLongitude ?? this.storeLongitude,
      createdAt: createdAt ?? this.createdAt,
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
    final questions = questionsJson
        .map((e) => QuestionDto.fromJson(e))
        .toList();

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
  final String type;
  final bool required;
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
    final options = optionsJson.map((e) => OptionDto.fromJson(e)).toList();

    final logicsJson = json['outgoing_logics'] as List<dynamic>? ?? [];
    final logics = logicsJson.map((e) => QuestionLogicDto.fromJson(e)).toList();

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
    final selectedIdsJson = json['selected_option_ids'] as List<dynamic>? ?? [];
    final mediaIdsJson = json['media_file_ids'] as List<dynamic>? ?? [];

    return AnswerDto(
      questionId: json['question'] as int,
      textValue: json['text_value'] as String?,
      numberValue: (json['number_value'] != null)
          ? double.tryParse(json['number_value'].toString())
          : null,
      selectedOptionIds: selectedIdsJson.map((e) => e as int).toList(),
      mediaFileIds: mediaIdsJson.map((e) => e as int).toList(),
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
    final answers = answersJson.map((e) => AnswerDto.fromJson(e)).toList();

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
  final String mediaType; // 'image' or 'video'

  MediaFileDto({
    required this.id,
    required this.fileUrl,
    required this.mediaType,
  });

  factory MediaFileDto.fromJson(Map<String, dynamic> json) {
    return MediaFileDto(
      id: json['id'] as int,
      fileUrl: (json['file_url'] as String?) ?? '',
      mediaType: (json['media_type'] as String?) ?? '',
    );
  }
}

class SubmissionCommentDto {
  final int id;
  final int submission;
  final int author;
  final String authorName;
  final String role; // "reviewer" / "evaluator"
  final String message;
  final String type; // "normal" / "system"
  final DateTime createdAt;

  SubmissionCommentDto({
    required this.id,
    required this.submission,
    required this.author,
    required this.authorName,
    required this.role,
    required this.message,
    required this.type,
    required this.createdAt,
  });

  factory SubmissionCommentDto.fromJson(Map<String, dynamic> json) {
    return SubmissionCommentDto(
      id: json['id'] as int,
      submission: json['submission'] as int,
      author: json['author'] as int,
      authorName: (json['author_name'] ?? '') as String,
      role: json['role'] as String,
      message: json['message'] as String,
      type: json['type'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'submission': submission,
      'author': author,
      'author_name': authorName,
      'role': role,
      'message': message,
      'type': type,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// 本地“答案草稿”模型（UI 层会用）
class AnswerDraft {
  final int questionId;
  String? textValue;
  double? numberValue;
  List<int> selectedOptionIds;
  List<int> mediaFileIds;

  /// 是否有媒体正在上传（用来显示 loading、禁止重复点）
  bool isUploadingMedia;

  /// 最近一次上传的错误信息（为空代表没错 / 已清空）
  String? mediaError;

  AnswerDraft({
    required this.questionId,
    this.textValue,
    this.numberValue,
    List<int>? selectedOptionIds,
    List<int>? mediaFileIds,
    this.isUploadingMedia = false,
    this.mediaError,
  }) : selectedOptionIds = selectedOptionIds ?? [],
       mediaFileIds = mediaFileIds ?? [];
}

/// 取消任务接口的返回
class CancelAssignmentResponse {
  final String detail;
  final bool confirmRequired;
  final String? rule;
  final Map<String, dynamic>? stats;

  CancelAssignmentResponse({
    required this.detail,
    required this.confirmRequired,
    this.rule,
    this.stats,
  });

  factory CancelAssignmentResponse.fromJson(Map<String, dynamic> json) {
    return CancelAssignmentResponse(
      detail: json['detail'] as String? ?? '',
      confirmRequired: json['confirm_required'] as bool? ?? false,
      rule: json['rule'] as String?,
      stats: json['stats'] as Map<String, dynamic>?,
    );
  }
}
