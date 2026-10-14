import hashlib
import pathlib
import subprocess
import sys


config, image, certificate, verifier = sys.argv[1:]
data = pathlib.Path(image).read_bytes()
marker = b"++CONFIG_B2SUM_SIGNATURE++"
if data.count(marker) != 1:
    raise SystemExit("Limine config-hash slot is missing or ambiguous")
start = data.index(marker) + len(marker)
expected = hashlib.blake2b(pathlib.Path(config).read_bytes()).hexdigest().encode()
if data[start : start + 128] != expected:
    raise SystemExit("Limine's enrolled hash does not match the installed configuration")
subprocess.run([verifier, "--cert", certificate, image], check=True)
print("Verified Limine configuration hash and Secure Boot signature")
