# Contributing to Caelo

Thanks for wanting to help. This document covers the parts that are specific to Caelo;
everything else is ordinary GitHub.

## Before you write code

Open an issue first for anything beyond a small fix. It saves you from building something
we are already building, or something we have decided not to build — see the "Чего не
хотим" reasoning in the project notes, and ask if you are unsure.

## Licensing and provenance

Caelo is GPL-3.0-or-later. Contributions are accepted under that license.

**Do not copy code into Caelo from another project without raising it first.** Even
GPL-licensed code carries obligations, and several projects in this space add conditions
under GPLv3 §7 — non-commercial clauses, requirements that derivatives be forks of a
particular repository — that cannot be reconciled with shipping Caelo as plain free
software. Reading anything is fine. Copying needs a conversation first, and that applies
to code, `.proto` files, build scripts and configuration alike.

Anything under MIT, BSD or Apache-2.0 is usually fine to bring in, but it needs a row in
[ATTRIBUTION.md](ATTRIBUTION.md), its original copyright header preserved, and an
`SPDX-License-Identifier` line.

If you are porting an idea rather than a file, say so in the pull request. If you are
porting a file, say that too, and name the upstream commit.

## Sign your commits off

We use the [Developer Certificate of Origin](https://developercertificate.org/). It is a
short statement that you wrote the contribution, or otherwise have the right to submit it
under our license. There is no CLA and you keep your copyright.

Add a sign-off line to every commit:

```bash
git commit -s -m "your message"
```

That appends `Signed-off-by: Your Name <your@email.address>` using your git identity.
Use a real name and a working address.

## Branches

Name a branch after the issue it closes: `<number>-<short-slug>`, lower case, hyphens.
`10-selection-in-flutter`, not `selection-in-flutter`. GitHub links the two automatically
and anyone reading `git branch` can find out why the work exists without asking.

The slug describes the work, not the issue's title. An issue is often a question, and the
branch is the answer — sometimes the opposite of what the title proposed.

Work with no issue behind it takes a plain slug. If you cannot write one in a few words,
that is usually the branch telling you it is two changes.

## Pull requests

- One logical change per pull request.
- Write commit messages that explain *why*, not just what.
- Say how you tested it. For anything touching the tunnel, "it connected" is not a test —
  tell us what you verified and on which network.
- Rebase rather than merge when updating your branch.

## Reporting bugs

Use the issue templates. For anything that could put users at risk, do not open an issue at
all — read [SECURITY.md](SECURITY.md) instead.

Never paste a real subscription link, key or server address into an issue. Redact them.

## Code of conduct

Be decent to people. Harassment, and using this project to harm the people it exists to
protect, will get you removed. Raise problems privately with the maintainers.
