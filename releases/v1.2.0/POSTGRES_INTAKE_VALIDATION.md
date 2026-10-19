# Disposable PostgreSQL 16 Intake validation

The runner in `scripts/validate_postgres_intake.py` creates a uniquely named disposable database on the selected Docker PostgreSQL server. It bootstraps only that database, reapplies atomic Intake twice, runs the rollback-only contract and exercises four real concurrent-session cases: commit/replay, rollback/retry, changed payload and changed owner. Each case verifies that exactly one enrollment, durable receipt and completion audit survives.

The second session must be observed waiting on a real PostgreSQL lock while the first has finished submitting and remains in its transaction. The driver then commits or rolls back the first. It does not substitute sleeps or serial calls for this contention assertion. Session/statement timeouts bound failure; private logs contain only synthetic fixtures from the disposable database.

It accepts only PostgreSQL major 16 and never bootstraps, migrates or queries operational tables in `signaturegate` or `signaturegate_test`. The maintenance connection reads server/session metadata and creates/removes the generated database. Cleanup is allowed only after this invocation successfully creates its unique database. Existing databases are never adopted or dropped. A cleanup failure requires reviewing private invocation.json and logs; do not drop any guessed database. A role without CREATEDB will fail before fixture application.

On the Linode, when this additional environment check is needed:

```bash
cd ~/signaturegate
git pull --ff-only
python3 scripts/validate_postgres_intake.py --container signaturegate-postgres
```

No `.env` loading, signing account, contact values or credentials are requested. Docker uses the same database role/container as the existing release commands. Detailed logs remain under `~/signaturegate-release-evidence/v1.2.0/postgres-intake` with private permissions; stdout returns technical version, case names and pass flags only after cleanup succeeds. Do not commit raw logs. Failure returns nonzero.

This fresh disposable check proves SQL/replay/rollback/concurrency semantics on PostgreSQL 16. It is not a production restore, owner/grant proof, current-definition review, workflow isolation rehearsal, Appsmith renderer test or external delivery acceptance. Those release gates remain open. CI execution and operator environment evidence must be recorded separately in STATUS.md.
