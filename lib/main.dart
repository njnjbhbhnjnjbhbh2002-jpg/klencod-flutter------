
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';

const Color green = Color(0xFF006B50);
const Color darkGreen = Color(0xFF004735);
const Color bg = Color(0xFFF3F7F5);
const Color red = Color(0xFFE65359);
const Color ink = Color(0xFF24332F);
const Color muted = Color(0xFF7B8984);

String money(num value) =>
    '${NumberFormat('#,##0', 'en_US').format(value)} د.ع';

String dateText(String value) {
  try {
    return DateFormat('yyyy/MM/dd').format(DateTime.parse(value));
  } catch (_) {
    return value;
  }
}

String nowDate() => DateTime.now().toIso8601String();

class DebtDb {
  DebtDb._();
  static final DebtDb instance = DebtDb._();
  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'mahal_debts.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE customers(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT NOT NULL DEFAULT '',
            note TEXT NOT NULL DEFAULT '',
            color INTEGER NOT NULL DEFAULT 0,
            createdAt TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE transactions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customerId INTEGER NOT NULL,
            type TEXT NOT NULL,
            amount INTEGER NOT NULL,
            date TEXT NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            FOREIGN KEY(customerId) REFERENCES customers(id)
          )
        ''');
      },
    );
    return _db!;
  }

  Future<List<Map<String, dynamic>>> customers() async {
    final d = await db;
    return d.query('customers', orderBy: 'name COLLATE NOCASE ASC');
  }

  Future<Map<String, dynamic>?> customer(int id) async {
    final d = await db;
    final rows = await d.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> addCustomer({
    required String name,
    required String phone,
    required String note,
    required int color,
  }) async {
    final d = await db;
    return d.insert('customers', {
      'name': name.trim(),
      'phone': phone.trim(),
      'note': note.trim(),
      'color': color,
      'createdAt': nowDate(),
    });
  }

  Future<void> updateCustomer(
    int id, {
    required String name,
    required String phone,
    required String note,
  }) async {
    final d = await db;
    await d.update(
      'customers',
      {'name': name.trim(), 'phone': phone.trim(), 'note': note.trim()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteCustomer(int id) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('transactions', where: 'customerId = ?', whereArgs: [id]);
      await txn.delete('customers', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<int> addTransaction({
    required int customerId,
    required String type,
    required int amount,
    required String date,
    required String note,
  }) async {
    final d = await db;
    return d.insert('transactions', {
      'customerId': customerId,
      'type': type,
      'amount': amount,
      'date': date,
      'note': note.trim(),
    });
  }

  Future<List<Map<String, dynamic>>> transactions(int customerId) async {
    final d = await db;
    return d.query(
      'transactions',
      where: 'customerId = ?',
      whereArgs: [customerId],
      orderBy: 'date DESC, id DESC',
    );
  }

  Future<int> balance(int customerId) async {
    final d = await db;
    final rows = await d.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN type = 'debt' THEN amount ELSE 0 END), 0)
        -
        COALESCE(SUM(CASE WHEN type = 'payment' THEN amount ELSE 0 END), 0)
        AS balance
      FROM transactions WHERE customerId = ?
    ''', [customerId]);
    return ((rows.first['balance'] as num?) ?? 0).toInt();
  }

  Future<Map<String, int>> totals() async {
    final d = await db;
    final customersCount = Sqflite.firstIntValue(
          await d.rawQuery('SELECT COUNT(*) FROM customers'),
        ) ??
        0;
    final rows = await d.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN type = 'debt' THEN amount ELSE 0 END), 0) AS debts,
        COALESCE(SUM(CASE WHEN type = 'payment' THEN amount ELSE 0 END), 0) AS payments
      FROM transactions
    ''');
    final debts = ((rows.first['debts'] as num?) ?? 0).toInt();
    final payments = ((rows.first['payments'] as num?) ?? 0).toInt();
    return {
      'customers': customersCount,
      'debts': debts,
      'payments': payments,
      'balance': debts - payments,
    };
  }

  Future<List<Map<String, dynamic>>> allTransactions() async {
    final d = await db;
    return d.rawQuery('''
      SELECT transactions.*, customers.name AS customerName
      FROM transactions
      INNER JOIN customers ON customers.id = transactions.customerId
      ORDER BY transactions.date DESC, transactions.id DESC
    ''');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DebtDb.instance.db;
  runApp(const MahalDebtsApp());
}

class MahalDebtsApp extends StatelessWidget {
  const MahalDebtsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'سجل ديون المحل',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: green,
          primary: green,
          surface: Colors.white,
        ),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: darkGreen,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF7F9F8),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: green,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int index = 0;
  int refreshKey = 0;

  void refresh() => setState(() => refreshKey++);

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(key: ValueKey('home$refreshKey'), onRefresh: refresh),
      CustomersPage(key: ValueKey('customers$refreshKey'), onRefresh: refresh),
      ActivityPage(key: ValueKey('activity$refreshKey')),
      ReportsPage(key: ValueKey('reports$refreshKey')),
      const SettingsPage(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFDDF3E9),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'الزبائن'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'الحركات'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'التقارير'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'الإعدادات'),
        ],
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  final VoidCallback onRefresh;
  const DashboardPage({super.key, required this.onRefresh});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, int> totals = {};
  List<Map<String, dynamic>> customers = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final t = await DebtDb.instance.totals();
    final c = await DebtDb.instance.customers();
    if (!mounted) return;
    setState(() {
      totals = t;
      customers = c;
      loading = false;
    });
  }

  Future<void> addCustomer() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => const CustomerFormDialog(),
    );
    if (result == true) {
      await load();
      widget.onRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = totals['balance'] ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          children: [
            Text('سجل ديون المحل', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            Text('إدارة حسابات زبائنك بسهولة', style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () async {
              await load();
              widget.onRefresh();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addCustomer,
        backgroundColor: green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('إضافة زبون'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [darkGreen, green],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.account_balance_wallet_outlined, color: Colors.white70),
                            SizedBox(width: 8),
                            Text('إجمالي الديون المتبقية', style: TextStyle(color: Colors.white70)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          money(balance),
                          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            const Icon(Icons.people_alt_outlined, color: Colors.white70, size: 18),
                            const SizedBox(width: 6),
                            Text('${totals['customers'] ?? 0} زبون', style: const TextStyle(color: Colors.white)),
                            const Spacer(),
                            const Icon(Icons.shield_outlined, color: Colors.white70, size: 18),
                            const SizedBox(width: 5),
                            const Text('حفظ محلي', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: SummaryCard(
                          title: 'إجمالي الديون',
                          amount: totals['debts'] ?? 0,
                          icon: Icons.trending_up,
                          color: red,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SummaryCard(
                          title: 'إجمالي التسديدات',
                          amount: totals['payments'] ?? 0,
                          icon: Icons.check_circle_outline,
                          color: green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('أحدث حسابات الزبائن', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ink)),
                      ),
                      TextButton(onPressed: widget.onRefresh, child: const Text('تحديث')),
                    ],
                  ),
                  if (customers.isEmpty)
                    EmptyState(
                      icon: Icons.people_outline,
                      title: 'لا يوجد زبائن بعد',
                      subtitle: 'أضف أول زبون لبدء تسجيل الديون.',
                      buttonText: 'إضافة أول زبون',
                      onPressed: addCustomer,
                    )
                  else
                    ...customers.take(8).map((c) => CustomerTile(
                          customer: c,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CustomerDetailPage(customerId: c['id'] as int),
                              ),
                            );
                            await load();
                            widget.onRefresh();
                          },
                        )),
                ],
              ),
            ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  final String title;
  final int amount;
  final IconData icon;
  final Color color;

  const SummaryCard({
    super.key,
    required this.title,
    required this.amount,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8EFEB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 7),
          FittedBox(
            fi: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(money(amount), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

const List<Color> customerColors = [
  Color(0xFFE75B63),
  Color(0xFF9364D8),
  Color(0xFF3785E8),
  Color(0xFF25A982),
  Color(0xFFE99B30),
  Color(0xFF168A96),
];

class CustomerTile extends StatelessWidget {
  final Map<String, dynamic> customer;
  final VoidCallback onTap;

  const CustomerTile({super.key, required this.customer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorIndex = (customer['color'] as int? ?? 0) % customerColors.length;
    final color = customerColors[colorIndex];
    return FutureBuilder<int>(
      future: DebtDb.instance.balance(customer['id'] as int),
      builder: (context, snapshot) {
        final balance = snapshot.data ?? 0;
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE8EFEB)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            onTap: onTap,
            leading: CircleAvatar(
              backgroundColor: color.withAlpha(30),
              foregroundColor: color,
              child: Text(
                (customer['name'] as String).isNotEmpty
                    ? (customer['name'] as String).substring(0, 1)
                    : '?',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(customer['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, color: ink)),
            subtitle: Text(
              (customer['phone'] as String).isEmpty ? 'لا يوجد رقم هاتف' : customer['phone'] as String,
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(money(balance), style: TextStyle(color: balance > 0 ? red : green, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                const Text('الرصيد المتبقي', style: TextStyle(color: muted, fontSize: 10)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class CustomersPage extends StatefulWidget {
  final VoidCallback onRefresh;
  const CustomersPage({super.key, required this.onRefresh});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  List<Map<String, dynamic>> customers = [];
  String query = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final result = await DebtDb.instance.customers();
    if (mounted) setState(() => customers = result);
  }

  Future<void> add() async {
    final result = await showDialog<bool>(context: context, builder: (_) => const CustomerFormDialog());
    if (result == true) {
      await load();
      widget.onRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = customers.where((c) {
      final name = (c['name'] as String).toLowerCase();
      final phone = (c['phone'] as String).toLowerCase();
      final q = query.toLowerCase().trim();
      return name.contains(q) || phone.contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('الزبائن')),
      floatingActionButton: FloatingActionButton(
        onPressed: add,
        backgroundColor: green,
        foregroundColor: Colors.white,
        child: const Icon(Icons.person_add_alt_1),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (v) => setState(() => query = v),
              decoration: const InputDecoration(
                hintText: 'ابحث باسم الزبون أو رقم الهاتف...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? EmptyState(
                    icon: Icons.person_search_outlined,
                    title: 'لا توجد نتائج',
                    subtitle: 'أضف زبوناً جديداً أو جرّب كلمة بحث أخرى.',
                    buttonText: 'إضافة زبون',
                    onPressed: add,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) => CustomerTile(
                      customer: filtered[i],
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CustomerDetailPage(customerId: filtered[i]['id'] as int),
                          ),
                        );
                        await load();
                        widget.onRefresh();
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class CustomerFormDialog extends StatefulWidget {
  const CustomerFormDialog({super.key});

  @override
  State<CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<CustomerFormDialog> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final phone = TextEditingController();
  final note = TextEditingController();
  int color = DateTime.now().millisecond % customerColors.length;
  bool saving = false;

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate() || saving) return;
    setState(() => saving = true);
    await DebtDb.instance.addCustomer(
      name: name.text,
      phone: phone.text,
      note: note.text,
      color: color,
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة زبون جديد'),
      content: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'اسم الزبون *', prefixIcon: Icon(Icons.person_outline)),
                validator: (v) => v == null || v.trim().isEmpty ? 'أدخل اسم الزبون' : null,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'رقم الهاتف', prefixIcon: Icon(Icons.phone_outlined)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)', prefixIcon: Icon(Icons.notes)),
              ),
              const SizedBox(height: 15),
              const Align(alignment: Alignment.centerRight, child: Text('لون بطاقة الزبون')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                children: List.generate(customerColors.length, (i) {
                  return GestureDetector(
                    onTap: () => setState(() => color = i),
                    child: CircleAvatar(
                      radius: 17,
                      backgroundColor: customerColors[i],
                      child: color == i ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(context, false), child: const Text('إلغاء')),
        ElevatedButton(onPressed: saving ? null : save, child: Text(saving ? 'جارٍ الحفظ...' : 'حفظ الزبون')),
      ],
    );
  }
}

class CustomerDetailPage extends StatefulWidget {
  final int customerId;
  const CustomerDetailPage({super.key, required this.customerId});

  @override
  State<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends State<CustomerDetailPage> {
  Map<String, dynamic>? customer;
  List<Map<String, dynamic>> transactions = [];
  int balance = 0;
  int debts = 0;
  int payments = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final c = await DebtDb.instance.customer(widget.customerId);
    final tx = await DebtDb.instance.transactions(widget.customerId);
    final b = await DebtDb.instance.balance(widget.customerId);
    var d = 0;
    var pay = 0;
    for (final item in tx) {
      if (item['type'] == 'debt') {
        d += (item['amount'] as num).toInt();
      } else {
        pay += (item['amount'] as num).toInt();
      }
    }
    if (!mounted) return;
    setState(() {
      customer = c;
      transactions = tx;
      balance = b;
      debts = d;
      payments = pay;
      loading = false;
    });
  }

  Future<void> addTx(String type) async {
    if (customer == null) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => TransactionFormDialog(
        customerId: widget.customerId,
        customerName: customer!['name'] as String,
        type: type,
        currentBalance: balance,
      ),
    );
    if (result == true) await load();
  }

  Future<void> editCustomer() async {
    if (customer == null) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => EditCustomerDialog(customer: customer!),
    );
    if (result == true) await load();
  }

  Future<void> deleteCustomer() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الزبون؟'),
        content: const Text('سيتم حذف حساب الزبون وجميع حركاته نهائياً من هذا الهاتف.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف نهائياً'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await DebtDb.instance.deleteCustomer(widget.customerId);
      if (mounted) Navigator.pop(context, true);
    }
  }

  Future<void> shareStatement() async {
    if (customer == null) return;
    final buffer = StringBuffer()
      ..writeln('كشف حساب الزبون')
      ..writeln('الاسم: ${customer!['name']}')
      ..writeln('الهاتف: ${customer!['phone']}')
      ..writeln('إجمالي الديون: ${money(debts)}')
      ..writeln('إجمالي التسديدات: ${money(payments)}')
      ..writeln('الرصيد المتبقي: ${money(balance)}')
      ..writeln('')
      ..writeln('الحركات:');
    for (final tx in transactions) {
      buffer.writeln(
        '${dateText(tx['date'] as String)} | ${tx['type'] == 'debt' ? 'دين' : 'تسديد'} | ${money((tx['amount'] as num).toInt())} | ${tx['note']}',
      );
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم نسخ كشف الحساب. يمكنك لصقه ومشاركته.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = customer;
    return Scaffold(
      appBar: AppBar(
        title: Text(c?['name'] as String? ?? 'حساب الزبون'),
        actions: [
          IconButton(onPressed: editCustomer, icon: const Icon(Icons.edit_outlined)),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'share') shareStatement();
              if (v == 'delete') deleteCustomer();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'share', child: Text('نسخ كشف الحساب')),
              PopupMenuItem(value: 'delete', child: Text('حذف الزبون')),
            ],
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : c == null
              ? const Center(child: Text('لم يتم العثور على الزبون'))
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: customerColors[(c['color'] as int? ?? 0) % customerColors.length].withAlpha(35),
                              foregroundColor: customerColors[(c['color'] as int? ?? 0) % customerColors.length],
                              child: Text(
                                (c['name'] as String).substring(0, 1),
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(c['name'] as String, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                            if ((c['phone'] as String).isNotEmpty)
                              Text(c['phone'] as String, style: const TextStyle(color: muted)),
                            const SizedBox(height: 18),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE4F5ED),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                children: [
                                  const Text('الرصيد المتبقي', style: TextStyle(color: green)),
                                  const SizedBox(height: 5),
                                  Text(money(balance), style: const TextStyle(color: darkGreen, fontSize: 24, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(child: SmallTotal(title: 'إجمالي الديون', amount: debts, color: red)),
                                const SizedBox(width: 8),
                                Expanded(child: SmallTotal(title: 'إجمالي التسديدات', amount: payments, color: green)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => addTx('debt'),
                              icon: const Icon(Icons.add_circle_outline),
                              label: const Text('تسجيل دين'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: red),
                              onPressed: () => addTx('payment'),
                              icon: const Icon(Icons.payments_outlined),
                              label: const Text('تسديد الدين'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      const Text('سجل الحركات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      if (transactions.isEmpty)
                        const EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'لا توجد حركات',
                          subtitle: 'ستظهر الديون والتسديدات هنا.',
                        )
                      else
                        ...transactions.map((tx) {
                          final isDebt = tx['type'] == 'debt';
                          return Card(
                            color: Colors.white,
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: const BorderSide(color: Color(0xFFE8EFEB)),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: (isDebt ? red : green).withAlpha(25),
                                foregroundColor: isDebt ? red : green,
                                child: Icon(isDebt ? Icons.add : Icons.remove),
                              ),
                              title: Text(isDebt ? 'دين جديد' : 'تسديد'),
                              subtitle: Text(
                                '${dateText(tx['date'] as String)}${(tx['note'] as String).isNotEmpty ? '\n${tx['note']}' : ''}',
                              ),
                              isThreeLine: (tx['note'] as String).isNotEmpty,
                              trailing: Text(
                                '${isDebt ? '+' : '-'}${money((tx['amount'] as num).toInt())}',
                                style: TextStyle(color: isDebt ? red : green, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}

class SmallTotal extends StatelessWidget {
  final String title;
  final int amount;
  final Color color;
  const SmallTotal({super.key, required this.title, required this.amount, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: muted, fontSize: 11)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(money(amount), style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class TransactionFormDialog extends StatefulWidget {
  final int customerId;
  final String customerName;
  final String type;
  final int currentBalance;

  const TransactionFormDialog({
    super.key,
    required this.customerId,
    required this.customerName,
    required this.type,
    required this.currentBalance,
  });

  @override
  State<TransactionFormDialog> createState() => _TransactionFormDialogState();
}

class _TransactionFormDialogState extends State<TransactionFormDialog> {
  final formKey = GlobalKey<FormState>();
  final amount = TextEditingController();
  final note = TextEditingController();
  DateTime date = DateTime.now();
  bool saving = false;

  bool get isDebt => widget.type == 'debt';

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> chooseDate() async {
    final result = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'اختر تاريخ العملية',
    );
    if (result != null) setState(() => date = result);
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate() || saving) return;
    final value = int.tryParse(amount.text.replaceAll(',', '').trim());
    if (value == null || value <= 0) return;
    if (!isDebt && value > widget.currentBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('مبلغ التسديد أكبر من الدين المتبقي.')),
      );
      return;
    }
    setState(() => saving = true);
    await DebtDb.instance.addTransaction(
      customerId: widget.customerId,
      type: widget.type,
      amount: value,
      date: date.toIso8601String(),
      note: note.text,
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isDebt ? 'تسجيل دين جديد' : 'تسجيل تسديد'),
      content: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.customerName, style: const TextStyle(color: green, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (!isDebt)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('الرصيد الحالي: ${money(widget.currentBalance)}', style: const TextStyle(color: muted)),
                ),
              TextFormField(
                controller: amount,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'المبلغ بالدينار العراقي', prefixIcon: Icon(Icons.payments_outlined)),
                validator: (v) {
                  final n = int.tryParse((v ?? '').replaceAll(',', ''));
                  if (n == null || n <= 0) return 'أدخل مبلغاً صحيحاً';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: chooseDate,
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text('التاريخ: ${DateFormat('yyyy/MM/dd').format(date)}'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات أو تفاصيل المشتريات',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(context, false), child: const Text('إلغاء')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: isDebt ? green : red),
          onPressed: saving ? null : save,
          child: Text(saving ? 'جارٍ الحفظ...' : (isDebt ? 'حفظ الدين' : 'حفظ التسديد')),
        ),
      ],
    );
  }
}

class EditCustomerDialog extends StatefulWidget {
  final Map<String, dynamic> customer;
  const EditCustomerDialog({super.key, required this.customer});

  @override
  State<EditCustomerDialog> createState() => _EditCustomerDialogState();
}

class _EditCustomerDialogState extends State<EditCustomerDialog> {
  late final TextEditingController name;
  late final TextEditingController phone;
  late final TextEditingController note;
  final formKey = GlobalKey<FormState>();
  bool saving = false;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.customer['name'] as String);
    phone = TextEditingController(text: widget.customer['phone'] as String);
    note = TextEditingController(text: widget.customer['note'] as String);
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);
    await DebtDb.instance.updateCustomer(
      widget.customer['id'] as int,
      name: name.text,
      phone: phone.text,
      note: note.text,
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تعديل بيانات الزبون'),
      content: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                decoration: const InputDecoration(labelText: 'الاسم'),
                validator: (v) => v == null || v.trim().isEmpty ? 'الاسم مطلوب' : null,
              ),
              const SizedBox(height: 10),
              TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
              const SizedBox(height: 10),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظات'), maxLines: 2),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        ElevatedButton(onPressed: saving ? null : save, child: const Text('حفظ التعديلات')),
      ],
    );
  }
}

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  List<Map<String, dynamic>> transactions = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final result = await DebtDb.instance.allTransactions();
    if (mounted) setState(() {
      transactions = result;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سجل الحركات')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : transactions.isEmpty
              ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'لا توجد حركات', subtitle: 'ستظهر هنا جميع الديون والتسديدات.')
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: transactions.length,
                    itemBuilder: (context, i) {
                      final tx = transactions[i];
                      final debt = tx['type'] == 'debt';
                      return Card(
                        color: Colors.white,
                        elevation: 0,
                        child: ListTile(
                          leading: Icon(debt ? Icons.add_circle_outline : Icons.check_circle_outline, color: debt ? red : green),
                          title: Text(tx['customerName'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${debt ? 'دين' : 'تسديد'} • ${dateText(tx['date'] as String)}\n${tx['note']}'),
                          isThreeLine: true,
                          trailing: Text(
                            '${debt ? '+' : '-'}${money((tx['amount'] as num).toInt())}',
                            style: TextStyle(color: debt ? red : green, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  Map<String, int> totals = {};
  List<Map<String, dynamic>> customers = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final t = await DebtDb.instance.totals();
    final c = await DebtDb.instance.customers();
    if (mounted) setState(() {
      totals = t;
      customers = c;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('التقارير')),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: darkGreen, borderRadius: BorderRadius.circular(22)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('الرصيد الإجمالي المتبقي', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  Text(money(totals['balance'] ?? 0), style: const TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SummaryCard(title: 'إجمالي الديون المسجلة', amount: totals['debts'] ?? 0, icon: Icons.trending_up, color: red),
            const SizedBox(height: 10),
            SummaryCard(title: 'إجمالي التسديدات المسجلة', amount: totals['payments'] ?? 0, icon: Icons.check_circle_outline, color: green),
            const SizedBox(height: 20),
            Text('أعلى الأرصدة المتبقية', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ...customers.map((c) => CustomerTile(
                  customer: c,
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailPage(customerId: c['id'] as int)));
                    await load();
                  },
                )),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [darkGreen, green]),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Column(
              children: [
                Icon(Icons.storefront, size: 48, color: Colors.white),
                SizedBox(height: 10),
                Text('سجل ديون المحل', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.bold)),
                SizedBox(height: 5),
                Text('إدارة ديون زبائنك بكل سهولة', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SettingsTile(icon: Icons.offline_bolt_outlined, title: 'العمل دون إنترنت', subtitle: 'البيانات محفوظة محلياً على الهاتف'),
          const SettingsTile(icon: Icons.currency_exchange, title: 'العملة', subtitle: 'الدينار العراقي (د.ع)'),
          const SettingsTile(icon: Icons.storage_outlined, title: 'قاعدة البيانات', subtitle: 'SQLite محلية'),
          const SettingsTile(icon: Icons.info_outline, title: 'حول التطبيق', subtitle: 'سجل ديون المحل • الإصدار 1.0.0'),
          const SizedBox(height: 12),
          const Text(
            'تنبيه: هذه النسخة تحفظ البيانات داخل التطبيق على هذا الهاتف. احرص على إنشاء نسخة احتياطية قبل حذف التطبيق أو تغيير الهاتف.',
            style: TextStyle(color: muted, fontSize: 12, height: 1.7),
          ),
        ],
      ),
    );
  }
}

class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const SettingsTile({super.key, required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFE4F5ED),
          foregroundColor: green,
          child: Icon(icon),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(color: muted, fontSize: 12)),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? buttonText;
  final VoidCallback? onPressed;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.buttonText,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 35, horizontal: 20),
      child: Column(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: const BoxDecoration(color: Color(0xFFE4F5ED), shape: BoxShape.circle),
            child: Icon(icon, size: 34, color: green),
          ),
          const SizedBox(height: 15),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          const SizedBox(height: 7),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: muted, height: 1.5)),
          if (buttonText != null && onPressed != null) ...[
            const SizedBox(height: 15),
            ElevatedButton(onPressed: onPressed, child: Text(buttonText!)),
          ],
        ],
      ),
    );
  }
}