# FitFight

Challenge your friends. Winner takes the glory.

Cloud-only iOS app: Marc talks from his phone, a Cursor cloud agent codes, GitHub Actions (`macos-26`) ships to TestFlight. No home Mac.

**v0.3** ports the approved design: four tabs, dark/light, 10 accents. Spec in [`docs/design/source/`](docs/design/source/README.md).

## Agents

Read [`AGENTS.md`](AGENTS.md) and [`docs/`](docs/README.md) before changing anything. That’s the project memory for parallel chats. Ideas live in the [Notion Product Backlog](https://app.notion.com/p/3d38907c7ecf816facdff36cb59f463e) (FitFight rows only). The production architecture is [`docs/system-design.md`](docs/system-design.md); follow it, don’t build all of it. First real Metric is Steps.

## Marc

Talk to the agent. Test ~30 min/day. Evening: TestFlight → Update. App pushes upload by themselves.

Do not paste the `.p8` into chat. Setup (Apple app, API key, GitHub secrets) is already done — see `docs/shipping.md`.
