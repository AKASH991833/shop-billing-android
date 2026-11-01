"""OS-level lock-gate checks via adb on the SAME device where the smoke suite
set password 'smoke-lock-99'. Uses native adb input (not the Flutter engine):
  0. password persistence: pull the app db via run-as (debug build) and check
     the password_hash row on the HOST with python's sqlite3
  1. force-stop + cold relaunch  -> Locked must show (persisted hash re-gates)
  2. type password + tap Unlock via native input -> home must show
  3. HOME then relaunch          -> Locked must show (background re-arms gate)
Every phase first proves the app is in the FOREGROUND (dumpsys window focus
line, retried up to 60s) before any screen assertion or screenshot - a fixed
short wait made run 41 photograph the launcher instead of the app.
Prints PASSWORD_PERSISTED / FOCUS lines / LOCK_GATE_COLDSTART / OS_UNLOCK /
LOCK_GATE_AFTER_HOME and exits 0 only if all gates hold."""
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

def wait_focus(label, timeout_s=60):
    """Retry until the app holds window focus; print the focus line as
    foreground evidence. Returns True only when focused on our package."""
    deadline = time.time() + timeout_s
    last = ''
    while time.time() < deadline:
        out = sh('shell', 'dumpsys', 'window', 'windows')
        for line in out.splitlines():
            if 'mCurrentFocus' in line:
                last = line.strip()
                break
        if PKG in last:
            print('FOCUS_%s=%s' % (label, last))
            return True
        time.sleep(3)
    print('FOCUS_%s=NOT_FOREGROUND last=%s' % (label, last))
    return False

def screencap(name):
    sh('shell', 'screencap', '-p', '/sdcard/%s' % name)
    print(sh('pull', '/sdcard/%s' % name, name))

print(sh('wait-for-device'))
sh('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')

# 0. password persistence, checked on the host from the pulled database
persisted = False
try:
    db_bytes = subprocess.run(
        ['adb', 'shell', 'run-as', PKG, 'cat', 'databases/shop_billing.db'],
        capture_output=True).stdout
    if db_bytes:
        open('/tmp/smoke_app.db', 'wb').write(db_bytes)
        row = sqlite3.connect('/tmp/smoke_app.db').execute(
            "select value from settings where key='password_hash'").fetchone()
        if row and row[0]:
            parts = row[0].split('$')
            persisted = len(parts) == 4 and parts[0] == 'v2'
            print('PASSWORD_PERSISTED=True format=%s iters=%s hashlen=%d'
                  % (parts[0], parts[2], len(parts[3])))
        else:
            print('PASSWORD_PERSISTED=False (no password_hash row)')
    else:
        print('PASSWORD_PERSISTED=UNKNOWN (run-as cat returned nothing)')
except Exception as e:
    print('PASSWORD_PERSISTED=UNKNOWN (%s)' % e)

# 1. cold start with a persisted password
sh('shell', 'am', 'force-stop', PKG)
time.sleep(2)
launch_app()
focused_cold = wait_focus('COLD')
xml = dump()
cold = focused_cold and 'Locked' in xml
print('LOCK_GATE_COLDSTART=%s' % cold)
screencap('lock_coldstart.png')

# 2. native unlock
ok_unlock = False
if cold:
    m = re.search(r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml)
    if m:
        x = (int(m.group(1)) + int(m.group(3))) // 2
        y = (int(m.group(2)) + int(m.group(4))) // 2
        sh('shell', 'input', 'tap', str(x), str(y))
        time.sleep(1)
        sh('shell', 'input', 'text', 'smoke-lock-99')
        time.sleep(1)
        xml2 = dump()
        if tap_text(xml2, 'Unlock'):
            deadline = time.time() + 30
            while time.time() < deadline:
                time.sleep(3)
                if 'START WORK' in dump():
                    ok_unlock = True
                    break
print('OS_UNLOCK=%s' % ok_unlock)

# 3. background then relaunch re-arms the gate
after_home = False
if ok_unlock:
    sh('shell', 'input', 'keyevent', 'KEYCODE_HOME')
    time.sleep(3)
    launch_app()
    focused_home = wait_focus('AFTER_HOME')
    after_home = focused_home and 'Locked' in dump()
print('LOCK_GATE_AFTER_HOME=%s' % after_home)
screencap('lock_after_home.png')

sys.exit(0 if (persisted and cold and ok_unlock and after_home) else 1)
