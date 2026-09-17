#!/usr/bin/env python3
"""Replay both patch routes in full clean checkouts and compare complete trees.

Example:
  python3 verify_replay.py --source /path/to/kernel --output /tmp/patch-check

Does not build, touch the source worktree, initialize subprojects, or use network.
Checkouts may share source Git objects and should be kept with that database.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess

BASE = '4d69a3ed9a176152e85580352723c308f29cbfcb'
BUILD = '30426bf8a3e1b57596ee741086e2c491617c58d1'
DOC = 'vendor/qcom/opensource/wlan/qcacld-3.0/docs/peach-native-injection.md'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--target', default='HEAD')
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    patches = Path(__file__).resolve().parent
    output.mkdir(parents=True, exist_ok=True)
    log = (output / 'commands.log').open('x')

    def run(argv, cwd=source):
        log.write(json.dumps({'cwd': str(cwd), 'argv': list(map(str, argv))})+'\n')
        log.flush()
        result = subprocess.run(list(map(str, argv)), cwd=cwd, capture_output=True)
        log.write(result.stderr.decode(errors='replace'))
        log.flush()
        if result.returncode:
            raise RuntimeError(f'{argv}: {result.returncode}: {result.stderr.decode(errors="replace")}')
        return result.stdout

    def git(*argv, cwd=source):
        return run(['git', *argv], cwd)

    def rev(value, cwd=source):
        return git('rev-parse', value, cwd=cwd).decode().strip()

    def sha(path):
        with path.open('rb') as stream:
            return hashlib.file_digest(stream, 'sha256').hexdigest()

    target = rev(args.target)
    target_tree = rev(target+'^{tree}')
    commits = git('rev-list', '--reverse', BASE+'..'+target).decode().splitlines()
    mail = [patches/'exported'/s for s in (patches/'exported/series').read_text().splitlines() if s and not s.startswith('#')]
    combined = [(patches/s).resolve() for s in (patches/'series').read_text().splitlines() if s and not s.startswith('#')]
    assert len(commits) == len(mail)
    for commit, patch in zip(commits, mail):
        assert patch.read_text().splitlines()[0] == f'From {commit} Mon Sep 17 00:00:00 2001', patch

    # This repo historically tracks .repo, including its own active Git index.
    # Compare committed metadata in replay trees; never restore live .repo files.
    status = [s for s in git('status', '--porcelain=v1', '-z', '--untracked-files=no').decode().split('\0') if s]
    assert all(s[3:].startswith('.repo/') for s in status), status
    assert not git('diff', '--cached', '--name-only').strip()
    assert rev('HEAD') == target
    source_manifest = git('ls-tree', '-r', '-z', target)
    checked_files = 0
    subprojects = []
    for entry in source_manifest.split(b'\0'):
        if not entry:
            continue
        meta, raw_path = entry.split(b'\t', 1)
        mode, kind, oid = meta.decode().split()
        path = raw_path.decode()
        full = source/path
        if kind == 'commit':
            actual = rev('HEAD', full)
            tracked = git('status', '--porcelain=v1', '--untracked-files=no', cwd=full).decode().strip()
            assert actual == oid and not tracked, (path, actual, oid, tracked)
            subprojects.append({'path': path, 'revision': oid, 'tracked_worktree_clean': True})
        elif not path.startswith('.repo/'):
            if mode == '120000':
                assert full.is_symlink(), path
                contents = os.fsencode(os.readlink(full))
            else:
                assert full.is_file() and not full.is_symlink(), path
                contents = full.read_bytes()
                assert bool(full.stat().st_mode & stat.S_IXUSR) == (mode == '100755'), path
            actual = hashlib.sha1(b'blob '+str(len(contents)).encode()+b'\0'+contents).hexdigest()
            assert actual == oid, path
            checked_files += 1

    report = {'base': BASE, 'target_commit': target, 'target_tree': target_tree,
              'mail_patch_count': len(mail), 'method': 'full independent checkouts; git am and git apply --index; complete tree equality',
              'source_file_bytes_and_modes_checked': checked_files, 'subprojects': subprojects,
              'source_live_repo_metadata_status': status,
              'scope': 'All committed blobs, file modes, symlinks and gitlink revisions. Live .repo metadata, untracked and ignored build outputs are not source equivalence claims.',
              'routes': {}, 'patch_sha256': {str(p.relative_to(patches)) if p.is_relative_to(patches) else os.path.relpath(p, patches): sha(p) for p in mail+combined},
              'build_started': False, 'device_operations': False}
    for route, inputs in [('mail', mail), ('combined', combined)]:
        checkout = output/route
        assert not checkout.exists(), checkout
        run(['git', 'clone', '--shared', '--no-checkout', source, checkout], output)
        git('config', 'user.name', 'Patch replay verification', cwd=checkout)
        git('config', 'user.email', 'patch-replay@example.invalid', cwd=checkout)
        git('config', 'core.autocrlf', 'false', cwd=checkout)
        git('checkout', '--detach', BASE, cwd=checkout)
        assert not git('status', '--porcelain', '--untracked-files=all', cwd=checkout).strip()
        steps = []
        print(f'{route}: clean baseline checkout ready', flush=True)
        for i, patch in enumerate(inputs):
            if route == 'mail':
                git('-c', 'commit.gpgsign=false', 'am', patch, cwd=checkout)
                tree = rev('HEAD^{tree}', checkout)
                expected = rev(commits[i]+'^{tree}')
                assert tree == expected, (patch, tree, expected)
                assert git('show', '-s', '--format=%B', 'HEAD', cwd=checkout) == git('show', '-s', '--format=%B', commits[i])
                steps.append({'patch': patch.name, 'source_commit': commits[i], 'replay_commit': rev('HEAD', checkout), 'tree': tree})
            else:
                git('apply', '--check', '--index', patch, cwd=checkout)
                git('apply', '--index', patch, cwd=checkout)
                steps.append({'patch': os.path.relpath(patch, patches), 'tree': git('write-tree', cwd=checkout).decode().strip()})
        if route == 'combined':
            git('-c', 'commit.gpgsign=false', 'commit', '-m', 'Verify combined native monitor patch application', cwd=checkout)
        tree = rev('HEAD^{tree}', checkout)
        assert tree == target_tree, (route, tree, target_tree)
        assert not git('status', '--porcelain', '--untracked-files=all', cwd=checkout).strip()
        manifest = git('ls-tree', '-r', '-z', 'HEAD', cwd=checkout)
        assert manifest == source_manifest
        (output/(route+'-tree-manifest.z')).write_bytes(manifest)
        report['routes'][route] = {'checkout': str(checkout), 'tree': tree, 'clean': True, 'manifest_sha256': hashlib.sha256(manifest).hexdigest(), 'steps': steps}
        print(f'{route}: all patches applied, complete tree {tree}, clean', flush=True)

    changes = git('diff', '--name-only', BUILD, target).decode().splitlines()
    assert changes == [DOC], changes
    assert not git('diff', BUILD, target, '--', '.', ':!'+DOC).strip()
    report['v8_runtime_unchanged'] = True
    report['changes_since_v8_build'] = changes
    report['match'] = True
    (output/'verification.json').write_text(json.dumps(report, indent=2, ensure_ascii=False)+'\n')
    log.close()
    print(f'PASS: source worktree, {len(commits)} commits, both patch routes and full manifests agree.', flush=True)


if __name__ == '__main__':
    main()
