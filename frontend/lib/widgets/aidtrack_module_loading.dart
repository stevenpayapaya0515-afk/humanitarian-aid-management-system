import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class AidTrackModuleLoading extends StatelessWidget {
  const AidTrackModuleLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 28, horizontal: 12),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 25,
              width: 25,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.primaryGreen,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Loading...',
              style: TextStyle(fontSize: 13, color: AppColors.greyText),
            ),
          ],
        ),
      ),
    );
  }
}
