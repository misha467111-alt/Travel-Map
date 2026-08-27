import 'package:flutter/material.dart';

import '../../../controllers/profile_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Налаштування')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            _Section(
              title: 'Загальні',
              children: [
                SwitchListTile.adaptive(
                  value: profileController.isOfflineMode,
                  onChanged: (value) => setState(
                    () => profileController.isOfflineMode = value,
                  ),
                  secondary: const Icon(Icons.offline_bolt_outlined),
                  title: const Text('Офлайн-режим'),
                  subtitle: const Text(
                    'Використовувати збережені локації та маршрути без мережі',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const _Section(
              title: 'Про публікації',
              children: [
                ListTile(
                  leading: Icon(Icons.verified_user_outlined),
                  title: Text('Модерація локацій'),
                  subtitle: Text(
                    'Нові локації проходять перевірку перед публікацією.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            _Section(
              title: 'Обліковий запис',
              children: [
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.redAccent),
                  title: const Text('Вийти'),
                  onTap: profileController.logout,
                ),
              ],
            ),
          ],
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          Card(margin: EdgeInsets.zero, child: Column(children: children)),
        ]),
      );
}
