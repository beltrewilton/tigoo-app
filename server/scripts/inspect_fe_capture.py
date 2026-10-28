#!/usr/bin/env python3
"""Inspect saved DGII XML offline; never submit, issue tokens, or alter app trust."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET


def run(args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    return result.returncode, result.stdout


def save(directory, name, data):
    path = directory / name
    with path.open("xb") as stream:
        stream.write(data)
    path.chmod(0o600)
    return path


def certificate_pem(openssl, path):
    for encoding in ("PEM", "DER"):
        code, output = run([openssl, "x509", "-inform", encoding, "-in", str(path), "-outform", "PEM"])
        if code == 0:
            return output
    raise ValueError("Cannot decode certificate: " + str(path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xml", required=True, type=Path)
    parser.add_argument("--roots", nargs="+", type=Path, required=True)
    parser.add_argument("--intermediates", nargs="*", type=Path, default=[])
    parser.add_argument("--output", required=True, type=Path, help="New directory; existing output is never overwritten")
    parser.add_argument("--xmlsec", default="xmlsec1")
    parser.add_argument("--openssl", default="openssl")
    args = parser.parse_args()
    openssl = shutil.which(args.openssl)
    xmlsec = shutil.which(args.xmlsec)
    if not openssl or not xmlsec:
        raise ValueError("openssl and xmlsec1 must be installed")

    if args.xml.stat().st_size > 5_000_000:
        raise ValueError("XML exceeds 5 MB")
    xml = args.xml.read_bytes()
    if b"<!DOCTYPE" in xml or b"<!ENTITY" in xml or b"\0" in xml:
        raise ValueError("Unsupported XML content")
    root = ET.fromstring(xml)
    ds = "{http://www.w3.org/2000/09/xmldsig#}"
    signatures = root.findall(".//" + ds + "Signature")
    if len(signatures) != 1:
        raise ValueError("Expected exactly one XML signature")
    certificates = signatures[0].findall("./" + ds + "KeyInfo/" + ds + "X509Data/" + ds + "X509Certificate")
    if not certificates:
        raise ValueError("No embedded signer certificate")

    os.umask(0o077)
    args.output.mkdir(parents=True, exist_ok=False)
    args.output.chmod(0o700)
    original = save(args.output, "original.xml", xml)
    certificate_paths = []
    for index, certificate in enumerate(certificates, 1):
        der = base64.b64decode("".join((certificate.text or "").split()), validate=True)
        raw = save(args.output, f"certificate-{index}.der", der)
        pem = save(args.output, f"certificate-{index}.pem", certificate_pem(openssl, raw))
        certificate_paths.append(pem)
        _, details = run([openssl, "x509", "-in", str(pem), "-noout", "-text", "-fingerprint", "-sha256"])
        save(args.output, f"certificate-{index}.txt", details)

    roots = save(args.output, "trusted-roots.pem", b"".join(certificate_pem(openssl, p) for p in args.roots))
    intermediates = args.intermediates + certificate_paths[1:]
    chain_args = [openssl, "verify", "-no-CApath", "-CAfile", str(roots)]
    _, verify_help = run([openssl, "verify", "-help"])
    if b"-no-CAstore" in verify_help:
        chain_args.append("-no-CAstore")
    if intermediates:
        bundle = save(args.output, "intermediates.pem", b"".join(certificate_pem(openssl, p) for p in intermediates))
        chain_args += ["-untrusted", str(bundle)]
    chain_code, chain_log = run(chain_args + [str(certificate_paths[0])])
    save(args.output, "chain-verification.txt", chain_log)

    # Explicitly isolate signature integrity from chain trust. This result never
    # authenticates a caller and must not be used as an application trust bypass.
    _, help_text = run([xmlsec, "--help-verify"])
    signature_args = [xmlsec, "--verify", "--enabled-reference-uris", "empty",
                      "--enabled-key-data", "raw-x509-cert", "--pubkey-cert-pem", str(certificate_paths[0])]
    if b"--lax-key-search" in help_text:
        signature_args.append("--lax-key-search")
    signature_code, signature_log = run(signature_args + [str(original)])
    save(args.output, "signature-verification.txt", signature_log)
    report = {
        "xml_sha256": hashlib.sha256(xml).hexdigest(),
        "signer_certificate_sha256": hashlib.sha256((args.output / "certificate-1.der").read_bytes()).hexdigest(),
        "signature_integrity": "passed" if signature_code == 0 else "failed",
        "certificate_chain": "passed" if chain_code == 0 else "failed",
        "overall": "passed" if signature_code == chain_code == 0 else "failed",
        "scope": "Offline cryptographic inspection only; no seed freshness, XSD, tenant, or token validation",
    }
    save(args.output, "report.json", json.dumps(report, indent=2).encode())
    print(json.dumps(report, indent=2))
    print("Evidence directory:", args.output.resolve())
    return 0 if report["overall"] == "passed" else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, ET.ParseError, subprocess.TimeoutExpired) as error:
        print("Inspection failed:", error, file=sys.stderr)
        sys.exit(2)
