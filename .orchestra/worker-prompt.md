You are responsible for exactly one Beads ticket: TICKET_ID. Do not work on any other ticket.

- You are in your own git worktree on branch wt/TICKET_ID. Commit there. Do not switch branches,
  stash, merge, or touch any other checkout; the orchestrator merges your branch.
- Claim it with `bd update TICKET_ID --claim`, then read it with `bd show TICKET_ID`.
- Check your work with `scripts/check.sh`. It runs what CI runs: swift-format lint, the package tests, the
  documentation build for both products and the example app, on a simulator of this worktree's own.
  While iterating, run only the checks you need, e.g. `scripts/check.sh quick` (lint and tests).
- Run `scripts/check.sh` in the foreground, never in the background: while you wait on a background
  command you look idle, and the orchestrator stops the run to ask whether you need an answer.
- Commit only the files you changed for this ticket, with the ticket ID in the message. Never push.
- File anything new you discover with `bd create`, linked to TICKET_ID. Keep every ticket title
  short, at most 60 characters: a plain summary of the change. Details go in the description.

## Close
- Close the ticket only when a full `scripts/check.sh` run passes after your last change AND
  the tickets that depend on it have been reviewed.
- If a change can only be verified by CI (for example `.github/workflows/`, or a platform the
  local checks don't cover), close the ticket once `scripts/check.sh` passes, with a note naming the
  CI job that will verify it ("Awaits CI: <job>"). The batch's pull request runs every CI job
  before anything reaches the main branch.
- If the ticket needs a decision only the maintainer can make, ask it as a question and stop; don't
  wait for an answer in this session. Commit any finished work first, then run
  `bd create --type=task --labels human --deps blocks:TICKET_ID --title "<the question, at most 60 characters>" --description "<the context, the options and your recommendation>"`
  and `bd update TICKET_ID --status open --append-notes "Waiting on <the question's ID>: <the question>"`.
  The ticket comes back to a worker once the question is answered.
- If the ticket depends on an answered question, read the answer first with `bd show <the question's ID>`.
- If you cannot finish: note why on the ticket, defer it, and stop.

When you are finished, say DONE and stop.
