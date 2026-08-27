import 'package:flutter/material.dart';

import '../../../core/theme/app_design.dart';

class ProfileIdentityHeader extends StatelessWidget {
  const ProfileIdentityHeader({
    required this.name,
    required this.subtitle,
    this.avatarUrl,
    this.onAvatarTap,
    this.nameAction,
    super.key,
  });

  final String name;
  final String subtitle;
  final String? avatarUrl;
  final VoidCallback? onAvatarTap;
  final Widget? nameAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Stack(
          children: [
            CircleAvatar(
              radius: 48,
              backgroundColor: colors.primaryContainer,
              backgroundImage: avatarUrl?.isNotEmpty == true
                  ? NetworkImage(avatarUrl!)
                  : null,
              child: avatarUrl?.isNotEmpty == true
                  ? null
                  : Icon(Icons.person,
                      size: 52, color: colors.onPrimaryContainer),
            ),
            if (onAvatarTap != null)
              Positioned(
                right: 0,
                bottom: 0,
                child: Material(
                  color: colors.primary,
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Змінити аватар',
                    onPressed: onAvatarTap,
                    icon: Icon(Icons.camera_alt, color: colors.onPrimary),
                    iconSize: 20,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (nameAction != null) nameAction!,
          ],
        ),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class ProfileStats extends StatelessWidget {
  const ProfileStats({required this.items, super.key});

  final List<({String label, String value})> items;

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.center,
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.md,
        children: [
          for (final item in items)
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 84),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.value,
                      style: Theme.of(context).textTheme.titleLarge),
                  Text(item.label, textAlign: TextAlign.center),
                ],
              ),
            ),
        ],
      );
}
