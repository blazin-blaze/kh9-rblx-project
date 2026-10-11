"""Relay-only DNS fallback when a network caches an old hostname-not-found answer."""
import http.client
import ipaddress
import json
import socket
import threading
import time
from urllib.parse import urlencode, urlsplit
from urllib.request import HTTPSHandler, HTTPRedirectHandler, Request, build_opener


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


_cache = {}
_lock = threading.Lock()


def public_addresses(host):
    with _lock:
        cached = _cache.get(host)
        if cached and cached[0] > time.monotonic():
            return cached[1]
    # Only the hostname is sent to DNS; no relay credentials, microphone, or commands.
    request = Request('https://1.1.1.1/dns-query?' + urlencode({'name': host, 'type': 'A'}),
                      headers={'Accept': 'application/dns-json'})
    with build_opener(NoRedirect()).open(request, timeout=3) as response:
        body = json.load(response)
    if not isinstance(body, dict) or body.get('Status') != 0:
        raise socket.gaierror('Relay hostname could not be resolved')
    addresses, ttl = [], 60
    for answer in body.get('Answer', []):
        if answer.get('type') != 1:
            continue
        address = ipaddress.ip_address(answer['data'])
        if address.version == 4 and address.is_global:
            addresses.append(str(address))
            ttl = min(ttl, max(1, int(answer.get('TTL', 1))))
    if not addresses:
        raise socket.gaierror('Relay hostname has no public address')
    with _lock:
        _cache[host] = (time.monotonic() + ttl, addresses)
    return addresses


def relay_connection(address, timeout=socket._GLOBAL_DEFAULT_TIMEOUT, source_address=None):
    try:
        return socket.create_connection(address, timeout, source_address)
    except socket.gaierror:
        host, port = address
        last_error = None
        for ip in public_addresses(host):
            try:
                return socket.create_connection((ip, port), timeout, source_address)
            except OSError as error:
                last_error = error
        raise last_error or socket.gaierror('Relay unavailable')


def relay_opener(url):
    relay_host = urlsplit(url).hostname

    class RelayConnection(http.client.HTTPSConnection):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            if self.host == relay_host:
                # HTTPSConnection still uses the original hostname for SNI/certificate checks.
                self._create_connection = relay_connection

    class RelayHTTPSHandler(HTTPSHandler):
        def https_open(self, request):
            return self.do_open(RelayConnection, request, context=self._context)

    opener = build_opener(NoRedirect(), RelayHTTPSHandler())
    opener.addheaders = [('User-Agent', 'KnightHacksVoiceRelay/1.0')]
    return opener
