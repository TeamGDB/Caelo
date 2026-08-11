# Security Policy

Caelo is a censorship-circumvention tool. For some of the people who use it, a bug is not
an inconvenience — it is exposure. We treat vulnerability reports accordingly.

## Reporting a vulnerability

**Do not open a public issue.**

Use GitHub's [private vulnerability reporting](https://github.com/TeamGDB/Caelo/security/advisories/new)
on this repository. If that is not available to you, email `TODO: security contact`.

If you need to encrypt your report, our PGP key is `TODO: key fingerprint and location`.

Please include:

- what you found and why it matters;
- the version, platform and protocol in use;
- steps to reproduce, or a proof of concept;
- whether the issue is already public anywhere.

You do not need to prove impact to report something. A hunch about a traffic-analysis
weakness is worth sending.

## What to expect

- We acknowledge reports within **72 hours**.
- We aim to have an assessment back to you within **7 days**.
- We will tell you honestly whether we plan to fix it, and when.
- We publish a security advisory once a fix ships, crediting you unless you would rather
  stay anonymous.

We will not ask you to stay quiet indefinitely. If we cannot fix an issue in a reasonable
time, we would rather disclose it than leave users believing they are protected.

## Scope

In scope: everything in this repository — the app and the core in [`core/`](core) — along
with our build and release pipeline and our subscription delivery service.

Of particular interest:

- traffic that distinguishes Caelo from ordinary traffic, or one Caelo user from another;
- leaks outside the tunnel — DNS, IPv6, traffic during connect/disconnect or on network
  change;
- anything that exposes which servers a user connects to;
- key, credential or subscription-link handling;
- weaknesses in signing, notarization or release integrity.

Out of scope: vulnerabilities in upstream projects that do not affect Caelo as shipped —
report those to sing-box, AmneziaWG or WireGuard directly. Also out of scope: denial of
service against our own infrastructure, and social engineering of the maintainers.

## Supported versions

Only the latest release is supported. There are no releases yet.

## Safe harbour

We will not pursue legal action against anyone acting in good faith under this policy:
research on your own installation, no access to other people's data, no service disruption,
and a private report before disclosure. If you are unsure whether something is in bounds,
ask first.
