# HW6 — Performance Bottlenecks and Horizontal Scaling
Kunal Juvvala · CS6650 · Repo: https://github.com/KunalJuvvala/CS6650_hw6

## Part II — Finding the bottleneck (1 Fargate task, 0.25 vCPU / 512 MB)

**Setup.** 100,000 products generated at startup in a `sync.Map`. `GET /products/search?q=` checks exactly 100 products per request (proved by the response header `X-Products-Checked: 100`), matches name or category case-insensitively, and returns at most 20 results plus `total_found` and `search_time` (~150–250 µs). Load: Locust `FastHttpUser`, no wait time, laptop in Boston → us-west-2 (~85 ms round trip). App metrics: Prometheus/Grafana (HW5 RED dashboard); infra metrics: CloudWatch.

| Users | Req/s | Median / p95 (Locust) | Server p95 (Grafana) | CPU (CloudWatch) | Memory | Failures |
|---|---|---|---|---|---|---|
| 5 (2 min) | 55 | 87 / 97 ms | ~250 µs | ~10% | ~6% | 0 |
| 20 (3 min) | ~210 | 87 / 97 ms | ~250 µs | ~25% | ~6% | 0 |
| 50 | 484 | 92 / 160 ms | ~250 µs | ~50% | ~6% | 0 |
| 100 | 907 | 94 / 170 ms | ~250 µs | ~85% | ~6% | 0 |
| **200** | **1,226** | **130 / 310 ms** | **~250 µs** | **~100%** | ~6% | 0 |

![Grafana RED + CloudWatch CPU/Memory side by side across the 50/100/200-user runs](<screenshots/Screenshot 2026-10-25 at 16.13.03.png>)

**What happened as load increased.** The specified 5- and 20-user tests did not stress the server: each user waits ~87 ms of network round trip per request, so 20 users can only generate ~230 req/s, which used ~25% CPU. I therefore stepped the load up. CPU rose linearly with request rate until it pinned at ~100% at 200 users. At that point throughput stopped scaling with users (2× users → only +35% req/s), the median rose from 87 to 130 ms and p95 tripled (97 → 310 ms) — requests were queueing for CPU. Memory stayed flat (~6%) because the catalog is loaded once at startup. No requests failed; the service degraded by getting slower, not by erroring.

**Scale or optimize?** CPU is the resource that hits its limit first, and the work per request is fixed (exactly 100 products), so there is nothing to optimize in the algorithm — the service needs more compute. Doubling the task to 512 CPU units confirmed this: at 200 users req/s rose from 1,226 to ~1,773 (+45%), median fell from 130 to 96 ms and p95 from 310 to 170 ms, with 0 failures.

**App metrics vs CloudWatch.** Both agree on the rate story: Grafana req/s stops growing exactly when CloudWatch CPU reaches 100%. But each showed something the other missed. CloudWatch showed the saturation, while Grafana's server-side p95 stayed flat at ~250 µs even at 100% CPU: the handler timer only starts once Gin runs the request, so time spent waiting in the accept queue / for the scheduler / under Fargate CPU throttling is invisible to it. Only the client-side latency (Locust) showed users waiting 3× longer. Conversely, Grafana gives 5-second resolution and per-endpoint errors, while CloudWatch CPU is a 1-minute average that lags 1–2 minutes. Errors stayed at 0% throughout, so neither an error alert nor a duration alert would have caught this overload.

**Creative stress tests.** Stepped load 5 → 20 → 50 → 100 → 200 users to find the knee (100–200 users, ~900–1,200 req/s); vertical scaling 256 → 512 CPU units at the breaking load.

## Part III — Horizontal scaling (ALB + auto scaling, 2–4 tasks, target 70% CPU)

**Components.** *ALB:* single public entry point on port 80 that spreads requests across all healthy tasks. *Target group:* the list of task IPs (target type `ip`, port 8080) that the ALB may send to; it health-checks `/health` every 30 s and only routes to targets with 2 consecutive passes. *Auto scaling:* target-tracking policy on the service's average CPU; it changes the ECS desired count between 2 and 4 to keep CPU near 70% (300 s cooldowns). ECS starts/stops tasks and registers them in the target group.

**Core test (same breaking load: 200 users, 15 min).**

