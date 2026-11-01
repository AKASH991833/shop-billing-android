import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shop_billing/data.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tmp = await Directory.systemTemp.createTemp('shopdb_lock');
    await databaseFactoryFfi.setDatabasesPath(tmp.path);
  });

  test('PBKDF2 vector matches the desktop/Python reference exactly (hash compatibility)', () {
    // Computed with hashlib.pbkdf2_hmac - the same function the desktop uses.
    expect(
        AppDb.pbkdf2Hex('correct horse battery',
            '010203040506070809000a0b0c0d0e0f10', 200000),
        'ba1ef4b366443af68e5bcb27afad382743989d94dbe3cf282d2c2433ceb2b192');
  });

  test('set, verify, wrong-password, min length, remove - hash only stored', () async {
    expect(await AppDb.hasPassword(), isFalse);
    expect(() => AppDb.setPassword('short'), throwsArgumentError);
    await AppDb.setPassword('shop-secret-1');
    expect(await AppDb.hasPassword(), isTrue);
    expect(await AppDb.verifyPassword('shop-secret-1'), isTrue);
    expect(await AppDb.verifyPassword('wrong-password'), isFalse);
    final stored = (await AppDb.setting('password_hash'))!;
    expect(stored.startsWith('v2\$'), isTrue);
    expect(stored.contains('shop-secret-1'), isFalse,
        reason: 'only the salted hash is stored, never the password');
    await AppDb.removePassword();
    expect(await AppDb.hasPassword(), isFalse);
    expect(await AppDb.verifyPassword('anything'), isTrue,
        reason: 'no password set means the app opens freely');
  });

  test('a verified restore clears the unlocked session so a restored password re-gates', () async {
    await AppDb.setPassword('gate-check-9');
    final r = await AppDb.backupNow();
    await AppDb.removePassword();
    AppDb.sessionUnlocked = true; // simulate an unlocked session
    final rr = await AppDb.restoreBackup(r['path'] as String);
    expect(rr['verified'], isTrue);
    expect(AppDb.sessionUnlocked, isFalse,
        reason: 'restoring while unlocked must not bypass the gate');
    expect(await AppDb.hasPassword(), isTrue,
        reason: 'the backup carried a password hash');
    await AppDb.removePassword();
  });
}
