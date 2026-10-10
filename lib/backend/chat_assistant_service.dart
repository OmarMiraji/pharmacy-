import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'assistant_config.dart';
import 'firestore_collections.dart';
import 'models.dart';
import 'pharmacy.dart';
import 'subscription_service.dart';
import 'tenant_context.dart';
import 'user_profile.dart';

class ChatTurn {
  const ChatTurn({required this.fromUser, required this.text});

  final bool fromUser;
  final String text;
}

class ChatAssistantService {
  ChatAssistantService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<String> reply({
    required String question,
    required List<ChatTurn> history,
    bool supportMode = false,
  }) async {
    final trimmed = question.trim();
    if (supportMode) {
      if (!TenantContext.instance.isSuperAdmin) {
        return ChatAssistantService.looksSwahili(trimmed)
            ? 'Msaidizi huyu ni wa console ya mfumo tu.'
            : 'This assistant is only for the system console.';
      }
      if (trimmed.isEmpty) {
        return 'Ask about shops, licenses, logins, or customer pharmacies.';
      }
      final live = await _loadSupportLive();
      try {
        return await _askGemini(question: trimmed, history: history, context: live.prompt);
      } catch (_) {
        return live.answerLocally(trimmed);
      }
    }
    if (TenantContext.instance.isSuperAdmin) {
      return ChatAssistantService.looksSwahili(trimmed)
          ? 'Data ya duka haipo hapa. Tumia msaidizi wa mfumo kwa shops na logins.'
          : 'Shop data is not available here. Use the system assistant for shops and logins.';
    }
    if (trimmed.isEmpty) {
      return 'Ask about stock, this shop’s staff, bills, expiry, or sales.';
    }
    final live = await _loadLive();
    try {
      return await _askGemini(question: trimmed, history: history, context: live.prompt);
    } catch (_) {
      return live.answerLocally(trimmed);
    }
  }

