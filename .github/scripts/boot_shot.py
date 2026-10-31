import re, subprocess, sys, time

def sh(*args):
    return subprocess.run(['adb'] + list(args), capture_output=True, text=True).stdout

print(sh('wait-for-device'))
for _ in range(60):
    if sh('shell', 'getprop', 'sys.boot_completed').strip() == '1':
        break
    time.sleep(3)
time.sleep(10)
print(sh('install', '-r', 'build/app/outputs/flutter-apk/app-release.apk'))
sh('shell', 'monkey', '-p', 'com.example.shop_billing',
   '-c', 'android.intent.category.LAUNCHER', '1')

def dismiss_anr():
    sh('shell', 'uiautomator', 'dump', '/sdcard/ui.xml')
    xml = sh('shell', 'cat', '/sdcard/ui.xml')
    m = re.search(r'text="Wait"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml)
    if m:
        x = (int(m.group(1)) + int(m.group(3))) // 2
        y = (int(m.group(2)) + int(m.group(4))) // 2
        sh('shell', 'input', 'tap', str(x), str(y))
        return True
    return False

ok = False
for _ in range(10):
    time.sleep(8)
    dismiss_anr()
    out = sh('shell', 'dumpsys', 'activity', 'activities')
    for line in out.splitlines():
        if 'ResumedActivity' in line and 'shop_billing' in line:
            ok = True
            break
    if ok:
        break
time.sleep(6)
dismiss_anr()
sh('shell', 'screencap', '-p', '/sdcard/boot_home.png')
sh('pull', '/sdcard/boot_home.png', 'boot_home.png')
open('logcat_tail.txt', 'w').write(sh('logcat', '-d', '-t', '400'))
print('RESUMED_OK' if ok else 'RESUMED_NOT_CONFIRMED')
sys.exit(0 if ok else 1)
