import 'package:flutter/material.dart';

void main() {
  runApp(const PosApp());
}

/// Shell only. POS-1 replaces this with the Riverpod and go_router shell.
class PosApp extends StatelessWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Caramel Cottage POS',
      home: Scaffold(body: Center(child: Text('Caramel Cottage POS'))),
    );
  }
}
