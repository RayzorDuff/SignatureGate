# Appsmith export

SignatureGate-Appsmith is the canonical source for the Appsmith application.

The file appsmith/Rooted Psyche Membership Ops.json is a generated artifact.
Do not hand-edit it.

## Local regeneration

Clone both repositories side by side, then run:

    node scripts/appsmith-export.mjs \
      --source "$HOME/GitHub/SignatureGate-Appsmith" \
      --output "appsmith/Rooted Psyche Membership Ops.json"

The source repository may also be supplied through APPSMITH_SOURCE.

## GitHub Actions

The workflow "Regenerate Appsmith export" is manually dispatchable from the
SignatureGate Actions page. It checks out the requested
RayzorDuff/SignatureGate-Appsmith ref, regenerates the monolithic export,
validates its structure, and commits the generated file when it changes.

Once the Appsmith repository is writable by the GitHub integration, this can
be extended with an Appsmith-side trigger. For now the explicit manual
dispatch keeps the dependency clear.
