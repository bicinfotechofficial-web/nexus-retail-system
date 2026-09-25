import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_admin/main.dart';

void main() {
  testWidgets('the shell starts', (tester) async {
    await tester.pumpWidget(const AdminApp());
    expect(find.text('Caramel Cottage Admin'), findsOneWidget);
  });
}
