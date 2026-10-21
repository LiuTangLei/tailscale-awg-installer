"""Run only in the disposable --network none Linux fixture, never on a host."""
import json, os, select, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
report = {'passed': False, 'kernel': os.uname().release,
          'scope': 'real release netns hooks, UDP/TCP and real QUIC handshakes; not a full authenticated tailnet/WG/AWG/DERP session test',
          'cases': []}
children = []

def run(*args):
    p = subprocess.run(args, text=True, capture_output=True, timeout=5)
    if p.returncode:
        raise RuntimeError(f'{args}: {p.stderr}')
    return p.stdout.strip()

def ip(*args):
    return run('ip', *args)

def link(letter, recreate=False):
    name = 'wan' + letter
    ns = 'gw' + letter
    v4 = '192.0.2' if letter == 'a' else '198.51.100'
    v6 = '2001:db8:a' if letter == 'a' else '2001:db8:b'
    ip('link', 'add', name, 'type', 'veth', 'peer', 'name', 'peer' + letter)
    ip('link', 'set', 'peer' + letter, 'netns', ns)
    ip('addr', 'add', v4 + '.2/24', 'dev', name)
    ip('-6', 'addr', 'add', v6 + '::2/64', 'dev', name, 'nodad')
    ip('link', 'set', name, 'up')
    for args in [('addr', 'add', v4 + '.1/24', 'dev', 'peer' + letter),
                 ('-6', 'addr', 'add', v6 + '::1/64', 'dev', 'peer' + letter, 'nodad'),
                 ('link', 'set', 'peer' + letter, 'up')]:
        ip('-n', ns, *args)

def routes(family):
    if family == '4':
        ip('-4', 'route', 'replace', 'table', '100', '198.51.100.0/24', 'dev', 'wanb', 'src', '198.51.100.2')
        ip('-4', 'route', 'replace', 'table', '100', 'default', 'via', '198.51.100.1', 'dev', 'wanb')
    else:
        ip('-6', 'route', 'replace', 'table', '100', '2001:db8:b::/64', 'dev', 'wanb', 'src', '2001:db8:b::2')
        ip('-6', 'route', 'replace', 'table', '100', 'default', 'via', '2001:db8:b::1', 'dev', 'wanb')

def stage(name, expected, families=('4', '6'), kinds=('udp', 'tcp', 'quic')):
    case = {'name': name, 'expected': expected, 'probes': []}
    report['cases'].append(case)
    for f in families:
        for kind in kinds:
            host = '203.0.113.10' if f == '4' else '2001:db8:ffff::10'
            probe.stdin.write(kind + f + ' ' + host + '\n'); probe.stdin.flush()
            if not select.select([probe.stdout], [], [], 5)[0]:
                raise RuntimeError('probe did not respond: ' + name)
            line = probe.stdout.readline()
            if not line:
                raise RuntimeError('probe exited: ' + str(probe.poll()))
            result = json.loads(line)
            case['probes'].append(result)
            assert (bool(result.get('error')) if expected == 'blocked'
                    else result.get('label') == expected and not result.get('error')), (name, result)
    case['passed'] = True
    print(name, 'PASS', flush=True)

assert os.environ.get('ISSUE19_DISPOSABLE_FIXTURE') == '1', 'Use the documented disposable Docker fixture'
kernel_fallbacks = {'tunl0', 'gre0', 'gretap0', 'erspan0', 'ip_vti0', 'ip6_vti0', 'sit0', 'ip6tnl0', 'ip6gre0'}
assert all(i['ifname'] == 'lo' or (i['ifname'] in kernel_fallbacks and 'UP' not in i['flags'])
           for i in json.loads(ip('-j', 'link', 'show'))), 'Fixture must have no external interfaces'
assert not ip('-4', 'route', 'show', 'table', 'main') and not ip('-6', 'route', 'show', 'table', 'main'), 'Fixture must have no external routes'

