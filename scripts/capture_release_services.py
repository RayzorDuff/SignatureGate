#!/usr/bin/env python3
"""Collect deployed image/version metadata without emitting credentials."""
import argparse
import hashlib
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

SERVICES = ['signaturegate-postgres', 'appsmith', 'n8n', 'erpnext-backend', 'documenso', 'listmonk', 'nocodb']
URL_KEYS = {'WEBHOOK_URL', 'N8N_EDITOR_BASE_URL', 'DOCUMENSO_BASE_URL', 'NOCODB_BASE_URL',
            'LISTMONK_PUBLIC_URL', 'LISTMONK_API_BASE_URL', 'ERPNEXT_PUBLIC_URL', 'ERPNEXT_INTERNAL_URL'}
VALUE_KEYS = {'N8N_HOST', 'N8N_PORT', 'N8N_PROTOCOL', 'ERPNEXT_SITE_NAME', 'LISTMONK_DEFAULT_LIST_ID',
              'LISTMONK_NEWSLETTER_LIST_ID', 'LISTMONK_MEMBER_COMMUNICATIONS_LIST_ID', 'LISTMONK_CONTRIBUTOR_LIST_ID'}


def command(args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def target(value):
    if not isinstance(value, str):
        return '<unresolved target; review in application>'
    if not value or '{{' in value or value.startswith('='):
        return '<dynamic or unset; review in application>'
    try:
        url = urlsplit(value)
        if url.scheme not in ('http', 'https') or not url.hostname:
            return '<unresolved target; review in application>'
        host = url.hostname
        if ':' in host:
            host = f'[{host}]'
        if url.port:
            host += f':{url.port}'
        return urlunsplit((url.scheme, host, url.path, '', ''))
    except ValueError:
        return '<invalid target; review in application>'


def summary(workflows, provenance):
    rows = []
    for workflow in workflows:
        nodes = []
        for node in workflow.get('nodes', []):
            parameters = node.get('parameters', {})
            item = {'name': node.get('name'), 'type': node.get('type'), 'disabled': node.get('disabled', False),
                    'credentials': {kind: {k: v.get(k) for k in ('id', 'name')} if isinstance(v, dict) else {'status': 'review binding in n8n'}
                                    for kind, v in (node.get('credentials') or {}).items()}}
            if str(node.get('type', '')).endswith('.webhook'):
                item['webhook'] = {k: parameters.get(k) for k in ('path', 'httpMethod', 'authentication')}
            if 'url' in parameters:
                item['target'] = target(parameters['url'])
            if 'query' in parameters:
                item['query_sha256'] = hashlib.sha256(str(parameters['query']).encode()).hexdigest()
            nodes.append(item)
        definition = {k: workflow.get(k) for k in ('nodes', 'connections', 'settings')}
        rows.append({k: workflow.get(k) for k in ('id', 'name', 'active', 'versionId', 'activeVersionId', 'updatedAt')}
                    | {'definition_sha256': hashlib.sha256(json.dumps(definition, sort_keys=True).encode()).hexdigest(), 'nodes': nodes})
    return {'captured_at': datetime.now(timezone.utc).isoformat(), 'provenance': provenance,
            'credential_targets': 'not included in workflow descriptors; verify in n8n Credentials', 'workflows': rows}


def capture_workflows(output):
    help_text = command(['sudo', 'docker', 'exec', '-u', 'node', 'n8n', 'n8n', 'export:workflow', '--help'])
    published_supported = bool(re.search(r'--published\b', help_text))
    directory = command(['sudo', 'docker', 'exec', '-u', 'node', 'n8n', 'sh', '-c',
                         'umask 077; mktemp -d /tmp/signaturegate-release.XXXXXX']).strip()
    if not re.fullmatch(r'/tmp/signaturegate-release\.[A-Za-z0-9]+', directory):
        raise ValueError('Unexpected temporary directory; stopping')
    try:
        for label, extra in [('draft', [])] + ([('published', ['--published'])] if published_supported else []):
            path = directory + '/' + label + '.json'
            command(['sudo', 'docker', 'exec', '-u', 'node', 'n8n', 'n8n', 'export:workflow', '--all', *extra, '--output=' + path])
            raw = command(['sudo', 'docker', 'exec', '-u', 'node', 'n8n', 'cat', path])
            workflows = json.loads(raw)
            if not isinstance(workflows, list):
                raise ValueError('Unexpected workflow export shape')
            description = 'published/active export' if label == 'published' else 'draft export; active flag alone does not prove running version'
            (output / f'n8n-workflows-{label}.json').write_text(json.dumps(summary(workflows, description), indent=2) + '\n')
        (output / 'n8n-publication-status.json').write_text(json.dumps({
            'published_export_supported': published_supported,
            'live_review_required': True,
            'note': 'Confirm running workflow revision/activation in n8n; draft export is not publication evidence.'
        }, indent=2) + '\n')
    finally:
        # Only the freshly created temporary export directory is removed.
        command(['sudo', 'docker', 'exec', '-u', 'node', 'n8n', 'rm', '-r', directory])


def capture_services(output, rootedops):
    rows = []
    for name in SERVICES:
        try:
            info = json.loads(command(['sudo', 'docker', 'inspect', name]))[0]
            image = json.loads(command(['sudo', 'docker', 'image', 'inspect', info['Image']]))[0]
            labels = image.get('Config', {}).get('Labels') or {}
            values = {}
            for entry in info.get('Config', {}).get('Env') or []:
                key, _, value = entry.partition('=')
                if key in URL_KEYS:
                    values[key] = target(value)
                elif key in VALUE_KEYS:
                    values[key] = value
            rows.append({'container': name, 'image_reference': info['Config']['Image'], 'image_id': info['Image'],
                         'repo_digests': image.get('RepoDigests', []), 'running': info['State']['Running'],
                         'started_at': info['State']['StartedAt'], 'image_version': labels.get('org.opencontainers.image.version'),
                         'image_revision': labels.get('org.opencontainers.image.revision'), 'service_targets': values})
        except subprocess.CalledProcessError:
            rows.append({'container': name, 'status': 'unavailable; requires operator review'})
    (output / 'deployed-services.json').write_text(json.dumps({'captured_at': datetime.now(timezone.utc).isoformat(), 'services': rows}, indent=2) + '\n')
    for name, cmd, filename in [
        ('n8n', ['n8n', '--version'], 'n8n-version.txt'),
        ('erpnext-backend', ['bench', 'version'], 'erpnext-app-versions.txt'),
    ]:
        args = ['sudo', 'docker', 'exec']
        args += ['-u', 'node'] if name == 'n8n' else ['-u', 'frappe', '-w', '/home/frappe/frappe-bench']
        try:
            (output / filename).write_text(command([*args, name, *cmd]))
        except subprocess.CalledProcessError:
            (output / filename).write_text('unavailable; requires operator review\n')
    source = {'path': str(rootedops), 'meaning': 'host source checkout; not proof of deployed code'}
    try:
        source['sha'] = command(['git', '-C', str(rootedops), 'rev-parse', 'HEAD']).strip()
        source['branch'] = command(['git', '-C', str(rootedops), 'branch', '--show-current']).strip()
        source['working_tree'] = command(['git', '-C', str(rootedops), 'status', '--porcelain'])
        source['version'] = (rootedops / 'VERSION').read_text().strip()
    except (OSError, subprocess.CalledProcessError):
        source['status'] = 'source checkout unavailable'
    (output / 'rootedops-source.json').write_text(json.dumps(source, indent=2) + '\n')
    # Compare mounted RootedOps app source to the host checkout, independent of image tag.
    local_base = rootedops / 'erpnext/apps/rootedops_payroll'
    if local_base.is_dir():
        files = command(['git', '-C', str(rootedops), 'ls-files', 'erpnext/apps/rootedops_payroll']).splitlines()
        local = {str(Path(f).relative_to('erpnext/apps/rootedops_payroll')): hashlib.sha256((rootedops / f).read_bytes()).hexdigest()
                 for f in files if (rootedops / f).is_file()}
        code = "import hashlib,json;from pathlib import Path;root=Path('/home/frappe/frappe-bench/apps/rootedops_payroll');names=json.loads(input());print(json.dumps({n:hashlib.sha256((root/n).read_bytes()).hexdigest() if (root/n).is_file() else None for n in names}))"
        try:
            run = subprocess.run(['sudo', 'docker', 'exec', '-i', 'erpnext-backend', 'python3', '-c', code],
                                 input=json.dumps(list(local)), capture_output=True, text=True, check=True)
            actual = json.loads(run.stdout)
            changed = [name for name in local if actual.get(name) != local[name]]
            comparison = {'tracked_files_checked': len(local), 'missing_or_changed': changed,
                          'scope': 'tracked source files only; extra deployed files, dependencies and runtime configuration require review',
                          'host_source_sha': source.get('sha')}
        except (ValueError, subprocess.CalledProcessError):
            comparison = {'status': 'deployed source comparison unavailable; requires review'}
        (output / 'rootedops-deployed-source-comparison.json').write_text(json.dumps(comparison, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--rootedops', type=Path, default=Path.home() / 'RootedOps')
    parser.add_argument('--workflows', action='store_true')
    args = parser.parse_args()
    args.evidence.mkdir(parents=True, exist_ok=True)
    if args.workflows:
        capture_workflows(args.evidence)
    else:
        capture_services(args.evidence, args.rootedops)
    print(f'Evidence written to {args.evidence}; live review remains pending')


if __name__ == '__main__':
    main()
