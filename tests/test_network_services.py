"""Real loopback exchanges; no physical Q11 or LAN settings required."""
from __future__ import annotations
import argparse
import importlib.util
import json
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'tools/network/probe_services.py'
spec = importlib.util.spec_from_file_location('services', SCRIPT)
assert spec and spec.loader
services = importlib.util.module_from_spec(spec)
spec.loader.exec_module(services)


class ServiceTests(unittest.TestCase):
    def exchange(self, mode: str, response: bytes) -> tuple[dict, bytes]:
        received = []
        with socket.socket() as server:
            server.bind(('127.0.0.1', 0))
            server.listen(1)
            server.settimeout(2)
            def answer() -> None:
                with server.accept()[0] as connection:
                    connection.settimeout(2)
                    if mode != 'banner':
                        received.append(connection.recv(1024))
                    else:
                        received.append(b'')
                    connection.sendall(response)
            worker = threading.Thread(target=answer)
            worker.start()
            result = services.probe('127.0.0.1', '127.0.0.1', server.getsockname()[1], mode, 1)
            worker.join(3)
            self.assertFalse(worker.is_alive())
        return result, received[0]

    def test_real_banner_head_and_descriptor_requests(self) -> None:
        banner, request = self.exchange('banner', b'hello\n')
        self.assertEqual(request, b'')
        self.assertEqual(banner['sent_bytes'], 0)
        self.assertEqual(bytes.fromhex(banner['response_hex']), b'hello\n')
        head, request = self.exchange('head', b'HTTP/1.0 404 Not Found\r\nContent-Length: 0\r\n\r\n')
        self.assertTrue(request.startswith(b'HEAD / HTTP/1.0\r\n'))
        self.assertEqual(head['http_status'], 'HTTP/1.0 404 Not Found')
        xml = b'<root><device><deviceType>tv</deviceType><modelName>Q11</modelName><UDN>private</UDN><friendlyName>private</friendlyName></device></root>'
        description, request = self.exchange('dial-description', b'HTTP/1.1 200 OK\r\n\r\n' + xml)
        self.assertTrue(request.startswith(b'GET /dd.xml HTTP/1.0\r\n'))
        self.assertEqual(services.dial_summary(bytes.fromhex(description['response_hex'])), {'deviceType': 'tv', 'modelName': 'Q11'})

    def test_silent_device_deadline_and_absent_device(self) -> None:
        with socket.socket() as server:
            server.bind(('127.0.0.1', 0)); server.listen(1)
            start = time.monotonic()
            result = services.probe('127.0.0.1', '127.0.0.1', server.getsockname()[1], 'banner', .1)
            self.assertLess(time.monotonic() - start, 1)
            self.assertEqual(result['result'], 'silent')
            port = server.getsockname()[1]
        absent = services.probe('127.0.0.1', '127.0.0.1', port, 'banner', .1)
        self.assertFalse(absent['tcp_open'])
        # Windows can defer a loopback refusal beyond the short timeout.
        self.assertIn(absent['result'], ('socket-error', 'timeout'))

    def test_invalid_input_and_xml(self) -> None:
        for target, source in [('8.8.8.8', '192.168.73.1'), ('192.168.74.2', '192.168.73.1'), ('192.168.73.255', '192.168.73.1'), ('127.0.0.2', '127.0.0.1'), ('192.168.73.1', '192.168.73.1')]:
            with self.assertRaises(ValueError): services.addresses(target, source)
        for value in ('0', '65536', '22,22', 'x'):
            with self.assertRaises(argparse.ArgumentTypeError): services.ports(value)
        with self.assertRaises(ValueError): services.probe('127.0.0.1', '127.0.0.1', 22, 'post', .1)
        self.assertEqual(services.dial_summary(b'HTTP/1.1 200 OK\r\n\r\n<truncated>'), {})
        with self.assertRaises(ValueError): services.dial_summary(b'HTTP/1.1 200 OK\r\n\r\n<!DOCTYPE x><x/>')

    def test_cli_success_invalid_missing_and_no_overwrite(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / 'report.json'
            command = [sys.executable, str(SCRIPT), '--target', '192.168.73.2', '--source', '192.168.73.1', '--ports', '56790', '--dry-run', '--output', str(output)]
            result = subprocess.run(command, capture_output=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(json.loads(output.read_text())['dry_run'])
            before = output.read_bytes()
            self.assertNotEqual(subprocess.run(command, capture_output=True, timeout=20).returncode, 0)
            self.assertEqual(output.read_bytes(), before)
            self.assertNotEqual(subprocess.run([sys.executable, str(SCRIPT)], capture_output=True, timeout=20).returncode, 0)
            self.assertNotEqual(subprocess.run(command[:-2] + ['--timeout', '9'], capture_output=True, timeout=20).returncode, 0)


if __name__ == '__main__':
    unittest.main()
