"""
HW6 load test for GET /products/search (FastHttpUser, minimal wait time).

Test 1 (baseline):       locust -f locustfile_search.py --host http://<IP>:8080 -u 5  -r 5  -t 2m
Test 2 (breaking point): locust -f locustfile_search.py --host http://<IP>:8080 -u 20 -r 20 -t 3m
Part III: same command, but --host http://<ALB-DNS-NAME>   (port 80, no :8080)

Add --headless --csv results/<name> --html results/<name>.html to run without the web UI.
"""
import os
import random

from locust import FastHttpUser, between, task

# Mix of terms that hit names ("alpha", "product", digits) and categories ("electro", "book").
SEARCH_TERMS = [
    "electro", "book", "home", "garden", "toys", "sports",
    "alpha", "beta", "gamma", "product", "1", "42", "zzz-no-match",
]

WAIT_MAX = float(os.getenv("WAIT_MAX", "0"))  # 0 = no think time
# Optional "creative" test: % of requests sent WITHOUT q (server answers 400).
# These are cheap for the server, so errors rise while CPU does not.
BAD_PCT = float(os.getenv("BAD_PCT", "0"))


class SearchUser(FastHttpUser):
    wait_time = between(0, WAIT_MAX)

    @task
    def search(self):
        if BAD_PCT and random.random() * 100 < BAD_PCT:
            self.client.get("/products/search?q=", name="GET /products/search (no q -> 400)")
            return
        q = random.choice(SEARCH_TERMS)
        # name= groups every query under one row in Locust's stats table
        self.client.get(f"/products/search?q={q}", name="GET /products/search")
