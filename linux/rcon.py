"""Source RCON client (TCP). py rcon.py host port password "command" ["command" ...]
The password can also come from the RCON_PASSWORD environment variable (pass "-" as the password)."""
import os
import socket
import struct
import sys
import time


def packet(rid, kind, body):
    data = struct.pack('<ii', rid, kind) + body.encode() + b'\0\0'
    return struct.pack('<i', len(data)) + data


def read_packet(s):
    size = b''
    while len(size) < 4:
        chunk = s.recv(4 - len(size))
        if not chunk:
            raise EOFError
        size += chunk
    n, = struct.unpack('<i', size)
    data = b''
    while len(data) < n:
        chunk = s.recv(n - len(data))
        if not chunk:
            raise EOFError
        data += chunk
    rid, kind = struct.unpack_from('<ii', data)
    return rid, kind, data[8:-2].decode('utf-8', 'replace')


def main():
    host, port, pw = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    if pw == '-':
        pw = os.environ['RCON_PASSWORD']
    s = socket.create_connection((host, port), timeout=10)
    s.sendall(packet(1, 3, pw))
    while True:
        rid, kind, _ = read_packet(s)
        if kind == 2:
            break
    if rid == -1:
        sys.exit('rcon: bad password')
    for i, cmd in enumerate(sys.argv[4:], start=10):
        s.sendall(packet(i, 2, cmd))
        s.sendall(packet(i + 1000, 0, ''))      # empty marker: its echo ends the reply
        out = []
        while True:
            try:
                rid, kind, body = read_packet(s)
            except socket.timeout:
                break
            if rid == i + 1000:
                break
            out.append(body)
        sys.stdout.write(''.join(out))
        time.sleep(0.1)


main()
