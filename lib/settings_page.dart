import 'package:flutter/material.dart';
import 'settings/favourite_page.dart';
import 'settings/display_settings_page.dart';
import 'settings/update_database_page.dart';
import 'settings/privacy_policy_page.dart';
import 'settings/storage_settings.dart';
import 'settings/notification_settings_page.dart';
import 'settings/contact_us_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: theme.colorScheme.surfaceTint,
        elevation: 2,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              _buildMenuItem(
                context,
                icon: Icons.favorite,
                title: 'Favourites',
                subtitle: 'Manage your favorite items',
                onTap: () {
                  FocusScope.of(context).unfocus();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FavouritePage()),
                  );
                },
              ),
              const SizedBox(height: 8),
              _buildMenuItem(
                context,
                icon: Icons.display_settings,
                title: 'Display Settings',
                subtitle: 'Customize theme and appearance',
                onTap: () {
                  FocusScope.of(context).unfocus();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DisplaySettingsPage()),
                  );
                },
              ),
              const SizedBox(height: 8),
              _buildMenuItem(
                context,
                icon: Icons.cloud_download,
                title: 'Update Database',
                subtitle: 'Sync and update data',
                onTap: () {
                  FocusScope.of(context).unfocus();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const UpdateDatabasePage()),
                  );
                },
              ),
              const SizedBox(height: 8),
              _buildMenuItem(
                context,
                icon: Icons.storage,
                title: 'Storage Settings',
                subtitle: 'Backup, restore & cache management',
                onTap: () {
                  FocusScope.of(context).unfocus();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StoragePage()),
                  );
                },
              ),
              const SizedBox(height: 8),
              _buildMenuItem(
                context,
                icon: Icons.notifications,
                title: 'Notification Settings',
                subtitle: 'Manage notification preferences',
                onTap: () {
                  FocusScope.of(context).unfocus();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NotificationSettingsPage()),
                  );
                },
              ),
              const SizedBox(height: 8),
              _buildMenuItem(
                context,
                icon: Icons.contact_support,
                title: 'Contact Us',
                subtitle: 'Reach out for support',
                onTap: () {
                  FocusScope.of(context).unfocus();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ContactUsPage()),
                  );
                },
              ),
              const SizedBox(height: 8),
              _buildMenuItem(
                context,
                icon: Icons.privacy_tip,
                title: 'Privacy & Policy',
                subtitle: 'View privacy information',
                onTap: () {
                  FocusScope.of(context).unfocus();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
                  );
                },
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'Version 2.6.4',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String subtitle,
        required VoidCallback onTap,
      }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      surfaceTintColor: Theme.of(context).colorScheme.surfaceTint,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                child: Icon(
                  icon,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}