  Future<_ShopLive> _loadLive() async {
    final tenant = TenantContext.instance;
    final shopId = (tenant.pharmacyId ?? '').trim();
    final shop = (tenant.pharmacyName ?? 'this pharmacy').trim();
    if (shopId.isEmpty) {
      return _ShopLive(shop: shop, prompt: 'No shop is linked.', medicines: const [], batches: const [], bills: const []);
    }

    List<Medicine> medicines = const [];
    List<MedicineBatch> batches = const [];
    var bills = <_Bill>[];
    var purchaseLines = <String>[];
    var todaySales = 0;
    var todayTotal = 0;
    var purchaseTotal = 0;

    try {
      final results = await Future.wait([
        tenant.scoped(_firestore.collection(FirestoreCollections.medicines)).get(),
        tenant.scoped(_firestore.collection(FirestoreCollections.medicineBatches)).get(),
        tenant.scoped(_firestore.collection(FirestoreCollections.sales)).get(),
        tenant.scoped(_firestore.collection(FirestoreCollections.purchases)).get(),
      ]);
      medicines = results[0].docs
          .map((doc) {
            try {
              return Medicine.fromFirestore(doc);
            } catch (_) {
              return null;
            }
          })
          .whereType<Medicine>()
          .toList();
      batches = results[1].docs
          .map((doc) {
            try {
              return MedicineBatch.fromFirestore(doc);
            } catch (_) {
              return null;
            }
          })
          .whereType<MedicineBatch>()
          .toList();

      final now = DateTime.now();
      final sales = [...results[2].docs.where((doc) {
        final status = (doc.data()['status'] as String?) ?? 'completed';
        return status != 'voided' && status != 'refunded';
      })]..sort((a, b) {
          final left = _asDate(a.data()['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
          final right = _asDate(b.data()['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
          return right.compareTo(left);
        });
      for (final doc in sales) {
        final data = doc.data();
        final created = _asDate(data['createdAt']);
        final total = (data['totalMinor'] as num?)?.toInt() ?? 0;
        if (created != null && created.year == now.year && created.month == now.month && created.day == now.day) {
          todaySales++;
          todayTotal += total;
        }
      }
      bills = sales.take(25).map((doc) {
        final data = doc.data();
        return _Bill(
          receipt: (data['receiptNumber'] as String?)?.trim().isNotEmpty == true
              ? data['receiptNumber'] as String
              : doc.id,
          total: (data['totalMinor'] as num?)?.toInt() ?? 0,
          at: _asDate(data['createdAt']),
        );
      }).toList();

      for (final doc in results[3].docs) {
        final data = doc.data();
        final total = (data['totalMinor'] as num?)?.toInt() ?? 0;
        purchaseTotal += total;
        final invoice = (data['invoiceNumber'] as String?)?.trim();
        purchaseLines.add('${invoice == null || invoice.isEmpty ? doc.id : invoice}: ${_money(total)} (${data['status'] ?? 'received'})');
      }
    } catch (_) {
      // Live lists stay empty; Gemini still gets shop identity.
    }

    var staff = <UserProfile>[];
    try {
      final usersSnap = await tenant.scoped(_firestore.collection(FirestoreCollections.users)).get();
      staff = usersSnap.docs
          .map((doc) {
            try {
              return UserProfile.fromFirestore(doc);
            } catch (_) {
              return null;
            }
          })
          .whereType<UserProfile>()
          .where((user) => !user.isSuperAdmin && (user.pharmacyId ?? '').trim() == shopId)
          .toList();
    } catch (_) {}

    final names = {for (final medicine in medicines) medicine.id: medicine.name};
    final active = medicines.where((medicine) => medicine.isActive).toList();
    final stockUnits = active.fold<int>(0, (total, medicine) => total + medicine.quantityOnHand);
    final low = active.where((medicine) => medicine.quantityOnHand <= medicine.reorderLevel).toList();
    final out = active.where((medicine) => medicine.quantityOnHand <= 0).toList();

    final expiryByMonth = <String, List<String>>{};
    var expiredQty = 0;
    var expiredNames = 0;
    final now = DateTime.now();
    for (final batch in batches) {
      if (!batch.isActive || batch.quantityOnHand <= 0) continue;
      final expiry = batch.expiryDate.toDate();
      final label = '${_monthName(expiry.month)} ${expiry.year}';
      final medicineName = names[batch.medicineId] ?? batch.medicineId;
      expiryByMonth.putIfAbsent(label, () => []).add('$medicineName batch ${batch.batchNumber}: ${batch.quantityOnHand} (exp ${expiry.day}/${expiry.month}/${expiry.year})');
      if (expiry.isBefore(DateTime(now.year, now.month, now.day))) {
        expiredQty += batch.quantityOnHand;
        expiredNames++;
      }
    }

    final buffer = StringBuffer();
    buffer.writeln('You are the PharmSpecio shop assistant for "$shop".');
    buffer.writeln('LANGUAGE: Reply in the SAME language as the latest user question.');
    buffer.writeln('If they write English, reply only in English. If they write Kiswahili, reply only in Kiswahili. Never mix. Never default to Kiswahili for an English question.');
    buffer.writeln('Short, clear, with real numbers from LIVE DATA only.');
    buffer.writeln('If a medicine is not in LIVE DATA, say you do not see it in this shop. Never invent quantities, bills, or expiry dates.');
    buffer.writeln('Never list staff from other pharmacies. STAFF OF THIS SHOP only.');
    buffer.writeln('Do not print API keys. Do not talk about Super Admin.');
    buffer.writeln('Money is Tanzanian shillings. "Bili" = sales receipts. Purchases = supplier invoices.');
    buffer.writeln('');
    buffer.writeln('LIVE DATA');
    buffer.writeln('Shop: $shop');
    buffer.writeln('Medicines: ${active.length}  |  Units on hand: $stockUnits  |  Low stock: ${low.length}  |  Out of stock: ${out.length}');
    buffer.writeln('Sales today: $todaySales bills, ${_money(todayTotal)}');
    buffer.writeln('Purchase invoices on file: ${purchaseLines.length}, total ${_money(purchaseTotal)}');
    buffer.writeln('Expired batches still showing qty: $expiredNames lines, $expiredQty units');
    buffer.writeln('Staff of this shop only: ${staff.length}');
    buffer.writeln('');
    buffer.writeln('STAFF OF THIS SHOP (not other Firebase users)');
    if (staff.isEmpty) {
      buffer.writeln('No staff logins linked to this pharmacy.');
    } else {
      for (final user in staff) {
        final name = user.displayName.trim().isEmpty ? user.email : user.displayName;
        buffer.writeln('- $name | ${user.email} | ${user.role} | ${user.isActive ? 'active' : 'disabled'}');
      }
    }
    buffer.writeln('');
    buffer.writeln('STOCK (name | left | reorder | sell price)');
    final stockLines = [...active]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    for (final medicine in stockLines.take(180)) {
      buffer.writeln('- ${medicine.name} | ${medicine.quantityOnHand} ${medicine.unit} | reorder ${medicine.reorderLevel} | ${_money(medicine.sellingPriceMinor)}');
    }
    if (stockLines.length > 180) buffer.writeln('… and ${stockLines.length - 180} more medicines');
    if (low.isNotEmpty) {
      buffer.writeln('LOW STOCK');
      for (final medicine in low.take(40)) {
        buffer.writeln('- ${medicine.name}: ${medicine.quantityOnHand} left (reorder ${medicine.reorderLevel})');
      }
    }
    buffer.writeln('');
    buffer.writeln('EXPIRY BY MONTH (active batches with qty > 0)');
    final months = expiryByMonth.keys.toList()..sort();
    for (final month in months) {
      final lines = expiryByMonth[month]!;
      buffer.writeln('$month: ${lines.length} batches');
      for (final line in lines.take(40)) {
        buffer.writeln('  $line');
      }
      if (lines.length > 40) buffer.writeln('  … ${lines.length - 40} more');
    }
    buffer.writeln('');
    buffer.writeln('RECENT SALES BILLS');
    if (bills.isEmpty) {
      buffer.writeln('No sales bills loaded.');
    } else {
      for (final bill in bills) {
        buffer.writeln('- ${bill.receipt} | ${_fmtDate(bill.at)} | ${_money(bill.total)}');
      }
    }
    buffer.writeln('');
    buffer.writeln('PURCHASE / SUPPLIER BILLS');
    if (purchaseLines.isEmpty) {
      buffer.writeln('No purchase invoices loaded.');
    } else {
      for (final line in purchaseLines.take(25)) {
        buffer.writeln('- $line');
      }
    }
    return _ShopLive(
      shop: shop,
      prompt: buffer.toString(),
      medicines: active,
      batches: batches,
      bills: bills,
      names: names,
      staff: staff,
    );
  }

  Future<_SupportLive> _loadSupportLive() async {
    final shops = <PharmacyRecord>[];
    final users = <UserProfile>[];
    try {
      final results = await Future.wait([
        _firestore.collection(FirestoreCollections.pharmacies).get(),
        _firestore.collection(FirestoreCollections.users).get(),
      ]);
      shops.addAll(
        results[0].docs.map((doc) {
          try {
            return PharmacyRecord.fromDoc(doc);
          } catch (_) {
            return null;
          }
        }).whereType<PharmacyRecord>(),
      );
      users.addAll(
        results[1].docs.map((doc) {
          try {
            return UserProfile.fromFirestore(doc);
          } catch (_) {
            return null;
          }
        }).whereType<UserProfile>(),
      );
    } catch (_) {}

    final shopNames = {for (final shop in shops) shop.id: shop.name};
    final staff = users.where((user) => !user.isSuperAdmin).toList();
    final buffer = StringBuffer();
    buffer.writeln('You are the PharmSpecio system-console assistant for the platform owner only.');
    buffer.writeln('LANGUAGE: Reply in the SAME language as the latest user question.');
    buffer.writeln('English question → English only. Kiswahili question → Kiswahili only. Never mix. Never default to Kiswahili for English.');
    buffer.writeln('This console: Customers, Shops, Licenses, Logins, Support data, App updates, Password.');
    buffer.writeln('Do NOT answer shop POS questions (how to sell, stock left, expiry of medicines). Direct those to the shop login.');
    buffer.writeln('When asked for staff, group them by shop. You may list all shop logins because this is the system owner.');
    buffer.writeln('Do not print API keys.');
    buffer.writeln('');
    buffer.writeln('SHOPS');
    buffer.writeln('Count: ${shops.length}');
    for (final shop in shops.take(40)) {
      final license = SubscriptionService.licenseFromPharmacy(shop);
      final access = license.isBlocked
          ? 'locked'
          : license.isReadOnly
              ? 'view-only'
              : license.isTrial
                  ? 'trial'
                  : 'paid';
      buffer.writeln('- ${shop.name} | $access | ends ${license.licenseEndsAt} | owner ${shop.ownerEmail ?? '—'}');
    }
    buffer.writeln('');
    buffer.writeln('SHOP LOGINS (not Super Admin)');
    buffer.writeln('Count: ${staff.length}');
    for (final user in staff.take(80)) {
      final shop = shopNames[user.pharmacyId ?? ''] ?? ((user.pharmacyId ?? '').trim().isEmpty ? 'no shop linked' : 'unknown shop');
      final name = user.displayName.trim().isEmpty ? user.email : user.displayName;
      buffer.writeln('- $name | ${user.email} | ${user.role} | $shop | ${user.isActive ? 'active' : 'disabled'}');
    }
    return _SupportLive(prompt: buffer.toString(), shops: shops, staff: staff, shopNames: shopNames);
  }

  Future<String> _askGemini({
    required String question,
    required List<ChatTurn> history,
    required String context,
  }) async {
    if (!AssistantConfig.hasGeminiKey) {
      throw StateError('Assistant key is not configured.');
    }
    final language = looksSwahili(question) ? 'Kiswahili' : 'English';
    final contents = <Map<String, dynamic>>[
      for (final turn in history.where((turn) => turn.text.trim().isNotEmpty).take(8))
        {
          'role': turn.fromUser ? 'user' : 'model',
          'parts': [
            {'text': turn.text},
          ],
        },
      {
        'role': 'user',
        'parts': [
          {'text': question},
        ],
      },
    ];
    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': '$context\n\nReply now in $language only. The user wrote: "$question"'},
        ],
      },
      'contents': contents,
    });

    Object? lastError;
    for (final model in [AssistantConfig.model, AssistantConfig.fallbackModel]) {
      try {
        return await _postGemini(model: model, body: body);
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? StateError('Assistant is unavailable.');
  }

  Future<String> _postGemini({required String model, required String body}) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=${AssistantConfig.geminiKey}',
    );
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri).timeout(const Duration(seconds: 20));
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(body));
      final response = await request.close().timeout(const Duration(seconds: 45));
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Assistant is busy. Try again.');
      }
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        final candidates = decoded['candidates'];
        if (candidates is List && candidates.isNotEmpty) {
          final content = (candidates.first as Map)['content'];
          if (content is Map) {
            final parts = content['parts'];
            if (parts is List && parts.isNotEmpty) {
              final part = parts.first;
              if (part is Map && part['text'] is String) {
                return (part['text'] as String).trim();
              }
            }
          }
        }
      }
      throw StateError('Empty assistant reply.');
    } finally {
      client.close(force: true);
    }
  }

  static DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String _fmtDate(DateTime? date) {
    if (date == null) return '—';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  static String _money(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer(value < 0 ? '-TZS ' : 'TZS ');
    for (var i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      final left = digits.length - i - 1;
      if (left > 0 && left % 3 == 0) buffer.write(',');
    }
    return buffer.toString();
  }

  static String _monthName(int month) {
    const names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    if (month < 1 || month > 12) return 'Month $month';
    return names[month - 1];
  }

  static bool looksSwahili(String text) {
    final q = text.toLowerCase();
    const markers = [
      'ngapi',
      'zimebaki',
      'dawa',
      'mwezi',
      'orodha',
      'taja',
      'nini',
      'vipi',
      'tafadhali',
      'nataka',
      'nisaidie',
      'kwanini',
      'mbona',
      'wafanyakazi',
      'mfanyakazi',
      'majina',
      'risiti',
      'mauzo',
      'ninahitaji',
      'naomba',
      'gani',
      'kwenye',
      'duka',
      'uliza',
      'eleza',
      'niambie',
      'zinakwisha',
      'zimekwisha',
      'watumiaji',
      'hisa',
      'je ',
      'naomba',
      'tafadhali',
    ];
    return markers.any(q.contains);
  }
}

