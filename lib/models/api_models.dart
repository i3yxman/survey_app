// lib/models/api_models.dart

import 'package:survey_app/utils/date_format.dart';

/// 登录成功返回的数据结构
class LoginResult {
  final String token; // ✅ 新增：DRF Token
  final int id;
  final String username;
  final String role;
  final String? email;
  final String? phone;
  final String? fullName;
  final String? gender;
  final String? idNumber;
  final String? province;
  final String? city;
  final String? address;
  final String? alipayAccount;
  final Map<String, dynamic>? notificationSettings;

  // 下面这些是你旧接口里可能用到的字段，先保留为可选，避免别处爆炸
  final String? status;
  final String? applicationStatus;

  LoginResult({
    required this.token,
    required this.id,
    required this.username,
    required this.role,
    this.email,
    this.phone,
    this.fullName,
    this.gender,
    this.idNumber,
    this.province,
    this.city,
    this.address,
    this.alipayAccount,
    this.notificationSettings,
    this.status,
    this.applicationStatus,
  });

  factory LoginResult.fromJson(Map<String, dynamic> json) {
    return LoginResult(
      token: (json['token'] as String?) ?? '',
      id: (json['id'] as int?) ?? 0,
      username: (json['username'] as String?) ?? '',
      role: (json['role'] as String?) ?? '',
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      fullName: json['full_name'] as String?,
      gender: json['gender'] as String?,
      idNumber: json['id_number'] as String?,
      province: json['province'] as String?,
      city: json['city'] as String?,
      address: json['address'] as String?,
      alipayAccount: json['alipay_account'] as String?,
      notificationSettings: (json['notification_settings'] as Map?)?.cast<String, dynamic>(),
      status: json['status'] as String?,
      applicationStatus: json['application_status'] as String?,
    );
  }

  LoginResult copyWith({
    String? token,
    int? id,
    String? username,
    String? role,
    String? email,
    String? phone,
    String? fullName,
    String? gender,
    String? idNumber,
    String? province,
    String? city,
    String? address,
    String? alipayAccount,
    Map<String, dynamic>? notificationSettings,
  }) {
    return LoginResult(
      token: token ?? this.token,
      id: id ?? this.id,
      username: username ?? this.username,
      role: role ?? this.role,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      fullName: fullName ?? this.fullName,
      gender: gender ?? this.gender,
      idNumber: idNumber ?? this.idNumber,
      province: province ?? this.province,
      city: city ?? this.city,
      address: address ?? this.address,
      alipayAccount: alipayAccount ?? this.alipayAccount,
      notificationSettings: notificationSettings ?? this.notificationSettings,
      status: status,
      applicationStatus: applicationStatus,
    );
  }
}

/// 任务列表的模型
class Assignment {
  final int id;
  final String status;
  final DateTime createdAt;

  String get createdAtText => formatDateTimeZh(createdAt);

  String? get projectDateRange {
    if (projectStartDate == null || projectEndDate == null) return null;
    return "${formatDateZh(projectStartDate)} ~ ${formatDateZh(projectEndDate)}";
  }

  String? get plannedVisitDateText {
    if (plannedVisitDate == null) return null;
    return formatDateZh(plannedVisitDate);
  }

  final DateTime? projectStartDate;
  final DateTime? projectEndDate;
  final double? rewardAmount;
  final double? reimbursementAmount;
  final String? currency;
  final DateTime? plannedVisitDate;
  final List<String> avoidVisitDates;
  final List<Map<String, String>> avoidVisitDateRanges;
  final String? postingTitle;
  final String? postingDescription;
  final String? taskContent;
  final String? currentSubmissionStatus;
  final List<TaskAttachment> taskAttachments;

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

    this.projectStartDate,
    this.projectEndDate,
    this.rewardAmount,
    this.reimbursementAmount,
    this.currency,
    this.plannedVisitDate,
    this.avoidVisitDates = const [],
    this.avoidVisitDateRanges = const [],

    this.postingTitle,
    this.postingDescription,
    this.taskContent,
    this.currentSubmissionStatus,
    this.taskAttachments = const [],

    this.jobPosting,

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
      createdAt: DateTime.parse(json['created_at']),

