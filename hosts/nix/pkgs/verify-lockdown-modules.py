import lzma
import pathlib
import struct
import subprocess
import sys
import tempfile


kernel = pathlib.Path(sys.argv[1])
version = sys.argv[2]
root = pathlib.Path("root")
(root / "modules").mkdir(parents=True)
magic = b"~Module signature appended~\n"


def unpack(path):
    data = path.read_bytes()
    return lzma.decompress(data) if path.suffix == ".xz" else data


def payload_and_signature(data):
    if not data.endswith(magic) or len(data) < len(magic) + 12:
        raise ValueError("Missing module signature")
    end = len(data) - len(magic) - 12
    _, _, kind, signer_len, key_len, length = struct.unpack(
        ">BBBBB3xI", data[end : end + 12]
    )
    if kind != 2 or signer_len or key_len or not 0 < length <= end:
        raise ValueError("Invalid PKCS#7 module signature trailer")
    return data[: end - length], data[end - length : end]


subprocess.run(
    ["openssl", "x509", "-inform", "DER", "-in", str(kernel / "module-signing.x509"),
     "-out", "certificate.pem"], check=True
)
modules = sorted((kernel / "lib/modules" / version).rglob("*.ko*"))
required = {"nvidia", "nvidia-drm", "nvidia-modeset", "nvidia-uvm", "nct6687", "v4l2loopback"}
available = {path.name.removesuffix(".xz").removesuffix(".ko") for path in modules}
if missing := required - available:
    raise RuntimeError(f"Missing signed drivers: {sorted(missing)}")
with tempfile.TemporaryDirectory() as temporary:
    payload_path = pathlib.Path(temporary) / "module"
    signature_path = pathlib.Path(temporary) / "signature"
    for path in modules:
        payload, signature = payload_and_signature(unpack(path))
        payload_path.write_bytes(payload)
        signature_path.write_bytes(signature)
        result = subprocess.run(
            ["openssl", "cms", "-verify", "-binary", "-inform", "DER", "-noverify",
             "-nointern", "-certfile", "certificate.pem", "-in", str(signature_path),
             "-content", str(payload_path), "-out", "/dev/null"],
            capture_output=True, text=True
        )
        if result.returncode:
            raise RuntimeError(f"{path}: {result.stderr}")

# Use modprobe's actual dependency order for the signed virtual-camera path.
for module in ["dummy", "v4l2loopback"]:
    dependencies = subprocess.check_output(
        ["modprobe", "--show-depends", "-d", str(kernel), "-S", version, module],
        text=True
    )
    commands = []
    for line in dependencies.splitlines():
        if line.startswith("insmod "):
            path = pathlib.Path(line.split()[1])
            name = path.name.removesuffix(".xz")
            (root / "modules" / name).write_bytes(unpack(path))
            commands.append(f"insmod /modules/{name} || exit 1")
    (root / f"load-{module}.sh").write_text("\n".join(commands) + "\n")

signed = (root / "modules/dummy.ko").read_bytes()
unsigned, _ = payload_and_signature(signed)
(root / "unsigned-dummy.ko").write_bytes(unsigned)
tampered = bytearray(signed)
tampered[-len(magic) - 13] ^= 1
(root / "tampered-dummy.ko").write_bytes(tampered)
print(f"Verified {len(modules)} module signatures against the kernel certificate")
