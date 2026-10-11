# Automation events

This is an event responsibility guide, rather than proof that every workflow is deployed. Validate published workflow revisions, credentials and destinations privately before release.

| Event | Responsibility |
| --- | --- |
| Identity created or updated | Normalize contact information under the canonical individual/company model; keep Participant and Contributor capacities separate from access roles. |
| Agreement signature completed | Record signed status and evidence through the reviewed signature callback. Duplicate callbacks must not duplicate the transition. |
| Paper agreement evidence submitted | Store its evidence reference and record verification through the authorized review path. |
| Gated action requested | Verify required signed agreements and access before changing state; audit both accepted and denied requests. |
| External contribution received | Deduplicate the source event, associate the correct identity through reviewed matching and record an audit event. |
| Confirmed cash deposit submitted for accounting | Use the separately released RootedOps dependency and preserve the stable source event across retries. |

External callbacks remain responsible for their audit writes because those events originate outside the application UI. A callback's successful delivery does not by itself prove completion of the underlying business transition.

Use synthetic data for development. Keep contact values, operational records, credentials, request/response bodies and screenshots out of Git. Public acceptance records contain versions, source revisions and pass/fail outcomes only.

See [signature integration](DOCUMENSO_INTEGRATION.md), [contribution integration](GIVEBUTTER_INTEGRATION.md), [cash-deposit dependency](CASH_DEPOSIT_ERP_INTEGRATION.md) and [architecture](../docs/ARCHITECTURE.md) for the current integration boundaries. Facilitator/Spiritual Practitioner is a functional access role; it does not define a person's identity or Participant capacity.
