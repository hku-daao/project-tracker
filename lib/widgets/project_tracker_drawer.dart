import 'package:flutter/material.dart';

/// Navigation drawer shared by [HomeScreen], Default dashboard, and Project views.
class ProjectTrackerDrawer extends StatelessWidget {
  const ProjectTrackerDrawer({
    super.key,
    required this.welcomeName,
    required this.onHome,
    required this.onFeedback,
    required this.onImportantNotice,
    required this.onSignOut,
    this.showSignOut = true,
  });

  final String welcomeName;
  final VoidCallback onHome;

  final VoidCallback onFeedback;
  final VoidCallback onImportantNotice;
  final VoidCallback onSignOut;
  final bool showSignOut;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              margin: EdgeInsets.zero,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Project Tracker',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Welcome, $welcomeName',
                      style: Theme.of(context).textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Home'),
              onTap: onHome,
            ),
            ListTile(
              leading: const Icon(Icons.feedback_outlined),
              title: const Text('Feedback'),
              onTap: onFeedback,
            ),
            ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Important Notice'),
              onTap: onImportantNotice,
            ),
            if (showSignOut)
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                onTap: onSignOut,
              ),
          ],
        ),
      ),
    );
  }
}
