#!/usr/bin/env python3
"""Monta uma pasta e ZIP somente com os arquivos públicos da página UbiAir."""
from pathlib import Path
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'Website'
OUTPUT = ROOT / 'build' / 'Website'
ARCHIVE = ROOT / 'build' / 'UbiAir-website.zip'
PUBLIC = ['index.html', 'styles.css', 'script.js']


def main():
    assets = sorted(path for path in (SOURCE / 'assets').rglob('*') if path.is_file())
    files = [SOURCE / name for name in PUBLIC] + assets
    if not assets:
        raise SystemExit('Assets ausentes.')
    for path in files:
        if path.is_symlink() or not path.is_file():
            raise SystemExit(f'Arquivo público ausente ou symlink não permitido: {path}')
    if OUTPUT.exists():
        if OUTPUT.is_symlink():
            raise SystemExit('Diretório de saída não pode ser symlink.')
        shutil.rmtree(OUTPUT)
    OUTPUT.mkdir(parents=True)
    for path in files:
        target = OUTPUT / path.relative_to(SOURCE)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
    with zipfile.ZipFile(ARCHIVE, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            archive.write(OUTPUT / path.relative_to(SOURCE), path.relative_to(SOURCE))
    print(f'Pasta pública: {OUTPUT}')
    print(f'ZIP para publicar: {ARCHIVE} ({ARCHIVE.stat().st_size:,} bytes)')


if __name__ == '__main__':
    main()
