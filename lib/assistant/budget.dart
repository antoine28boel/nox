/// Finances read from Actual Budget (through actual-http-api). Amounts are
/// in cents, as Actual stores them: spending is negative.
library;

class BudgetAccount {
  const BudgetAccount({
    required this.id,
    required this.name,
    this.offBudget = false,
    this.balance = 0,
  });

  final String id;
  final String name;
  final bool offBudget;
  final int balance;

  BudgetAccount withBalance(int value) =>
      BudgetAccount(id: id, name: name, offBudget: offBudget, balance: value);
}

/// One category of the month: what was put in, spent, and what is left.
class Envelope {
  const Envelope({
    required this.id,
    required this.name,
    required this.budgeted,
    required this.spent,
    required this.balance,
  });

  final String id;
  final String name;
  final int budgeted;
  final int spent;
  final int balance;

  bool get overspent => balance < 0;

  /// Less than a fifth of what was put in is left.
  bool get low => !overspent && budgeted > 0 && balance * 5 < budgeted;
}

class EnvelopeGroup {
  const EnvelopeGroup(this.name, this.envelopes);
  final String name;
  final List<Envelope> envelopes;

  int get balance => envelopes.fold(0, (sum, e) => sum + e.balance);
}

class BudgetMonth {
  const BudgetMonth({
    required this.month,
    required this.toBudget,
    required this.budgeted,
    required this.spent,
    required this.income,
    required this.groups,
  });

  /// "2026-11".
  final String month;

  /// Money not yet given to an envelope (negative: too much given).
  final int toBudget;
  final int budgeted;

  /// Spent this month, as a positive amount.
  final int spent;
  final int income;
  final List<EnvelopeGroup> groups;

  Iterable<Envelope> get envelopes => groups.expand((g) => g.envelopes);
}

class Operation {
  const Operation({
    required this.id,
    required this.accountId,
    required this.date,
    required this.amount,
    required this.payee,
    this.category,
    this.notes,
  });

  final String id;
  final String accountId;
  final DateTime date;
  final int amount;
  final String payee;
  final String? category;
  final String? notes;
}

/// Everything the "Budget" tab shows.
class Finances {
  const Finances({required this.accounts, required this.month, required this.operations});

  final List<BudgetAccount> accounts;
  final BudgetMonth month;

  /// Latest first.
  final List<Operation> operations;

  List<BudgetAccount> get onBudget => [
    for (final a in accounts)
      if (!a.offBudget) a,
  ];

  List<BudgetAccount> get offBudget => [
    for (final a in accounts)
      if (a.offBudget) a,
  ];

  int get total => onBudget.fold(0, (sum, a) => sum + a.balance);
}

/// actual-http-api wraps every answer in {"data": …}.
Object? unwrapData(Object? json) => json is Map && json.containsKey('data') ? json['data'] : json;

int _cents(Object? v) => v is num ? v.round() : int.tryParse('$v') ?? 0;

/// Open accounts, on-budget ones first.
List<BudgetAccount> parseAccounts(Object? json) {
  final list = unwrapData(json);
  if (list is! List) return const [];
  final accounts = [
    for (final a in list)
      if (a is Map && a['id'] is String && a['closed'] != true && a['tombstone'] != true)
        BudgetAccount(
          id: a['id'] as String,
          name: '${a['name'] ?? 'Compte'}',
          offBudget: a['offbudget'] == true,
          balance: _cents(a['balance'] ?? a['workingBalance']),
        ),
  ];
  // Stable: keeps Actual's order inside each kind.
  return [...accounts.where((a) => !a.offBudget), ...accounts.where((a) => a.offBudget)];
}

