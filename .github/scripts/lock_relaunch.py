"""Native OS-level lock checks, run CONCURRENTLY while the smoke suite's lock
test sits in its native window (app alive, unlocked on Home, password
persisted). Everything here is native adb - no Flutter engine involvement -
and NOTHING kills the app process: force-stop/am kill would kill the test
isolate too. A true process-death cold start is therefore out of scope by
design and stays an explicitly unverified path.

  0. persistence: pull databases/shop.db via run-as (debug build), verify the
     password_hash row on the HOST with python's sqlite3 (filename verified
     against lib/data.dart: getDatabasesPath() + 'shop.db')
  1. HOME then relaunch -> lock gate must show (background re-arms the lock)
  2. type password + tap Unlock via native input -> Home must show
  3. HOME then relaunch again -> lock gate must show again
Every phase first proves the app is the RESUMED activity (dumpsys activity,
retried) before any screen assertion or screencap. Pixels are captured with
adb exec-out (no on-device writes). Always writes the native_done marker so
the waiting engine test can finish. Exit 0 only if every check holds."""
import re, sqlite3, subprocess, sys, time

PKG = 'com.example.shop_billing'

def sh(*args):
    return subprocess.run(['adb'] + list(args), capture_output=True, text=True).stdout

def dump():
    sh('shell', 'uiautomator', 'dump', '/sdcard/ui.xml')
    return sh('shell', 'cat', '/sdcard/ui.xml')

def tap_text(xml, text):
    m = re.search(r'text="%s"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"' % re.escape(text), xml)
    if not m:
        return False
    x = (int(m.group(1)) + int(m.group(3))) // 2
    y = (int(m.group(2)) + int(m.group(4))) // 2
    sh('shell', 'input', 'tap', str(x), str(y))
    return True

def launch_app():
    sh('shell', 'monkey', '-p', PKG, '-c', 'android.intent.category.LAUNCHER', '1')

def wait_resumed(label, timeout_s=60):
    """Retry until our package holds the ResumedActivity slot; print the
    actual line as foreground evidence."""
    deadline = time.time() + timeout_s
    last = ''
    while time.time() < deadline:
        out = sh('shell', 'dumpsys', 'activity', 'activities')
        for line in out.splitlines():
            if 'ResumedActivity' in line:
                last = line.strip()
                break
        if PKG in last:
            print('RESUMED_%s=%s' % (label, last))
            return True
        time.sleep(3)
    print('RESUMED_%s=NOT_RESUMED last=%s' % (label, last))
    return False

def screencap(name):
    out = subprocess.run(['adb', 'exec-out', 'screencap', '-p'],
                         capture_output=True).stdout
    if out[:4] == b'\x89PNG':
        open(name, 'wb').write(out)
        print('saved %s (%d bytes)' % (name, len(out)))
    else:
        print('screencap %s FAILED (not a PNG, %d bytes)' % (name, len(out)))

def native_unlock(xml):
    m = re.search(r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml)
    if not m:
        return False
    x = (int(m.group(1)) + int(m.group(3))) // 2
    y = (int(m.group(2)) + int(m.group(4))) // 2
    sh('shell', 'input', 'tap', str(x), str(y))
    time.sleep(1)
    sh('shell', 'input', 'text', 'smoke-lock-99')
    time.sleep(1)
    if not tap_text(dump(), 'Unlock'):
        return False
    deadline = time.time() + 30
    while time.time() < deadline:
        time.sleep(3)
        if 'START WORK' in dump():
            return True
    return False

results = {}
try:
    print(sh('wait-for-device'))
    sh('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')

    # 0. password persistence (app alive; run-as reads its internal storage)
    try:
        db_bytes = subprocess.run(
            ['adb', 'shell', 'run-as', PKG, 'cat', 'databases/shop.db'],
            capture_output=True).stdout
        if db_bytes:
            open('/tmp/smoke_app.db', 'wb').write(db_bytes)
            row = sqlite3.connect('/tmp/smoke_app.db').execute(
                "select value from settings where key='password_hash'").fetchone()
            if row and row[0]:
                parts = row[0].split('$')
                results['persisted'] = len(parts) == 4 and parts[0] == 'v2'
                print('PASSWORD_PERSISTED=%s format=%s iters=%s hashlen=%d'
                      % (results['persisted'], parts[0], parts[2], len(parts[3])))
            else:
                results['persisted'] = False
                print('PASSWORD_PERSISTED=False (no password_hash row)')
        else:
            results['persisted'] = False
            print('PASSWORD_PERSISTED=False (run-as cat returned nothing)')
    except Exception as e:
        results['persisted'] = False
        print('PASSWORD_PERSISTED=False (%s)' % e)

    # 1. HOME then relaunch re-arms the gate
    sh('shell', 'input', 'keyevent', 'KEYCODE_HOME')
    time.sleep(3)
    launch_app()
    r1 = wait_resumed('AFTER_HOME_1')
    xml = dump()
    results['rearm1'] = r1 and 'Locked' in xml
    print('LOCK_GATE_AFTER_HOME=%s' % results['rearm1'])
    screencap('lock_after_home.png')

    # 2. native unlock
    results['unlock'] = native_unlock(xml) if results['rearm1'] else False
    print('OS_UNLOCK=%s' % results['unlock'])
    screencap('lock_after_unlock.png')

    # 3. HOME then relaunch re-arms again
    results['rearm2'] = False
    if results['unlock']:
        sh('shell', 'input', 'keyevent', 'KEYCODE_HOME')
        time.sleep(3)
        launch_app()
        r2 = wait_resumed('AFTER_HOME_2')
        results['rearm2'] = r2 and 'Locked' in dump()
    print('LOCK_GATE_REARM_SECOND=%s' % results['rearm2'])
finally:
    # Always release the waiting engine test, success or failure.
    print(sh('shell', 'run-as', PKG, 'touch', 'files/native_done.txt'))
    print('NATIVE_DONE marker written')

ok = all(results.get(k) for k in ('persisted', 'rearm1', 'unlock', 'rearm2'))
print('NATIVE_LOCK_CHECKS=%s' % ('ALL_PASS' if ok else 'FAILED'))
sys.exit(0 if ok else 1)
