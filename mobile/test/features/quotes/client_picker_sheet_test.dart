import 'package:contractorhub/features/quotes/data/quote_client_repository.dart';
import 'package:contractorhub/features/quotes/domain/quote_client.dart';
import 'package:contractorhub/features/quotes/presentation/widgets/client_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockQuoteClientRepository extends Mock implements QuoteClientRepository {}

/// Picking the client a quote is for.
///
/// The send transition refuses a quote with no client, so this sheet is what
/// turns that refusal from a dead end into something the user can resolve.
void main() {
  late MockQuoteClientRepository repository;

  const nora = QuoteClient(
    userId: 'u-1',
    email: 'nora@example.com',
    firstName: 'Nora',
    lastName: 'Client',
  );

  setUp(() {
    repository = MockQuoteClientRepository();
  });

  Future<QuoteClient?> pumpSheet(WidgetTester tester) async {
    QuoteClient? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await ClientPickerSheet.show(
                  context,
                  repository: repository,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('lists the roster and returns the client that was tapped',
      (tester) async {
    when(() => repository.listClients(search: any(named: 'search')))
        .thenAnswer((_) async => [nora]);

    await pumpSheet(tester);
    expect(find.text('Nora Client'), findsOneWidget);
    expect(find.text('nora@example.com'), findsOneWidget);

    await tester.tap(find.byKey(const Key('client_option_u-1')));
    await tester.pumpAndSettle();

    expect(find.text('Choose a client'), findsNothing, reason: 'sheet should close');
  });

  testWidgets('says plainly that adding a client grants no login',
      (tester) async {
    when(() => repository.listClients(search: any(named: 'search')))
        .thenAnswer((_) async => const <QuoteClient>[]);

    await pumpSheet(tester);
    await tester.tap(find.byKey(const Key('client_add_new_button')));
    await tester.pumpAndSettle();

    expect(find.text('Adding a client does not give them a login.'), findsOneWidget);
  });

  testWidgets('creates a client and returns it', (tester) async {
    when(() => repository.listClients(search: any(named: 'search')))
        .thenAnswer((_) async => const <QuoteClient>[]);
    when(() => repository.createClient(
          email: any(named: 'email'),
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
        )).thenAnswer((_) async => nora);

    await pumpSheet(tester);
    await tester.tap(find.byKey(const Key('client_add_new_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('client_email_field')),
      'nora@example.com',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('client_create_button')));
    await tester.pumpAndSettle();

    verify(() => repository.createClient(
          email: 'nora@example.com',
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
        )).called(1);
  });

  testWidgets('shows the backend reason when a create is refused',
      (tester) async {
    when(() => repository.listClients(search: any(named: 'search')))
        .thenAnswer((_) async => const <QuoteClient>[]);
    when(() => repository.createClient(
          email: any(named: 'email'),
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
        )).thenThrow(
      const QuoteClientException(
        'That email address already belongs to another account.',
      ),
    );

    await pumpSheet(tester);
    await tester.tap(find.byKey(const Key('client_add_new_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('client_email_field')),
      'taken@example.com',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('client_create_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('client_picker_error')), findsOneWidget);
    expect(find.textContaining('another account'), findsOneWidget);
  });

  testWidgets('shows the reason when the roster cannot be loaded',
      (tester) async {
    when(() => repository.listClients(search: any(named: 'search')))
        .thenThrow(const QuoteClientException('Clients are not available.'));

    await pumpSheet(tester);

    expect(find.text('Clients are not available.'), findsOneWidget);
  });

  testWidgets('cannot submit an empty email', (tester) async {
    when(() => repository.listClients(search: any(named: 'search')))
        .thenAnswer((_) async => const <QuoteClient>[]);

    await pumpSheet(tester);
    await tester.tap(find.byKey(const Key('client_add_new_button')));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('client_create_button')),
    );
    expect(button.onPressed, isNull);
  });
}