/// The month's envelopes, without income and hidden categories.
BudgetMonth parseMonth(Object? json) {
  final m = unwrapData(json);
  if (m is! Map) {
    return const BudgetMonth(month: '', toBudget: 0, budgeted: 0, spent: 0, income: 0, groups: []);
  }
  final groups = <EnvelopeGroup>[];
  for (final g in m['categoryGroups'] as List? ?? const []) {
    if (g is! Map || g['is_income'] == true || g['hidden'] == true) continue;
    final envelopes = [
      for (final c in g['categories'] as List? ?? const [])
        if (c is Map && c['hidden'] != true && c['is_income'] != true)
          Envelope(
            id: '${c['id']}',
            name: '${c['name'] ?? ''}',
            budgeted: _cents(c['budgeted']),
            spent: -_cents(c['spent']),
            balance: _cents(c['balance']),
          ),
    ];
    if (envelopes.isNotEmpty) groups.add(EnvelopeGroup('${g['name'] ?? ''}', envelopes));
  }
  return BudgetMonth(
    month: '${m['month'] ?? ''}',
    toBudget: _cents(m['toBudget']),
    budgeted: _cents(m['totalBudgeted']).abs(),
    spent: -_cents(m['totalSpent']),
    income: _cents(m['totalIncome']),
    groups: groups,
  );
}

/// Payee names by id; transfers read "→ account".
Map<String, String> parsePayees(Object? json) {
  final list = unwrapData(json);
  if (list is! List) return const {};
  return {
    for (final p in list)
      if (p is Map && p['id'] is String)
        p['id'] as String: p['transfer_acct'] != null ? '→ ${p['name']}' : '${p['name'] ?? ''}',
  };
}

/// Operations of one account. Split transactions come as their parent.
List<Operation> parseOperations(
  Object? json, {
  Map<String, String> payees = const {},
  Map<String, String> categories = const {},
}) {
  final list = unwrapData(json);
  if (list is! List) return const [];
  return [
    for (final t in list)
      if (t is Map && t['id'] != null && t['is_child'] != true && t['tombstone'] != true)
        if (DateTime.tryParse('${t['date']}') case final date?)
          Operation(
            id: '${t['id']}',
            accountId: '${t['account'] ?? ''}',
            date: date,
            amount: _cents(t['amount']),
            payee: payees[t['payee']] ?? _orNull(t['payee_name'] ?? t['imported_payee']) ?? '—',
            category: t['is_parent'] == true ? 'Ventilée' : categories[t['category']],
            notes: _orNull(t['notes']),
          ),
  ];
}

String? _orNull(Object? v) {
  final text = v?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

/// "2026-11" for a date.
String monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// "2026-11-17" for a date.
String dayKey(DateTime d) => '${monthKey(d)}-${d.day.toString().padLeft(2, '0')}';

const _months = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

/// "Novembre 2026" for "2026-11".
String monthTitle(String key) {
  final parts = key.split('-');
  final m = parts.length == 2 ? int.tryParse(parts[1]) : null;
  if (m == null || m < 1 || m > 12) return key;
  final name = _months[m - 1];
  return '${name[0].toUpperCase()}${name.substring(1)} ${parts[0]}';
}

/// "1 234,56 €", "−12,00 €" (with [sign], "+12,00 €" too).
String formatEuros(int cents, {bool sign = false}) {
  final negative = cents < 0;
  final abs = cents.abs();
  final units = (abs ~/ 100).toString();
  final grouped = StringBuffer();
  for (var i = 0; i < units.length; i++) {
    if (i > 0 && (units.length - i) % 3 == 0) grouped.write(' ');
    grouped.write(units[i]);
  }
  final prefix = negative ? '−' : (sign && cents > 0 ? '+' : '');
  return '$prefix$grouped,${(abs % 100).toString().padLeft(2, '0')} €';
}

/// Reads "12", "12,5", "12.50", "1 234,56 €": cents, or null.
int? parseEuros(String text) {
  final cleaned = text.replaceAll(RegExp(r'[\s  €]'), '').replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{0,2})?$').hasMatch(cleaned)) return null;
  final value = (double.parse(cleaned) * 100).round();
  return value > 0 ? value : null;
}
