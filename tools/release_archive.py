"""Shared local archive format for P42-01 downloads."""

import gzip
import hashlib
import io
from pathlib import Path
import re
import tarfile


ROOT = Path(__file__).resolve().parents[1]


def validate_version(version: str) -> None:
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("expected a numeric release version")


def write_archive(
    output_dir: Path, name: str, files: dict[str, bytes], *, executables: tuple[str, ...] = ()
) -> Path:
    if not files["LICENSE"].strip():
        raise ValueError("missing license text")
    checksums = "".join(f"{hashlib.sha256(data).hexdigest()}  {file}\n" for file, data in files.items())
    entries = {**files, "SHA256SUMS": checksums.encode()}
    output_dir.mkdir(parents=True, exist_ok=True)
    path = output_dir / f"{name}.tar.gz"
    # Fixed tar and gzip metadata keep repeated packages of the same inputs identical.
    with path.open("wb") as raw, gzip.GzipFile(filename="", fileobj=raw, mode="wb", mtime=0) as gz:
        with tarfile.open(fileobj=gz, mode="w", format=tarfile.USTAR_FORMAT) as archive:
            for file, data in entries.items():
                entry = tarfile.TarInfo(f"{name}/{file}")
                entry.mode = 0o755 if file in executables else 0o644
                entry.size = len(data)
                archive.addfile(entry, io.BytesIO(data))
    return path
