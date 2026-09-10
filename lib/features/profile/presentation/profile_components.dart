import 'package:flutter/material.dart';

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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Stack(
          children: [
            CircleAvatar(
              key: const Key('profile_avatar'),
              radius: 25,
              backgroundColor: colors.primaryContainer,
              backgroundImage: avatarUrl?.isNotEmpty == true
                  ? NetworkImage(avatarUrl!)
                  : null,
              child: avatarUrl?.isNotEmpty == true
                  ? null
                  : Icon(Icons.person,
                      key: const Key('profile_avatar_fallback'),
                      size: 26,
                      color: colors.onPrimaryContainer),
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
                    iconSize: 13,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 24,
                      height: 24,
                    ),
                    style: const ButtonStyle(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(
                    name,
                    key: const Key('profile_display_name'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          height: 1.08,
                        ),
                  ),
                ),
                if (nameAction != null) nameAction!,
              ]),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  key: const Key('profile_subtitle'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.white60),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class ProfileStats extends StatelessWidget {
  const ProfileStats({required this.items, super.key});

  final List<({String label, String value})> items;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (final item in items)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF14231D),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(item.value,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: const Color(0xFFD4A017),
                              fontWeight: FontWeight.w600,
                            )),
                    Text(item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(fontSize: 10)),
                  ],
                ),
              ),
            ),
        ],
      );
}
