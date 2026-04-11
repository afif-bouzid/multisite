import 'package:flutter/material.dart';
class AppScaler extends StatelessWidget {
  final Widget child;
  final double scale;
  const AppScaler({super.key, required this.child, this.scale = 0.9});
  @override
  Widget build(BuildContext context) {
    if (scale == 1.0) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final double virtualWidth = constraints.maxWidth / scale;
        final double virtualHeight = constraints.maxHeight / scale;
        return FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.center,
          child: SizedBox(
            width: virtualWidth,
            height: virtualHeight,
            child: child,
          ),
        );
      },
    );
  }
}
