#!/usr/bin/env python3
"""Verifica o artefato local; não substitui validação ou revisão da Mac App Store."""
import argparse
import plistlib
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    return subprocess.run(args, check=True, capture_output=True).stdout


def verify(app):
    identity = dict(re.findall(r'static let (\w+) = "([^"]+)"',
                              (ROOT / 'Sources/UbiAirMenuBar/AppIdentity.swift').read_text()))
    contents = app / 'Contents'
    info = plistlib.loads((contents / 'Info.plist').read_bytes())
    for key, source in [('CFBundleIdentifier', 'bundleIdentifier'),
                        ('CFBundleShortVersionString', 'version'), ('CFBundleVersion', 'build')]:
        if info.get(key) != identity[source]:
            raise ValueError(f'Metadado divergente: {key}')
    if info.get('LSUIElement') is not True or info.get('CFBundleName') != 'UbiAir':
        raise ValueError('Nome ou configuração de barra de menus incorreta.')
    if info.get('LSApplicationCategoryType') != 'public.app-category.utilities':
        raise ValueError('Categoria da loja ausente.')

    executable = contents / 'MacOS' / info['CFBundleExecutable']
    arches = set(run('lipo', '-archs', str(executable)).decode().split())
    if not {'arm64', 'x86_64'}.issubset(arches):
        raise ValueError('O artefato Release deve conter arm64 e x86_64.')
    run('codesign', '--verify', '--deep', '--strict', str(app))
    entitlements = plistlib.loads(run('codesign', '-d', '--entitlements', '-', '--xml', str(app)))
    for key in ['com.apple.security.app-sandbox', 'com.apple.security.network.client']:
        if entitlements.get(key) is not True:
            raise ValueError(f'Permissão necessária ausente: {key}')
    allowed = {'com.apple.security.app-sandbox', 'com.apple.security.network.client',
               'com.apple.application-identifier', 'com.apple.developer.team-identifier',
               'keychain-access-groups'}
    if set(entitlements) - allowed:
        raise ValueError('O artefato contém permissões adicionais; revisar antes de distribuir.')
    if any('*' in group for group in entitlements.get('keychain-access-groups', [])):
        raise ValueError('Grupo de Chaves amplo; revisar antes de distribuir.')

    resources = contents / 'Resources'
    privacy = plistlib.loads((resources / 'PrivacyInfo.xcprivacy').read_bytes())
    expected = [{'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategoryUserDefaults',
                 'NSPrivacyAccessedAPITypeReasons': ['CA92.1']}]
    if privacy.get('NSPrivacyTracking') is not False or privacy.get('NSPrivacyAccessedAPITypes') != expected:
        raise ValueError('Manifesto de privacidade divergente da preparação atual.')
    if not info.get('CFBundleIconName') or not list(resources.glob('*.icns')):
        raise ValueError('Ícone de aplicativo não foi compilado.')
    if not (resources / 'THIRD_PARTY_NOTICES.md').is_file():
        raise ValueError('Avisos de terceiros ausentes.')
    print(f'UbiAir {identity["version"]} ({identity["build"]}): identidade, universal, sandbox, rede, ícone e manifesto verificados.')
    print('Validação local. Certificados, provisionamento e revisão da Apple permanecem pendentes.')
    print('A declaração de coleta de dados da loja ainda precisa ser revisada; este teste não a certifica.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', nargs='?', type=Path,
                        default=ROOT / 'build/XcodeSandbox/Build/Products/Release/UbiAir.app')
    args = parser.parse_args()
    try:
        verify(args.app)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'Verificação falhou: {error}\n')


if __name__ == '__main__':
    main()
