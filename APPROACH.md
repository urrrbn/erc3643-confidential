# Approach

## What would I explore if I had more time

- **Encrypted error codes.** I would explore attaching an encrypted error
  code to each transfer, decryptable by the sender and the auditor: the
  sender learns whether it was compliance or an insufficient balance, and
  the auditor starts seeing attempted breaches, which the current design
  hides: a blocked transfer reaches them as a zero.
- **A delegated auditor.** I have an interesting idea. A contract holding 
  the grants, operational keys rotating under it, and monitoring on the `Allowed` 
  events that would betray a key re-granting what it can see.
- **Upgradability.** Real ERC-3643 deployments are proxied suites.
- **`ERC7984Rwa` instead of plain `ERC7984`.** It would pull partial
  freeze back into scope, which the design cut, at the cost of an extra
  comparison per transfer.
- **Security.** I would definitely dedicate more time to the security side.

## AI assistance

I used Claude Code along with the official Zama skills, which were very
helpful. Thank you for putting those together, the research went much
easier because of them. After reading the litepaper and the docs and
scaffolding the design doc with my first questions, ideas and assumptions,
I could just ask Claude questions and get informed answers.

It also helped me deliver the build slice quickly, which freed up time to
think the design through more deeply. My verdict: in this type of work AI
is very useful for holding all the context and delivering build slices
quickly, and not very good at anything that requires judgement.
