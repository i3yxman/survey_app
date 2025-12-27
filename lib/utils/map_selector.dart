// lib/utils/map_selector.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class MapOption {
  final String name;
  final Uri uri;

  MapOption(this.name, this.uri);
}

Future<void> openMapSelector({
  required BuildContext context,
  required double lat,
  required double lng,
  required String label,
}) async {
  final encodedLabel = Uri.encodeComponent(label);

  final options = <MapOption>[
    MapOption(
      '苹果地图',
      Uri.parse('http://maps.apple.com/?daddr=$lat,$lng&q=$encodedLabel'),
    ),
    MapOption(
      'Google 地图',
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'),
    ),
    MapOption(
      '高德地图',
      Uri.parse('iosamap://path?dlat=$lat&dlon=$lng&dname=$encodedLabel'),
    ),
    MapOption(
      '百度地图',
      Uri.parse(
        'baidumap://map/direction?destination=name:$encodedLabel|latlng:$lat,$lng',
      ),
    ),
  ];

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