try:
    ip('link', 'set', 'lo', 'up')
    for letter in ('a', 'b'):
        ip('netns', 'add', 'gw' + letter)
        ip('-n', 'gw' + letter, 'link', 'set', 'lo', 'up')
        ip('-n', 'gw' + letter, 'addr', 'add', '203.0.113.10/32', 'dev', 'lo')
        ip('-n', 'gw' + letter, '-6', 'addr', 'add', '2001:db8:ffff::10/128', 'dev', 'lo', 'nodad')
        link(letter)
        p = subprocess.Popen(['ip', 'netns', 'exec', 'gw' + letter, str(ROOT / 'egress-probe'), 'serve', letter.upper()], stdout=subprocess.PIPE, text=True)
        children.append(p)
        assert select.select([p.stdout], [], [], 5)[0] and p.stdout.readline().strip() == 'ready'
    ip('route', 'add', 'default', 'via', '192.0.2.1', 'dev', 'wana')
    ip('-6', 'route', 'add', 'default', 'via', '2001:db8:a::1', 'dev', 'wana')
    for f in ('4', '6'):
        # Reproduce the release's bypass/main and VPN-table rule ordering.
        ip('-' + f, 'rule', 'add', 'pref', '5210', 'fwmark', '0x80000/0xff0000', 'lookup', 'main')
        ip('-' + f, 'rule', 'add', 'pref', '5250', 'fwmark', '0x80000/0xff0000', 'type', 'unreachable')
        ip('-' + f, 'rule', 'add', 'pref', '5270', 'lookup', '52')
        ip('-' + f, 'route', 'add', 'blackhole', 'default', 'table', '52')
    env = dict(os.environ, ALL_PROXY='', all_proxy='', NO_PROXY='*', no_proxy='*', TS_FORCE_LINUX_BIND_TO_DEVICE='false')
    probe = subprocess.Popen([str(ROOT / 'egress-probe')], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=env)
    children.append(probe)
    stage('default unchanged', 'A')
    for f in ('4', '6'):
        ip('-' + f, 'route', 'del', 'table', '52', 'default')
    # With no exit default, ordinary unmarked Internet traffic uses main.
    # Fail-closed guard must be installed before the selective lookup.
    for f in ('4', '6'):
        ip('-' + f, 'rule', 'add', 'pref', '5190', 'fwmark', '0x80000/0xff0000', 'type', 'unreachable')
        ip('-' + f, 'rule', 'add', 'pref', '5180', 'fwmark', '0x80000/0xff0000', 'lookup', '100')
    routes('4')
    stage('IPv4 through B', 'B', ('4',))
    stage('IPv6 blocked until configured', 'blocked', ('6',))
    routes('6')
    stage('dual stack through non-default B', 'B')
    stage('unmarked traffic still follows A', 'A', kinds=('plain',))
    ip('route', 'replace', 'default', 'via', '198.51.100.1', 'dev', 'wanb')
    ip('-6', 'route', 'replace', 'default', 'via', '2001:db8:b::1', 'dev', 'wanb')
    stage('main defaults change', 'B')
    ip('route', 'replace', 'default', 'via', '192.0.2.1', 'dev', 'wana')
    ip('-6', 'route', 'replace', 'default', 'via', '2001:db8:a::1', 'dev', 'wana')
    for f in ('4', '6'):
        ip('-' + f, 'route', 'del', 'table', '100', 'default')
    stage('selected route removed: no fallback to A', 'blocked')
    stage('unmarked traffic remains usable during B outage', 'A', kinds=('plain',))
    routes('4'); routes('6')
    stage('route restored on the same UDP sockets', 'B')
    ip('link', 'set', 'wanb', 'down')
    stage('selected link down: no fallback to A', 'blocked')
    ip('link', 'set', 'wanb', 'up')
    # Linux may remove IPv6 addresses when the interface goes down. Model the
    # network manager restoring its address before reinstalling policy routes.
    ip('-6', 'addr', 'replace', '2001:db8:b::2/64', 'dev', 'wanb', 'nodad')
    routes('4'); routes('6')
    stage('link restored on the same UDP sockets', 'B')
    old_index = int(Path('/sys/class/net/wanb/ifindex').read_text())
    ip('link', 'del', 'wanb')
    stage('selected interface deleted: no fallback to A', 'blocked')
    link('b', recreate=True); routes('4'); routes('6')
    new_index = int(Path('/sys/class/net/wanb/ifindex').read_text())
    assert new_index != old_index
    stage('new interface index plus restored routes: reconnect', 'B')
    report['interface_indices'] = [old_index, new_index]
    # Both guards remain until selective lookups are removed during rollback.
    for f in ('4', '6'):
        ip('-' + f, 'rule', 'del', 'pref', '5180')
        ip('-' + f, 'rule', 'del', 'pref', '5190')
        ip('-' + f, 'route', 'flush', 'table', '100')
    stage('rollback restores ordinary default A', 'A')
    report['passed'] = True
finally:
    for p in children:
        p.terminate()
        try: p.wait(timeout=3)
        except subprocess.TimeoutExpired: p.kill(); p.wait()
    ROOT.joinpath('matrix-result.json').write_text(json.dumps(report, indent=2) + '\n')
