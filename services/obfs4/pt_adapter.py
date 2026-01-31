#!/usr/bin/env python3
import os
import sys
import subprocess
import socket
import select
import struct
import threading
import time

# SIP003 Adapter for Obfs4 (WireGuard UDP Support)
# Bridges Shadowsocks (SIP003) <-> Obfs4proxy (Tor PT)
# Essential because Obfs4 is TCP-only, but WS needs UDP-over-TCP encapsulation 
# which SS provides but requires a stream transport, not a SOCKS5 proxy that rejects UDP.

OBFS4PROXY = "/usr/local/bin/obfs4proxy"

def log(msg):
    sys.stderr.write(f"[pt_adapter] {msg}\n")
    sys.stderr.flush()

def start_server():
    # SS_REMOTE -> Bind Address (Public)
    # SS_LOCAL  -> Forward Address (Loopback SS-Server)
    bind_host = os.environ.get("SS_REMOTE_HOST", "0.0.0.0")
    bind_port = os.environ.get("SS_REMOTE_PORT", "12345")
    or_host = os.environ.get("SS_LOCAL_HOST", "127.0.0.1")
    or_port = os.environ.get("SS_LOCAL_PORT", "33333")
    
    env = os.environ.copy()
    env.update({
        "TOR_PT_MANAGED_TRANSPORT_VER": "1",
        "TOR_PT_STATE_LOCATION": "/var/lib/obfs4",
        "TOR_PT_SERVER_TRANSPORTS": "obfs4",
        "TOR_PT_SERVER_BINDADDR": f"obfs4-{bind_host}:{bind_port}",
        "TOR_PT_ORPORT": f"{or_host}:{or_port}"
    })
    
    log(f"Server starting: {bind_host}:{bind_port} -> {or_host}:{or_port}")
    proc = subprocess.Popen([OBFS4PROXY], env=env, stdout=subprocess.PIPE, stderr=sys.stderr, text=True)
    
    # Keep alive
    proc.wait()

def handle_client(client, socks_addr, auth_data):
    remote = None
    try:
        remote = socket.create_connection(socks_addr)
        # SOCKS5 Auth (Method 2)
        remote.sendall(b"\x05\x01\x02")
        if remote.recv(2)[1] == 0x02:
            # Send Auth (Cert + IAT)
            u_len = len(auth_data)
            remote.sendall(struct.pack("BB", 1, u_len) + auth_data + b"\x00")
            if remote.recv(2)[1] != 0x00: raise Exception("Auth failed")
            
        # Connect to Dummy Target (obfs4proxy ignores this in client mode usually, 
        # but we must send a valid CONNECT request)
        remote.sendall(b"\x05\x01\x00\x01\x7f\x00\x00\x01\x00\x00") # 127.0.0.1:0
        if remote.recv(1024)[1] != 0x00: raise Exception("Connect failed")
        
        # Bridge
        while True:
            r, _, _ = select.select([client, remote], [], [])
            if client in r:
                data = client.recv(4096)
                if not data: break
                remote.sendall(data)
            if remote in r:
                data = remote.recv(4096)
                if not data: break
                client.sendall(data)
    except Exception:
        pass
    finally:
        client.close()
        if remote: remote.close()

def start_client():
    # SS passes host/port to listen on in local vars? 
    # Actually SIP003 client mode: SS_LOCAL_HOST/PORT is where SS wants us to listen?
    # No, SS executes plugin. Plugin listens. SS connects to Plugin.
    # SS_REMOTE_HOST/PORT is the Real Server Address (we don't use it, Obfs4 knows it via cert/setup? 
    # No, we must pass it? Obfs4proxy manages connection details via SOCKS args?).
    # Wait, Obfs4proxy Client mode needs remote connection details!
    # "CMETHOD obfs4 SOCKS5 <addr>"
    # We configure Obfs4 via env vars only for Transports.
    # The actual connection destination is passed via SOCKS5 Request?
    # NO. Obfs4proxy (client) terminates SOCKS5. It needs to know where the Bridge is.
    # We pass that in `SS_REMOTE_HOST`?
    # Actually, in Client mode, we used `TOR_PT_CLIENT_TRANSPORTS=obfs4`. 
    # Obfs4proxy doesn't know the server IP yet.
    # When we do SOCKS5 CONNECT, we tell it the Destination IP!
    # Ah! In my previous adapter I sent target_host/port!
    # standard `ss-local` usage:
    # 1. ss-local receives packet.
    # 2. Encrypts it.
    # 3. Sends to Plugin.
    # 4. Plugin forwards to Remote Server.
    
    local_host = os.environ.get("SS_LOCAL_HOST", "127.0.0.1")
    local_port = int(os.environ.get("SS_LOCAL_PORT", "1080"))
    
    # We need to know the Bridge Address to tell Obfs4proxy
    remote_host = os.environ.get("SS_REMOTE_HOST", "127.0.0.1")
    remote_port = os.environ.get("SS_REMOTE_PORT", "12345")
    
    # Auth args from SS
    plugin_opts = os.environ.get("SS_PLUGIN_OPTIONS", "").encode('utf-8')
    
    env = os.environ.copy()
    env.update({
        "TOR_PT_MANAGED_TRANSPORT_VER": "1",
        "TOR_PT_STATE_LOCATION": "/var/lib/obfs4",
        "TOR_PT_CLIENT_TRANSPORTS": "obfs4"
    })
    
    proc = subprocess.Popen([OBFS4PROXY], env=env, stdout=subprocess.PIPE, stderr=sys.stderr, text=True)
    
    socks_addr = None
    while True:
        line = proc.stdout.readline()
        if not line: break
        if "CMETHOD obfs4 socks5" in line.lower():
            addr = line.split()[3]
            socks_addr = (addr.split(":")[0], int(addr.split(":")[1]))
            break
            
    if not socks_addr: sys.exit(1)
    
    # Start Listener for SS
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((local_host, local_port))
    srv.listen(10)
    
    # Update global for threads
    # In SOCKS CONNECT, we must send the Real Bridge Address.
    # Because Obfs4proxy uses that to dial the server.
    def handler(c):
        r = socket.socket()
        try:
            r.connect(socks_addr)
            r.sendall(b"\x05\x01\x02") # Auth
            r.recv(2)
            # Send Auth (Cert)
            u_len = len(plugin_opts)
            r.sendall(struct.pack("BB", 1, u_len) + plugin_opts + b"\x00")
            r.recv(2)
            
            # Connect to Bridge IP (The one SS thinks is remote)
            # IPv4
            try:
                ip_b = socket.inet_aton(remote_host)
                addr_h = b"\x05\x01\x00\x01" + ip_b
            except:
                # Domain
                h_b = remote_host.encode()
                addr_h = b"\x05\x01\x00\x03" + struct.pack("B", len(h_b)) + h_b
            
            p_b = struct.pack("!H", int(remote_port))
            r.sendall(addr_h + p_b)
            
            if r.recv(1024)[1] != 0x00: raise
            
            while True:
                fds, _, _ = select.select([c, r], [], [])
                if c in fds:
                    d = c.recv(4096)
                    if not d: break
                    r.sendall(d)
                if r in fds:
                    d = r.recv(4096)
                    if not d: break
                    c.sendall(d)
        except: pass
        finally: 
            c.close()
            r.close()

    while True:
        c, _ = srv.accept()
        threading.Thread(target=handler, args=(c,), daemon=True).start()

if __name__ == "__main__":
    if os.environ.get("SS_REMOTE_HOST") == "0.0.0.0" or "server" in sys.argv:
        start_server()
    else:
        start_client()
