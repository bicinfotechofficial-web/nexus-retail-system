import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_pos/main.dart';

void main() {
  testWidgets('the shell starts', (tester) async {
    await tester.pumpWidget(const PosApp());
    expect(find.text('Caramel Cottage POS'), findsOneWidget);
  });
}