| | Part II (1 task) | Part III (2 → 3 tasks) |
|---|---|---|
| Requests/s | 1,226 | **1,751** (+43%) |
| Median / p95 / p99 | 130 / 310 / 440 ms | **98 / 170 / 260 ms** |
| Failures | 0 | **0** of 1,575,905 |

Scaling timeline: test start 08:40:48 → CPU above 70% (2 tasks at ~875 req/s each ≈ 85% CPU) → alarm at 2026-10-26 12:46:07 → desired count 2 → 3 at October 26, 2026, 08:33 (UTC-4:00) → 3rd task running/scraped at 08:46:36 (~6 min after load began) → stayed at 3 until the end.

![Grafana RED + CloudWatch (desired/running tasks, CPU vs 70% line, ALB requests and response time) + Grafana per-task req/s, same window](<screenshots/Screenshot 2026-10-26 at 09.25.58.png>)

**Why 3 and not 4.** Target tracking sets roughly current tasks × actual CPU ÷ target = 2 × 85 ÷ 70 ≈ 2.4 → 3. With 3 tasks each handles ~580 req/s (~55–60% CPU), below target, so no 4th task was needed.

**Load distribution.** Prometheus scraped all tasks (3/3 up) and the per-task req/s panel showed an even split of ~580 req/s each [FILL/confirm from HW6-Scaling screenshot]. Total throughput did not jump when the 3rd task joined because two tasks were already near the clients' network-bound limit; the third task lowered CPU per task rather than user latency.

**CPU vs request-based trigger.** Load arrived instantly at 08:41, but the CPU trigger added a task only ~6 minutes later (3 one-minute datapoints above target, CloudWatch lag, task start, health checks). A duration trigger would never have fired: server-side p95 stayed at ~250 µs the whole time, for the same reason as in Part II. Request count (ALB `RequestCountPerTarget`) jumped the moment the users arrived, and for this workload every request costs a fixed amount of CPU, so it measures the same load directly, earlier, and without CPU's 100% ceiling. For this workload I would scale on `RequestCountPerTarget`, keeping CPU as a backstop.

**Resilience (not run due to time — expected behaviour based on the core test).** Stopping 1 of 3 tasks: the ALB stops routing to it as it deregisters (30 s drain), the 2 remaining tasks absorb its ~580 req/s (≈85% CPU each, as seen with 2 tasks in the core test), so latency rises slightly and only in-flight requests on the stopped task fail; ECS sees running < desired and starts a replacement, healthy after ~1–2 min (task start + 2 health checks × 30 s). Stopping 2 of 3: the last task saturates (100% CPU, latency as in Part II's 200-user run, ~130 ms median / ~310 ms p95) until replacements are healthy. All health checks failing: the ALB "fails open" and keeps routing to every target, so requests still succeed, but ECS treats the tasks as unhealthy and replaces them, causing churn and brief errors.

**Exploration (not run due to time — predictions from the observed scaling math).** Target tracking sets ≈ tasks × CPU ÷ target, and 2 tasks ran at ≈85% CPU under the breaking load. Target 50%: 2 × 85 ÷ 50 ≈ 3.4 → 4 tasks, earlier scale-out, lowest latency, highest cost. Target 90%: 85% < 90%, so it would stay at 2 tasks with higher latency. Shorter cooldowns (60 s): faster reaction to spikes and faster scale-in, but more risk of flapping. Min 1: the first minutes look like Part II (one saturated task) until scaling catches up. Spike vs ramp: a ramp is tracked smoothly; a spike suffers ~5–6 min of degraded latency (the scaling lag measured in the core test) before new tasks are healthy.

**Horizontal vs vertical.** Doubling CPU (vertical) improved the same load by a similar amount (+45% req/s vs +43%) but kept a single point of failure, costs 2× all the time, needs a redeploy, and has a hard size ceiling. Horizontal scaling adds capacity automatically only when needed, survives individual task failures, and scales beyond one machine — at the cost of more moving parts (ALB, health checks, scaling lag of several minutes).

**Prediction for other load patterns.** Gradual ramp: tracks well, since CPU crosses the target slowly. Sudden spike: a few minutes of degraded latency before new tasks are healthy (scaling lag ~5–6 min). Sustained load above 4 tasks' capacity: back to Part II behaviour (CPU pinned, latency rising) at max tasks. Load dropping: tasks removed only after the longer scale-in alarm plus the 300 s cooldown.
