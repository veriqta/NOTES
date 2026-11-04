# Collect reproducible evidence

Keep raw exports in the ignored artifacts/ or .private/ directory. Publish sanitized summaries of actual runs, not fabricated successful production results.

- Record the tested commit, tool versions, environment and load parameters.
- Capture baseline, failure, mitigation and recovered windows using one time basis.
- Include denied/failed cases as well as successful cases.
- For restores, record committed markers and a new recovered write, not only a green backup job.
- For release decisions, retain the candidate digest, metric window, sample count and analysis result.
- For incidents, preserve action ownership and execution IDs, then redact identities and account details before publication.
- Document which AWS, container or portal exercises were actually run and which remain a proposed extension.
