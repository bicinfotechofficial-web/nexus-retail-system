import 'package:flutter/material.dart';

import '../widgets/pos_scaffold.dart';

/// A drawer destination whose screen is built in a later task.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({required this.title, required this.task, super.key});

  final String title;

  /// The task that builds the real screen, e.g. `POS-7`.
  final String task;

  @override
  Widget build(BuildContext context) {
    return PosScaffold(
      title: title,
      body: Center(child: Text('$title arrives in $task.')),
    );
  }
}

/// A plain message page: starting up, signed out, or no access.
class MessageScreen extends StatelessWidget {
  const MessageScreen({required this.message, this.busy = false, super.key});

  final String message;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                ],
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
