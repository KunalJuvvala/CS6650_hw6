# HW6 — Performance Bottlenecks and Horizontal Scaling
Kunal Juvvala · CS6650 · Repo: <link>

## Part II — Finding the bottleneck (1 Fargate task, 0.25 vCPU / 512 MB)

**Setup.** 100,000 products in a `sync.Map`; each search checks exactly 100 products (header `X-Products-Checked: 100`), returns ≤20 results. Load: Locust `FastHttpUser`, no wait time, from Boston to us-west-2.

| | 5 users / 2 min | 20 users / 3 min |
|---|---|---|
| Requests/s | | |
| Median / p95 (Locust) | | |
| Server-side p95 (Grafana) | | |
| CPU avg / max | | |
| Memory | | |
| Failures | | |

*[Screenshot: Grafana RED + CloudWatch CPU/Memory side by side, 20-user test]*

**What happened as load increased.** <2–3 sentences: CPU hit ~100 %, RPS stopped growing, latency grew, memory flat.>

**Scale or optimize?** <Evidence: CPU-bound, fixed work per request, memory not the limit → needs more compute. If you ran 512 CPU: numbers.>

**App metrics vs CloudWatch.** <Where they agreed; what Grafana showed first (p95 rising before CPU maxed / errors in BAD_PCT test with flat CPU); CloudWatch 1-min granularity and lag.>

**Creative stress tests.** <1 line each: bad-request mix, 40 users, ramp, 512 CPU.>

## Part III — Horizontal scaling (ALB + auto scaling, 2–4 tasks, target 70 % CPU)

**Components.** ALB: <role>. Target group: <role>. Auto scaling: <role>.

**Core test (same 20-user load).**

| | Part II (1 task) | Part III (2 → N tasks) |
|---|---|---|
| Requests/s | | |
| Median / p95 | | |
| Failures | | |

Scaling timeline: test start → CPU > 70 % at __ → alarm at __ → desired count __ at __ → new target healthy at __ → p95 dropped at __.

*[Screenshot: CloudWatch (task count, CPU, ALB response time) + Grafana per-task req/s and CPU, same window]*

**Load distribution.** <Even split per task? From Grafana per-task panel.>

**CPU vs request-based trigger.** <Your answer + which dashboard signal moved first.>

**Resilience.** <Stopped 1 task: failures / recovery time. Stopped several. All health checks failing: ALB fail-open + ECS replacing tasks.>

**Exploration.** <One line per experiment: 50/70/90 % targets, min/max, cooldowns, ramp vs spike, more users.>

**Horizontal vs vertical.** <2–3 sentences of trade-offs.>

**Prediction for other load patterns.** <Spike: slow first minutes; ramp: tracks well; sustained > 4 tasks' capacity: back to Part II behavior.>