      jobPosting: json['job_posting'] as int?,

      // 这里仍然用后端原始字段名 project / questionnaire
      project: json['project'] as int?,
      projectName: json['project_name']?.toString(),
      projectStartDate: json['project_start_date'] != null
          ? DateTime.parse(json['project_start_date'])
          : null,
      projectEndDate: json['project_end_date'] != null
          ? DateTime.parse(json['project_end_date'])
          : null,
      rewardAmount: toDouble(json['reward_amount']),
      reimbursementAmount: toDouble(json['reimbursement_amount']),
      currency: json['currency']?.toString(),
      plannedVisitDate: json['planned_visit_date'] != null
          ? DateTime.parse(json['planned_visit_date'])
          : null,
      avoidVisitDates: (json['avoid_visit_dates'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      avoidVisitDateRanges: (json['avoid_visit_date_ranges'] as List<dynamic>?)
              ?.map((e) => Map<String, String>.from(e as Map))
              .toList() ??
          const [],
      postingTitle: json['posting_title']?.toString(),
      postingDescription: json['posting_description']?.toString(),
      taskContent: json['task_content']?.toString(),
      currentSubmissionStatus: json['current_submission_status']?.toString(),
      taskAttachments: (json['task_attachments'] as List<dynamic>?)
              ?.map((e) => TaskAttachment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
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
      'created_at': createdAt.toIso8601String(),

      'project_start_date': projectStartDate?.toIso8601String().substring(
        0,
        10,
      ),
      'project_end_date': projectEndDate?.toIso8601String().substring(0, 10),
      'reward_amount': rewardAmount,
      'reimbursement_amount': reimbursementAmount,
      'planned_visit_date': plannedVisitDate?.toIso8601String().substring(
        0,
        10,
      ),

      'posting_title': postingTitle,
      'posting_description': postingDescription,
      'task_content': taskContent,
      'current_submission_status': currentSubmissionStatus,
      'task_attachments': taskAttachments.map((e) => e.toJson()).toList(),

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

class TaskAttachment {
  final int id;
  final String mediaType;
  final String? name;
  final String url;
  final int? size;

  TaskAttachment({
    required this.id,
    required this.mediaType,
    required this.url,
    this.name,
    this.size,
  });

  factory TaskAttachment.fromJson(Map<String, dynamic> json) {
    return TaskAttachment(
      id: json['id'] as int,
      mediaType: json['media_type']?.toString() ?? 'file',
      name: json['name']?.toString(),
      url: json['url']?.toString() ?? json['file_url']?.toString() ?? '',
      size: json['size'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'media_type': mediaType,
      'name': name,
      'url': url,
      'size': size,
    };
  }
}

/// 任务大厅里的“可申请任务”模型
class JobPosting {
  final int id;
  final String title;
  final String description;
  final String? taskContent;
  final List<TaskAttachment> taskAttachments;

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

  final String? projectStartDate;
  final String? projectEndDate;
  final double? rewardAmount;
  final double? reimbursementAmount;
  final String? currency;
  final List<String> avoidVisitDates;
  final List<Map<String, String>> avoidVisitDateRanges;
  final String? plannedVisitDate;

  final int? storeId;
  final String? storeCode;
  final String? storeName;
  final String? storeAddress;
  final String? storeCity;
  final double? storeLatitude;
  final double? storeLongitude;

  final DateTime createdAt;
  final DateTime publishedAt;

  JobPosting({
    required this.id,
    required this.title,
    required this.description,
    this.taskContent,
    this.taskAttachments = const [],
    required this.status,
    this.applicationStatus, // ⭐ 不是 required
    required this.clientId,
    required this.clientName,
    required this.projectId,
    required this.projectName,
    required this.questionnaireId,
    required this.questionnaireTitle,
    required this.createdAt,
    required this.publishedAt,
    this.plannedVisitDate,
    this.projectStartDate,
    this.projectEndDate,
    this.rewardAmount,
    this.reimbursementAmount,
    this.currency,
    this.avoidVisitDates = const [],
    this.avoidVisitDateRanges = const [],
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
      taskContent: json['task_content']?.toString(),
      taskAttachments: (json['task_attachments'] as List<dynamic>?)
              ?.map((e) => TaskAttachment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      status:
          (json['status'] as String?) ?? (json['new_status'] as String?) ?? '',
      applicationStatus: json['application_status'] as String?, // ⭐ 新字段
      clientId: json['client'] as int,
      clientName: json['client_name'] as String? ?? '',
      projectId: json['project'] as int,
      projectName: json['project_name'] as String? ?? '',
      questionnaireId: json['questionnaire'] as int,
      questionnaireTitle: json['questionnaire_title'] as String? ?? '',
      plannedVisitDate: json['planned_visit_date'] as String?,
      projectStartDate: json['project_start_date'] as String?,
      projectEndDate: json['project_end_date'] as String?,
      rewardAmount: (json['reward_amount'] as num?)?.toDouble(),
      reimbursementAmount: (json['reimbursement_amount'] as num?)?.toDouble(),
      currency: json['currency']?.toString(),
      avoidVisitDates:
          (json['avoid_visit_dates'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      avoidVisitDateRanges:
          (json['avoid_visit_date_ranges'] as List<dynamic>?)
              ?.map(
                (e) => {
                  'start': (e as Map)['start'].toString(),
                  'end': (e)['end'].toString(),
                },
              )
              .toList() ??
          [],
      storeId: json['store_id'] as int?,
      storeCode: json['store_code'] as String?,
      storeName: json['store_name'] as String?,
      storeAddress: json['store_address'] as String?,
      storeCity: json['store_city'] as String?,
      storeLatitude: (json['store_latitude'] as num?)?.toDouble(),
      storeLongitude: (json['store_longitude'] as num?)?.toDouble(),
      createdAt: DateTime.parse(
        (json['created_at'] as String?) ?? DateTime.now().toIso8601String(),
      ),
      publishedAt: DateTime.parse(
        (json['published_at'] as String?) ??
            (json['start_at'] as String?) ??
            (json['created_at'] as String?) ??
            DateTime.now().toIso8601String(),
      ),
    );
  }

  /// 方便本地修改 status / applicationStatus
  JobPosting copyWith({
    int? id,
    String? title,
    String? description,
    String? taskContent,
    List<TaskAttachment>? taskAttachments,
    String? status,
    String? applicationStatus,
    int? clientId,
    String? clientName,
    int? projectId,
    String? projectName,
    int? questionnaireId,
    String? questionnaireTitle,
    double? rewardAmount,
    double? reimbursementAmount,
    String? currency,
    int? storeId,
    String? storeCode,
    String? storeName,
    String? storeAddress,
    String? storeCity,
    double? storeLatitude,
    double? storeLongitude,
    DateTime? createdAt,
    DateTime? publishedAt,
  }) {
    return JobPosting(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      taskContent: taskContent ?? this.taskContent,
      taskAttachments: taskAttachments ?? this.taskAttachments,
      status: status ?? this.status,
      applicationStatus: applicationStatus ?? this.applicationStatus,
      clientId: clientId ?? this.clientId,
      clientName: clientName ?? this.clientName,
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      questionnaireId: questionnaireId ?? this.questionnaireId,
      questionnaireTitle: questionnaireTitle ?? this.questionnaireTitle,
      rewardAmount: rewardAmount ?? this.rewardAmount,
      reimbursementAmount: reimbursementAmount ?? this.reimbursementAmount,
      currency: currency ?? this.currency,
      storeId: storeId ?? this.storeId,
      storeCode: storeCode ?? this.storeCode,
      storeName: storeName ?? this.storeName,
      storeAddress: storeAddress ?? this.storeAddress,
      storeCity: storeCity ?? this.storeCity,
      storeLatitude: storeLatitude ?? this.storeLatitude,
      storeLongitude: storeLongitude ?? this.storeLongitude,
      createdAt: createdAt ?? this.createdAt,
      publishedAt: publishedAt ?? this.publishedAt,
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
  final int? triggerOptionId;
  final String? triggerText;
  final double? triggerNumber;
  final int? gotoQuestionId;
  final bool gotoEnd;
  final String effect;
  final int order;

  QuestionLogicDto({
    required this.id,
    required this.fromQuestionId,
    required this.triggerOptionId,
    required this.triggerText,
    required this.triggerNumber,
    required this.gotoQuestionId,
    required this.gotoEnd,
    required this.effect,
    required this.order,
  });

  factory QuestionLogicDto.fromJson(Map<String, dynamic> json) {
    return QuestionLogicDto(
      id: json['id'] as int,
      fromQuestionId: json['from_question'] as int,
      triggerOptionId: json['trigger_option'] as int?,
      triggerText: json['trigger_text'] as String?,
      triggerNumber: json['trigger_number'] != null
          ? double.tryParse(json['trigger_number'].toString())
          : null,
      gotoQuestionId: json['goto_question'] as int?,
      gotoEnd: json['goto_end'] as bool? ?? false,
      effect: json['effect'] as String? ?? 'show',
      order: json['order'] as int? ?? 0,
    );
  }
}

/// 题目 DTO
class QuestionDto {
  final int id;
  final String text;
  final String type;
  final bool required;
  final double score;
  final int fontSize;
  final bool visibleToEvaluator;
  final bool visibleToAdmin;
  final bool visibleToClient;
  final List<int> applicableStoreIds;
  final List<int> applicableGroupIds;
  final List<OptionDto> options;
  final List<QuestionLogicDto> outgoingLogics;

  QuestionDto({
    required this.id,
    required this.text,
    required this.type,
    required this.required,
    required this.score,
    required this.fontSize,
    required this.visibleToEvaluator,
    required this.visibleToAdmin,
    required this.visibleToClient,
    required this.applicableStoreIds,
    required this.applicableGroupIds,
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
      score: json['score'] != null ? double.tryParse(json['score'].toString()) ?? 0 : 0,
      fontSize: json['font_size'] as int? ?? 14,
      visibleToEvaluator: json['visible_to_evaluator'] as bool? ?? true,
      visibleToAdmin: json['visible_to_admin'] as bool? ?? true,
      visibleToClient: json['visible_to_client'] as bool? ?? false,
      applicableStoreIds: (json['applicable_store_ids'] as List<dynamic>? ?? [])
          .map((e) => e as int)
          .toList(),
      applicableGroupIds: (json['applicable_group_ids'] as List<dynamic>? ?? [])
          .map((e) => e as int)
          .toList(),
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
  final double score;

  OptionDto({
    required this.id,
    required this.text,
    required this.value,
    required this.order,
    required this.score,
  });

  factory OptionDto.fromJson(Map<String, dynamic> json) {
    return OptionDto(
      id: json['id'] as int,
      text: json['text'] as String? ?? '',
      value: json['value'] as String? ?? '',
      order: json['order'] as int? ?? 0,
      score: json['score'] != null ? double.tryParse(json['score'].toString()) ?? 0 : 0,
    );
  }
}

class AnswerDto {
  final int questionId;
  final String? textValue;
  final double? numberValue;
  final String? dateValue;
  final String? timeValue;
  final double? locationLat;
  final double? locationLng;
  final String? locationAddress;
  final List<int> selectedOptionIds;
  final List<int> mediaFileIds;

  AnswerDto({
    required this.questionId,
    this.textValue,
    this.numberValue,
    this.dateValue,
    this.timeValue,
    this.locationLat,
    this.locationLng,
    this.locationAddress,
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
      dateValue: json['date_value'] as String?,
      timeValue: json['time_value'] as String?,
      locationLat: json['location_lat'] != null
          ? double.tryParse(json['location_lat'].toString())
          : null,
      locationLng: json['location_lng'] != null
          ? double.tryParse(json['location_lng'].toString())
          : null,
      locationAddress: json['location_address'] as String?,
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
      status:
          (json['status'] as String?) ?? (json['new_status'] as String?) ?? '',
      version: json['version'] as int?,
      submittedAt: json['submitted_at'] as String?,
      answers: answers,
    );
  }
}

class MediaFileDto {
  final int id;
  final String fileUrl;
  final String mediaType; // 'image' or 'video' or 'audio'

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
  String? dateValue;
  String? timeValue;
  double? locationLat;
  double? locationLng;
  String? locationAddress;
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
    this.dateValue,
    this.timeValue,
    this.locationLat,
    this.locationLng,
    this.locationAddress,
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
