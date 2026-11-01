"""OS-level lock-gate checks via adb on the SAME device where the smoke suite
set password 'smoke-lock-99'. Uses native adb input (not the Flutter engine):
  1. force-stop + cold relaunch  -> Locked must show (persisted hash re-gates)
  2. type password + tap Unlock via native input -> home must show (unlock works)
  3. HOME then relaunch          -> Locked must show (background re-arms gate)
Prints LOCK_GATE_COLDSTART / OS_UNLOCK / LOCK_GATE_AFTER_HOME and exits 0 only
if all three hold. Evidence: lock_coldstart.png, lock_after_home.png, dumps."""
import re, subprocess, sys, time

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
    sh('shell', 'monkey', '-p', 'com.example.shop_billing',
       '-c', 'android.intent.category.LAUNCHER', '1')

print(sh('wait-for-device'))
sh('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')

# 1. cold start with a persisted password
sh('shell', 'am', 'force-stop', 'com.example.shop_billing')
time.sleep(2)
launch_app()
time.sleep(8)
xml = dump()
cold = 'Locked' in xml
print('LOCK_GATE_COLDSTART=%s' % cold)
sh('shell', 'screencap', '-p', '/sdcard/lock_coldstart.png')
print(sh('pull', '/sdcard/lock_coldstart.png', 'lock_coldstart.png'))

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
            time.sleep(6)
            ok_unlock = 'START WORK' in dump()
print('OS_UNLOCK=%s' % ok_unlock)

# 3. background then relaunch re-arms the gate
after_home = False
if ok_unlock:
    sh('shell', 'input', 'keyevent', 'KEYCODE_HOME')
    time.sleep(3)
    launch_app()
    time.sleep(8)
    after_home = 'Locked' in dump()
print('LOCK_GATE_AFTER_HOME=%s' % after_home)
sh('shell', 'screencap', '-p', '/sdcard/lock_after_home.png')
print(sh('pull', '/sdcard/lock_after_home.png', 'lock_after_home.png'))

sys.exit(0 if (cold and ok_unlock and after_home) else 1)
