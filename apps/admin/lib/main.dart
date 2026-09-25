import 'package:flutter/material.dart';

void main() {
  runApp(const AdminApp());
}

/// Shell only. AD-1 replaces this with the login and side-nav shell.
class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Caramel Cottage Admin',
      home: Scaffold(body: Center(child: Text('Caramel Cottage Admin'))),
    );
  }
}