class _Bill {
  const _Bill({required this.receipt, required this.total, this.at});

  final String receipt;
  final int total;
  final DateTime? at;
}

class _ShopLive {
  const _ShopLive({
    required this.shop,
    required this.prompt,
    required this.medicines,
    required this.batches,
    required this.bills,
    this.names = const {},
    this.staff = const [],
  });

  final String shop;
  final String prompt;
  final List<Medicine> medicines;
  final List<MedicineBatch> batches;
  final List<_Bill> bills;
  final Map<String, String> names;
  final List<UserProfile> staff;

  String answerLocally(String question) {
    final q = question.toLowerCase();
    final sw = ChatAssistantService.looksSwahili(question);
    if (q.contains('staff') || q.contains('mfanyakazi') || q.contains('wafanyakazi') || q.contains('login') || q.contains('watumiaji')) {
      if (staff.isEmpty) {
        return sw ? 'Hakuna staff waliounganishwa na duka hili.' : 'No staff are linked to this shop.';
      }
      final lines = staff.map((user) {
        final name = user.displayName.trim().isEmpty ? user.email : user.displayName;
        return '• $name — ${user.role} — ${user.email}${user.isActive ? '' : ' (disabled)'}';
      });
      return sw ? 'Staff wa duka $shop tu:\n${lines.join('\n')}' : 'Staff in $shop only:\n${lines.join('\n')}';
    }
    final month = _parseMonth(q);
    if (month != null || q.contains('expir') || q.contains('muda wa') || q.contains('zinakwisha')) {
      return _expiryAnswer(month, sw);
    }
    if (q.contains('bili') || q.contains('bill') || q.contains('receipt') || q.contains('risiti')) {
      if (bills.isEmpty) {
        return sw ? 'Sijaona bili za mauzo kwenye duka hili bado.' : 'I do not see sales bills for this shop yet.';
      }
      final lines = bills.take(12).map((bill) => '• ${bill.receipt} — ${ChatAssistantService._fmtDate(bill.at)} — ${ChatAssistantService._money(bill.total)}');
      return sw ? 'Bili za hivi karibuni:\n${lines.join('\n')}' : 'Recent bills:\n${lines.join('\n')}';
    }
    final match = medicines.where((medicine) {
      final name = medicine.name.toLowerCase();
      final generic = (medicine.genericName ?? '').toLowerCase();
      return q.contains(name) || (generic.isNotEmpty && q.contains(generic)) || name.split(' ').any((part) => part.length > 3 && q.contains(part));
    }).toList();
    if (match.isNotEmpty) {
      return match.take(8).map((medicine) {
        return sw
            ? '${medicine.name}: zimebaki ${medicine.quantityOnHand} ${medicine.unit} (reorder ${medicine.reorderLevel}, bei ${ChatAssistantService._money(medicine.sellingPriceMinor)}).'
            : '${medicine.name}: ${medicine.quantityOnHand} ${medicine.unit} left (reorder ${medicine.reorderLevel}, price ${ChatAssistantService._money(medicine.sellingPriceMinor)}).';
      }).join('\n');
    }
    if (q.contains('stock') || q.contains('imebaki') || q.contains('ngapi') || q.contains('hisa')) {
      final units = medicines.fold<int>(0, (total, medicine) => total + medicine.quantityOnHand);
      final low = medicines.where((medicine) => medicine.quantityOnHand <= medicine.reorderLevel).length;
      return sw
          ? 'Duka $shop: dawa ${medicines.length}, units $units, low stock $low. Uliza jina la dawa ili nikuambie zimebaki ngapi.'
          : '$shop: ${medicines.length} medicines, $units units, $low low stock. Ask a medicine name for remaining quantity.';
    }
    return sw
        ? 'Uliza jina la dawa, mwezi wa expiry, au bili. Nitasoma data ya duka hili.'
        : 'Ask a medicine name, an expiry month, or about bills. I read this shop’s data.';
  }

