# Contribution webhook integration

The reviewed workflow receives successful external contribution events and associates them with canonical identities. A Participant or Contributor is a capacity an individual or company can hold; ingestion does not automatically create a Participant capacity.

Matching must use the approved source-identity and unique-contact rules. Ambiguous contact matches remain unresolved for an authorized reviewer. Reviewers can associate the event with an existing identity or establish the appropriate capacity through the application.

A stable source/reference pair provides database-enforced deduplication. Duplicate deliveries must return the existing result rather than insert a second contribution. External identity values must be normalized as text before database binding, including when a provider encodes them as numbers.

Authentication, workflow publication, destination review and any replay of an operational event require private operator validation. Keep the original event, signature configuration, contact values, source identifiers and transaction details outside Git. This guide intentionally contains no production replay command or transaction-output query.

Validate matching, unresolved cases, duplicate delivery and numeric external identity normalization with synthetic fixtures on the test environment. Record pass/fail and reviewed workflow revisions publicly; retain detailed input/output and audit evidence privately.

See [event responsibilities](EVENTS.md), [architecture](../docs/ARCHITECTURE.md) and the [release plan](../releases/v1.2.0/RELEASE_PLAN.md).
