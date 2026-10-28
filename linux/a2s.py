"""A2S_INFO / A2S_PLAYER query (Source protocol, challenge aware). py a2s.py host port [players]"""
import socket
import struct
import sys

HDR = b'\xff\xff\xff\xff'


def query(sock, addr, kind, body):
    sock.sendto(HDR + kind + body, addr)
    data, _ = sock.recvfrom(65535)
    if data[4:5] == b'A':                      # challenge: resend with it
        chal = data[5:9]
        body = body + chal if kind == b'T' else chal
        sock.sendto(HDR + kind + body, addr)
        data, _ = sock.recvfrom(65535)
    return data


def cstr(d, p):
    e = d.index(b'\0', p)
    return d[p:e].decode('utf-8', 'replace'), e + 1


def main():
    addr = (sys.argv[1], int(sys.argv[2]))
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(3)
    d = query(s, addr, b'T', b'Source Engine Query\0')
    if d[4:5] != b'I':
        sys.exit(f'unexpected reply {d[:40]!r}')
    p = 6
    name, p = cstr(d, p)
    mp, p = cstr(d, p)
    folder, p = cstr(d, p)
    game, p = cstr(d, p)
    appid, players, maxp, bots = struct.unpack_from('<HBBB', d, p)
    p += 5
    stype, env, vis, vac = chr(d[p]), chr(d[p + 1]), d[p + 2], d[p + 3]
    ver, p = cstr(d, p + 4)
    print(f'name={name!r} map={mp} folder={folder} game={game!r} appid={appid} '
          f'players={players}/{maxp} bots={bots} type={stype} os={env} vac={vac} version={ver}')
    if len(sys.argv) > 3:
        d = query(s, addr, b'U', b'\xff\xff\xff\xff')
        p = 6
        for _ in range(d[5]):
            p += 1
            pname, p = cstr(d, p)
            score, dur = struct.unpack_from('<lf', d, p)
            p += 8
            print(f'  {pname!r} score={score} time={dur:.0f}s')


main()
