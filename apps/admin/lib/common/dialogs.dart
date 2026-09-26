import 'package:flutter/material.dart';
import 'package:nexus_data/nexus_data.dart';

/// Asks before a destructive action. True only when the user confirms.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          key: const Key('confirm-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('confirm-ok'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// A message for a failed data-layer call.
String failureMessage(Object error) {
  if (error is! DataFailure) return 'Something went wrong: $error';
  return switch (error.reason) {
    FailureReason.offline =>
      'You are offline. The console needs a connection for this.',
    FailureReason.notPermitted => 'You do not have permission to do this.',
    FailureReason.notFound => 'It no longer exists. Refresh and try again.',
    FailureReason.ruleViolation =>
      error.detail.isEmpty
          ? 'This change is not allowed.'
          : 'This change is not allowed: ${error.detail}.',
    _ => 'Something went wrong (${error.reason.name}).',
  };
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
