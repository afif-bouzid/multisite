import 'package:flutter/material.dart';

class ConfigurationPlaceholderView extends StatelessWidget {
  final String pageTitle;
  const ConfigurationPlaceholderView({super.key, required this.pageTitle});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.construction_outlined,
                size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 20),
            Text(pageTitle, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(
              "Cette section est en cours de développement.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
