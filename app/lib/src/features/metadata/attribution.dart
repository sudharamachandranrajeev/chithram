import 'package:flutter/material.dart';

const tmdbNotice =
    'This application uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB.';

class MetadataAttribution extends StatelessWidget {
  const MetadataAttribution({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Image.asset(
          'assets/attribution/tmdb_logo.png',
          width: 100,
          semanticLabel: 'TMDB',
        ),
        const SizedBox(height: 8),
        const Text(tmdbNotice, style: TextStyle(fontSize: 12)),
      ],
    ),
  );
}
