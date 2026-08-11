# An example subscription server

The other side of [`docs/subscriptions.md`](../../docs/subscriptions.md), so that the
contract has two implementations that can be run against each other.

**This is an example, not the service.** No database, no accounts, no billing, no way to
add a subscriber except by editing a file. All of which the real thing needs, and none of
which teaches anybody the format.

```bash
cp nodes.example.json nodes.json   # then put real keys and a real token in it
go run . -config nodes.json -listen :8080
curl -i http://localhost:8080/sub/<token>
```

Put TLS in front of it. The document contains private keys, and this program speaks
plain HTTP because terminating TLS belongs to whatever is in front of it in any
deployment worth the name.

## It does not import the client

The types are declared here. Anyone implementing this contract will write their own, in
whatever language their service is in, and an example that only worked by importing
Caelo would be demonstrating the wrong thing — the module has no dependencies at all.

What keeps the two from drifting is `conformance.sh`, which serves a document and hands
every endpoint in it to the client's own reader:

```bash
./conformance.sh
```

It dials nothing — `caelo-probe -check` reads a configuration and describes what it
understood — so it needs no server, no network and no keys worth protecting. It checks
that both headers are present, that an unknown token is a `404`, and that each endpoint
parses, in the order it was served, because order is the contract's only expression of
priority.

That tests behaviour rather than shape, which is the stronger of the two: a shared struct
would prove the fields line up and nothing about whether the client can act on them.
