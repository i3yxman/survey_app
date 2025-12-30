// lib/utils/map_selector.dart
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class MapOption {
  final String name;
  final Uri uri;
  MapOption(this.name, this.uri);
}

/// 粗略判断是否在中国大陆范围（不含港澳台）
bool _isLikelyMainlandChina(double lat, double lng) {
  // Mainland China bbox (rough)
  return lat >= 3.86 && lat <= 53.55 && lng >= 73.66 && lng <= 135.05;
}

Future<void> openMapSelector({
  required BuildContext context,
  required double lat,
  required double lng,
  required String label,
}) async {
  final encodedLabel = Uri.encodeComponent(label);
  final inChina = _isLikelyMainlandChina(lat, lng);

  final options = <MapOption>[];

  // ============ Amap / 高德 ============
  final Uri amapUri = Platform.isIOS
      ? Uri.parse(
          'iosamap://path?sourceApplication=survey_app'
          '&dlat=$lat&dlon=$lng&dname=$encodedLabel&dev=0&t=0',
        )
      : Uri.parse(
          'androidamap://route?sourceApplication=survey_app'
          '&dlat=$lat&dlon=$lng&dname=$encodedLabel&dev=0&t=0',
        );

  if (await canLaunchUrl(amapUri)) {
    options.add(MapOption('高德地图', amapUri));
  }

  // ============ Baidu / 百度 ============
  final Uri baiduUri = Uri.parse(
    'baidumap://map/direction?destination=name:$encodedLabel|latlng:$lat,$lng&mode=driving&coord_type=bd09ll',
  );

  if (await canLaunchUrl(baiduUri)) {
    options.add(MapOption('百度地图', baiduUri));
  }

  // ============ Tencent / 腾讯 ============
  // routeplan docs style: qqmap://map/routeplan?type=drive&tocoord=lat,lng&to=xxx&coord_type=1
  final Uri tencentUri = Uri.parse(
    'qqmap://map/routeplan?type=drive&tocoord=$lat,$lng&to=$encodedLabel&coord_type=1',
  );

  if (await canLaunchUrl(tencentUri)) {
    options.add(MapOption('腾讯地图', tencentUri));
  }

  // ============ Apple Maps (iOS only, always available) ============
  if (Platform.isIOS) {
    options.add(
      MapOption(
        '苹果地图',
        Uri.parse('http://maps.apple.com/?daddr=$lat,$lng&q=$encodedLabel'),
      ),
    );
  }

  // ============ Google Maps (only when NOT in China, and app installed) ============
  if (!inChina) {
    final Uri googleUri = Platform.isIOS
        ? Uri.parse('comgooglemaps://?daddr=$lat,$lng&directionsmode=driving')
        : Uri.parse('google.navigation:q=$lat,$lng&mode=d');

    if (await canLaunchUrl(googleUri)) {
      options.add(MapOption('Google 地图', googleUri));
    }
  }

  if (options.isEmpty) {
    // 都没装：给一个兜底（浏览器打开腾讯/高德/百度任选其一，这里用腾讯网页版）
    final fallback = Uri.parse(
      'https://map.qq.com/?type=drive&to=$encodedLabel&'
      'tocoord=$lat,$lng',
    );
    await launchUrl(fallback, mode: LaunchMode.externalApplication);
    return;
  }

  showModalBottomSheet(
    context: context,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((o) {
            return ListTile(
              title: Text(o.name),
              onTap: () async {
                Navigator.pop(ctx);
                await launchUrl(o.uri, mode: LaunchMode.externalApplication);
              },
            );
          }).toList(),
        ),
      );
    },
  );
}
