import 'package:flutter_test/flutter_test.dart';
import 'package:nox/assistant/actual_client.dart';
import 'package:nox/assistant/budget.dart';

void main() {
  test('accounts: closed ones left out, off-budget ones last', () {
    final accounts = parseAccounts({
      'data': [
        {'id': 'e', 'name': 'Épargne', 'offbudget': true, 'closed': false},
        {'id': 'c', 'name': 'Courant', 'offbudget': false, 'closed': false},
        {'id': 'x', 'name': 'Vieux', 'offbudget': false, 'closed': true},
      ],
    });
    expect(accounts.map((a) => a.id), ['c', 'e']);
    final f = Finances(
      accounts: [accounts[0].withBalance(12000), accounts[1].withBalance(50000)],
      month: parseMonth(null),
      operations: const [],
    );
    expect(f.total, 12000);
    expect(f.offBudget.single.name, 'Épargne');
  });

  test('month: income and hidden categories left out, spending positive', () {
    final m = parseMonth({
      'data': {
        'month': '2026-11',
        'toBudget': 2500,
        'totalBudgeted': -150000,
        'totalSpent': -42000,
        'totalIncome': 200000,
        'categoryGroups': [
          {
            'id': 'g1',
            'name': 'Courant',
            'is_income': false,
            'categories': [
              {'id': 'a', 'name': 'Courses', 'budgeted': 40000, 'spent': -35000, 'balance': 5000},
              {'id': 'b', 'name': 'Resto', 'budgeted': 10000, 'spent': -12000, 'balance': -2000},
              {
                'id': 'h',
                'name': 'Cachée',
                'hidden': true,
                'budgeted': 0,
                'spent': 0,
                'balance': 0,
              },
            ],
          },
          {
            'id': 'g2',
            'name': 'Revenus',
            'is_income': true,
            'categories': [
              {'id': 's', 'name': 'Salaire', 'is_income': true},
            ],
          },
        ],
      },
    });
    expect(m.month, '2026-11');
    expect(m.spent, 42000);
    expect(m.budgeted, 150000);
    expect(m.groups.single.name, 'Courant');
    expect(m.envelopes.map((e) => e.name), ['Courses', 'Resto']);
    final courses = m.envelopes.first;
    expect(courses.spent, 35000);
    expect(courses.low, isTrue);
    expect(m.envelopes.last.overspent, isTrue);
    expect(m.groups.single.balance, 3000);
  });

  test('operations: payee and category names, children left out', () {
    final ops = parseOperations(
      {
        'data': [
          {
            'id': '1',
            'account': 'c',
            'date': '2026-11-16',
            'amount': -2350,
            'payee': 'p1',
            'category': 'a',
            'notes': ' ',
          },
          {'id': '2', 'account': 'c', 'date': '2026-11-15', 'amount': -500, 'is_child': true},
          {
            'id': '3',
            'account': 'c',
            'date': '2026-11-14',
            'amount': -9000,
            'imported_payee': 'CB LECLERC',
            'is_parent': true,
          },
        ],
      },
      payees: parsePayees({
        'data': [
          {'id': 'p1', 'name': 'Boulangerie'},
          {'id': 'p2', 'name': 'Épargne', 'transfer_acct': 'e'},
        ],
      }),
      categories: {'a': 'Courses'},
    );
    expect(ops.map((o) => o.id), ['1', '3']);
    expect(ops[0].payee, 'Boulangerie');
    expect(ops[0].category, 'Courses');
    expect(ops[0].notes, isNull);
    expect(ops[1].payee, 'CB LECLERC');
    expect(ops[1].category, 'Ventilée');
    expect(
      parsePayees({
        'data': [
          {'id': 'p2', 'name': 'Épargne', 'transfer_acct': 'e'},
        ],
      })['p2'],
      '→ Épargne',
    );
  });

  test('euros: formatting and reading', () {
    expect(formatEuros(123456), '1 234,56 €');
    expect(formatEuros(-500), '−5,00 €');
    expect(formatEuros(1200, sign: true), '+12,00 €');
    expect(formatEuros(0, sign: true), '0,00 €');
    expect(parseEuros('12'), 1200);
    expect(parseEuros('12,5'), 1250);
    expect(parseEuros('1 234.56 €'), 123456);
    expect(parseEuros('0'), isNull);
    expect(parseEuros('-3'), isNull);
    expect(parseEuros('abc'), isNull);
    expect(parseEuros('1,234'), isNull);
  });

  test('months and days', () {
    expect(monthKey(DateTime(2026, 3, 5)), '2026-03');
    expect(dayKey(DateTime(2026, 3, 5)), '2026-03-05');
    expect(monthTitle('2026-11'), 'Novembre 2026');
    expect(monthTitle('nope'), 'nope');
  });

  test('actual-http-api address', () {
    expect(normalizeActualUrl('actual.local:5007'), 'http://actual.local:5007');
    expect(normalizeActualUrl('https://budget.fr/v1/'), 'https://budget.fr');
    expect(normalizeActualUrl(''), isNull);
    expect(normalizeActualUrl('ftp://x'), isNull);
  });
}
