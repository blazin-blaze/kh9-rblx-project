import io
import json
import socket
import unittest
from unittest.mock import Mock, patch

import relay_dns


class RelayDNSTests(unittest.TestCase):
    def setUp(self):
        relay_dns._cache.clear()

    def test_system_dns_success_does_not_contact_fallback(self):
        sock = object()
        with patch.object(relay_dns.socket, 'create_connection', return_value=sock), patch.object(relay_dns, 'public_addresses') as lookup:
            self.assertIs(relay_dns.relay_connection(('relay.example.com', 443), 5), sock)
            lookup.assert_not_called()

    def test_failed_dns_connects_to_ip_without_changing_tls_hostname(self):
        sock = object()
        with patch.object(relay_dns.socket, 'create_connection', side_effect=[socket.gaierror(), sock]) as connect, patch.object(relay_dns, 'public_addresses', return_value=['1.1.1.1']):
            self.assertIs(relay_dns.relay_connection(('relay.example.com', 443), 5), sock)
            self.assertEqual(connect.call_args.args[0], ('1.1.1.1', 443))
        opener = relay_dns.relay_opener('https://relay.example.com')
        self.assertEqual(opener.addheaders, [('User-Agent', 'KnightHacksVoiceRelay/1.0')])
        handler = next(h for h in opener.handlers if h.__class__.__name__ == 'RelayHTTPSHandler')
        with patch.object(handler, 'do_open', return_value='response') as opened:
            self.assertEqual(handler.https_open(object()), 'response')
            connection_class = opened.call_args.args[0]
            connection = connection_class('relay.example.com')
            self.assertEqual(connection.host, 'relay.example.com')
            self.assertTrue(connection._context.check_hostname)
            self.assertEqual(connection._context.verify_mode, 2)
            self.assertIs(connection._create_connection, relay_dns.relay_connection)
            other = connection_class('proxy.example.com')
            self.assertIsNot(other._create_connection, relay_dns.relay_connection)

    def test_connection_errors_do_not_trigger_dns_fallback(self):
        with patch.object(relay_dns.socket, 'create_connection', side_effect=ConnectionRefusedError()), patch.object(relay_dns, 'public_addresses') as lookup:
            with self.assertRaises(ConnectionRefusedError):
                relay_dns.relay_connection(('relay.example.com', 443), 5)
            lookup.assert_not_called()

    def test_secure_lookup_has_no_credentials_and_filters_private_answers(self):
        body = {'Status': 0, 'Answer': [{'type': 1, 'TTL': 300, 'data': '10.0.0.1'}, {'type': 1, 'TTL': 300, 'data': '1.1.1.1'}]}
        opener = Mock()
        opener.open.return_value.__enter__ = Mock(return_value=io.StringIO(json.dumps(body)))
        opener.open.return_value.__exit__ = Mock(return_value=False)
        with patch.object(relay_dns, 'build_opener', return_value=opener):
            self.assertEqual(relay_dns.public_addresses('relay.example.com'), ['1.1.1.1'])
            self.assertEqual(relay_dns.public_addresses('relay.example.com'), ['1.1.1.1'])
            self.assertEqual(opener.open.call_count, 1)
            request = opener.open.call_args.args[0]
            self.assertTrue(request.full_url.startswith('https://1.1.1.1/dns-query?'))
            self.assertEqual(request.header_items(), [('Accept', 'application/dns-json')])


if __name__ == '__main__':
    unittest.main()