  String _expiryAnswer(int? month, bool sw) {
    final now = DateTime.now();
    final targetMonth = month ?? now.month;
    final targetYear = month != null && month < now.month - 6 ? now.year + 1 : now.year;
    var qty = 0;
    var count = 0;
    final lines = <String>[];
    for (final batch in batches) {
      if (!batch.isActive || batch.quantityOnHand <= 0) continue;
      final expiry = batch.expiryDate.toDate();
      if (expiry.month != targetMonth) continue;
      if (month == null && expiry.year != now.year) continue;
      if (month != null && expiry.year != targetYear && expiry.year != now.year) continue;
      count++;
      qty += batch.quantityOnHand;
      if (lines.length < 12) {
        final name = names[batch.medicineId] ?? 'Medicine';
        lines.add('• $name (${batch.batchNumber}): ${batch.quantityOnHand} — ${expiry.day}/${expiry.month}/${expiry.year}');
      }
    }
    final label = ChatAssistantService._monthName(targetMonth);
    if (count == 0) {
      return sw ? 'Hakuna batch zenye expiry $label kwenye stock ya sasa.' : 'No batches expire in $label in current stock.';
    }
    return sw ? '$label: $count batch, units $qty.\n${lines.join('\n')}' : '$label: $count batches, $qty units.\n${lines.join('\n')}';
  }

