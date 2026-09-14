---
name: security-review
description: Invoke before merging a change that touches authentication, authorization, sessions, secrets, API keys, user input parsing, file uploads, SQL or NoSQL queries, shell command construction, serialization, template rendering, or network boundaries — this list is the condition, and a change touching any of it gets the review without exception. Triggers on words like "auth", "login", "token", "password", "query", "upload", "render", "exec", "eval", "deserialize", "webhook", "CORS". Runs an OWASP-aligned checklist; a change is "safe" only after tracing each input from source to sink, not after reading the diff. Skip when none of those surfaces appear in the change.
---

# Security Review

Run this review on any change that touches:
- Authentication, authorization, session handling.
- Secrets, credentials, API keys, tokens.
- User input parsing (query strings, form data, JSON payloads, file
  uploads).
- Network boundaries (incoming requests, outgoing requests, webhooks).
- Permission checks, role-based access, multi-tenant data isolation.
- SQL, NoSQL, or any query builder.
- Shell command construction.
- Serialization / deserialization (JSON, YAML, pickle, XML).

## Procedure

1. **Identify the trust boundary.** Where does untrusted input enter
   the code path you changed? Trace it forward.
2. **Run the OWASP checklist** below against the changed code.
3. **Report findings** with severity: `blocker`, `should-fix`, or
   `note`. Only `blocker` findings should prevent merge.

## OWASP-aligned checklist

- **Injection.** User input concatenated into SQL, NoSQL, shell, or
  `eval`? Must use parameterized queries or strict escaping.
- **Broken authentication.** Session tokens in URLs? Passwords in
  logs? Missing rate limits on login? Weak token generation?
- **Sensitive data exposure.** Secrets in error messages, logs, or
  API responses? Unencrypted transport? Missing encryption at rest
  for sensitive fields?
- **XXE / deserialization.** External entities allowed in XML
  parsers? Untrusted data passed to `pickle.loads`, `yaml.load`,
  `unserialize`?
- **Broken access control.** Missing permission check on a sensitive
  endpoint? IDOR (Insecure Direct Object Reference)? Tenant isolation
  relying on client-side filters?
- **Security misconfiguration.** Default credentials? Debug mode
  enabled in production? Permissive CORS (`*`)? Missing security
  headers (CSP, HSTS, X-Frame-Options)?
- **XSS.** User input rendered into HTML without escaping? Raw HTML
  insertion (`innerHTML`, `dangerouslySetInnerHTML`, `v-html`)?
- **Insecure deserialization.** See XXE above.
- **Vulnerable dependencies.** New dependency added? Check for known
  CVEs. Pin to specific version.
- **Insufficient logging.** Auth failures, permission denials, and
  access to sensitive endpoints must be logged.

## Secret handling

- Secrets never belong in code, not even as "temporary" defaults.
- Secrets never belong in commit messages, test fixtures, or error
  messages.
- `.env`, `*.key`, `credentials*`, and private keys must be
  gitignored and never read without explicit user instruction.

## Known failure patterns to avoid

- **Do not** declare a change "safe" based only on reading the diff.
  Trace the input from its source to its use.
- **Do not** assume ORM use alone prevents injection. Raw query
  fragments inside ORM calls still inject.
- **Do not** ignore a `blocker` finding because "the existing code
  already has this issue". If you're touching it, fix it.
- **Do not** add defensive validation that duplicates framework
  guarantees. Validate at the boundary, not at every layer.
- **Do not** log secrets when debugging. Redact them before they reach
  any log sink.
- **Do not** trust client-side validation. Always validate server-side.
