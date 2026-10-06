#!/usr/bin/env python3
"""Bounded banner, HEAD /, or DIAL GET /dd.xml on one isolated private device."""
from __future__ import annotations

import argparse
import ipaddress
import socket
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lab import cli, emit, metadata


def addresses(target: str, source: str) -> tuple[str, str]:
    device, host = ipaddress.IPv4Address(target), ipaddress.IPv4Address(source)
    for address in (device, host):
        if not any(address in ipaddress.IPv4Network(network) for network in ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16')) or address.packed[-1] in (0, 255):
            raise ValueError('requires private unicast IPv4 addresses')
    if device == host:
        raise ValueError('source and target must differ')
    if ipaddress.IPv4Network(f'{device}/24', strict=False) != ipaddress.IPv4Network(f'{host}/24', strict=False):
        raise ValueError('source and target must share the isolated /24')
    return str(device), str(host)


def ports(value: str) -> list[int]:
    try:
        selected = [int(item) for item in value.split(',')]
    except ValueError as exc:
        raise argparse.ArgumentTypeError('comma-separated integer ports required') from exc
    if not 1 <= len(selected) <= 32 or len(set(selected)) != len(selected) or any(not 1 <= p <= 65535 for p in selected):
        raise argparse.ArgumentTypeError('requires 1..32 unique ports within 1..65535')
    return selected


def probe(target: str, source: str, port: int, mode: str, timeout: float) -> dict[str, Any]:
    if mode not in ('banner', 'head', 'dial-description') or not 1 <= port <= 65535 or not 0.1 <= timeout <= 3.0:
        raise ValueError('invalid probe mode, port or timeout')
    result: dict[str, Any] = {'port': port, 'mode': mode, 'tcp_open': False, 'sent_bytes': 0}
    deadline = time.monotonic() + timeout
    data = bytearray()
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as stream:
            stream.settimeout(timeout)
            stream.bind((source, 0))
            stream.connect((target, port))
            result['tcp_open'] = True
            if mode in ('head', 'dial-description'):
                method, path = ('HEAD', '/') if mode == 'head' else ('GET', '/dd.xml')
                request = f'{method} {path} HTTP/1.0\r\nHost: {target}:{port}\r\nConnection: close\r\n\r\n'.encode('ascii')
                stream.settimeout(max(0.01, deadline - time.monotonic()))
                stream.sendall(request)
                result['sent_bytes'] = len(request)
            while len(data) < 4096 and time.monotonic() < deadline:
                stream.settimeout(max(0.01, deadline - time.monotonic()))
                try:
                    block = stream.recv(4096 - len(data))
                except TimeoutError:
                    break
                if not block:
                    break
                data.extend(block)
                if mode == 'head' and b'\r\n\r\n' in data:
                    break
            result['result'] = 'response' if data else 'silent'
    except TimeoutError:
        result['result'] = 'timeout'
    except OSError as exc:
        result['result'] = 'socket-error'
        result['error'] = str(exc)
    result['response_bytes'] = len(data)
    result['response_at_limit'] = len(data) == 4096
    # Responses may contain identifiers/nonces. Raw reports stay private, not Git.
    result['response_hex'] = data.hex()
    if data.startswith(b'HTTP/'):
        result['http_status'] = bytes(data).split(b'\r\n', 1)[0].decode('ascii', 'replace')[:128]
    return result


def dial_summary(response: bytes) -> dict[str, str]:
    """Only non-unique device fields; never publish UDN/friendly name/raw headers."""
    header, separator, body = response.partition(b'\r\n\r\n')
    status = header.split(b'\r\n', 1)[0].split()
    if not separator or len(status) < 2 or status[0] not in (b'HTTP/1.0', b'HTTP/1.1') or status[1] != b'200':
        return {}
    if b'<!DOCTYPE' in body.upper() or b'<!ENTITY' in body.upper():
        raise ValueError('DTD/entities are not accepted')
    try:
        root = ET.fromstring(body)
    except ET.ParseError:
        return {}
    allowed = {'deviceType', 'manufacturer', 'modelName', 'modelNumber'}
    return {node.tag.rsplit('}', 1)[-1]: (node.text or '').strip()[:128]
            for node in root.iter() if node.tag.rsplit('}', 1)[-1] in allowed}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', required=True)
    parser.add_argument('--source', required=True, help='bind explicit isolated host address')
    parser.add_argument('--ports', required=True, type=ports)
    parser.add_argument('--mode', choices=('banner', 'head', 'dial-description'), default='banner')
    parser.add_argument('--timeout', type=float, default=2.0)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    target, source = addresses(args.target, args.source)
    if not 0.1 <= args.timeout <= 3.0:
        raise ValueError('timeout must be within 0.1..3 seconds')
    if args.output and args.output.exists():
        raise FileExistsError(args.output)
    results = [] if args.dry_run else [probe(target, source, port, args.mode, args.timeout) for port in args.ports]
    if args.mode == 'dial-description':
        for result in results:
            result['description_summary'] = dial_summary(bytes.fromhex(result['response_hex']))
    emit({**metadata('isolated-service-probe'), 'target': target, 'source': source,
          'ports': args.ports, 'mode': args.mode, 'dry_run': args.dry_run,
          'services': results, 'result': 'ok', 'exit_code': 0,
          'boundary': 'One device only. Banner/HEAD / or read-only GET /dd.xml (Netflix DIAL reference). No redirects, credentials, shell, SOAP, reset, update, POST or application launch.'}, args.output)


if __name__ == '__main__':
    cli(main)