  static int? _parseMonth(String q) {
    const map = {
      'januari': 1,
      'january': 1,
      'februari': 2,
      'february': 2,
      'machi': 3,
      'march': 3,
      'aprili': 4,
      'april': 4,
      'mei': 5,
      'may': 5,
      'juni': 6,
      'june': 6,
      'julai': 7,
      'july': 7,
      'agosti': 8,
      'august': 8,
      'septemba': 9,
      'september': 9,
      'oktoba': 10,
      'october': 10,
      'novemba': 11,
      'november': 11,
      'desemba': 12,
      'december': 12,
    };
    for (final entry in map.entries) {
      if (q.contains(entry.key)) return entry.value;
    }
    if (q.contains('mwezi huu') || q.contains('this month')) return DateTime.now().month;
    return null;
  }
}

class _SupportLive {
  const _SupportLive({
    required this.prompt,
    required this.shops,
    required this.staff,
    required this.shopNames,
  });

  final String prompt;
  final List<PharmacyRecord> shops;
  final List<UserProfile> staff;
  final Map<String, String> shopNames;

  String answerLocally(String question) {
    final q = question.toLowerCase();
    final sw = ChatAssistantService.looksSwahili(question);
    if (q.contains('sale') || q.contains('stock') || q.contains('expir') || q.contains('mauzo') || q.contains('dawa')) {
      return sw
          ? 'Mauzo na stock si kazi ya console hii. Ingia kwenye duka husika. Hapa ni shops, licenses, na logins.'
          : 'Sales and stock are not in this console. Sign in to the shop. Here you manage shops, licenses, and logins.';
    }
    if (q.contains('staff') || q.contains('login') || q.contains('wafanyakazi') || q.contains('watumiaji')) {
      if (staff.isEmpty) return sw ? 'Hakuna shop logins.' : 'There are no shop logins.';
      final lines = staff.take(30).map((user) {
        final name = user.displayName.trim().isEmpty ? user.email : user.displayName;
        final shop = shopNames[user.pharmacyId ?? ''] ?? 'no shop';
        return '• $name — ${user.role} — $shop';
      });
      return sw ? 'Logins za maduka:\n${lines.join('\n')}' : 'Shop logins:\n${lines.join('\n')}';
    }
    if (shops.isEmpty) {
      return sw ? 'Hakuna shops bado. Fungua Shops kuunda pharmacy.' : 'No shops yet. Open Shops to create a pharmacy.';
    }
    return sw ? 'Maduka ${shops.length}. Fungua Shops, Licenses, au Logins.' : '${shops.length} shops. Open Shops, Licenses, or Logins.';
  }
}
