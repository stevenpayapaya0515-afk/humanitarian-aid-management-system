import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class AidTrackSectionCard extends StatelessWidget {
  const AidTrackSectionCard({
    super.key,
    required this.child,
    this.width = double.infinity,
    this.height,
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.title,
    this.subtitle,
    this.icon,
    this.trailing,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding,
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD6E2D8), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x09000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: title == null
          ? child
          : LayoutBuilder(
              builder: (context, constraints) {
                final mobile = constraints.maxWidth < 520;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (icon != null) ...[
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: AppColors.lightGreen,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(
                              icon,
                              color: AppColors.primaryGreen,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title!,
                                style: const TextStyle(
                                  color: AppColors.darkText,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  subtitle!,
                                  style: const TextStyle(
                                    color: AppColors.greyText,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (!mobile && trailing != null) trailing!,
                      ],
                    ),
                    if (mobile && trailing != null) ...[
                      const SizedBox(height: 10),
                      Align(alignment: Alignment.centerRight, child: trailing!),
                    ],
                    const SizedBox(height: 18),
                    child,
                  ],
                );
              },
            ),
    );
  }
}
