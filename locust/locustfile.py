"""
Locust load test for the Product API.

Pick the client by naming the user class on the command line:
    locust -f locust/locustfile.py ProductHttpUser --host http://<IP>:8080
    locust -f locust/locustfile.py ProductFastUser --host http://<IP>:8080

Request mix (realistic e-commerce: browsing >> editing):
    80%  GET  existing product          -> 200
    15%  POST valid details update      -> 204
     5%  GET  non-existent product      -> 404 (counted as success in Locust,
                                           but shows up in the Errors panel in Grafana)

Env vars:
    SEEDED_PRODUCTS  must match SEED_PRODUCTS on the server (default 100)
    WAIT_MAX         max think time in seconds between requests (default 1.0).
                     Set WAIT_MAX=0 for a stress test (no think time).
"""
import os
import random

from locust import FastHttpUser, HttpUser, between

SEEDED = int(os.getenv("SEEDED_PRODUCTS", "100"))
WAIT_MAX = float(os.getenv("WAIT_MAX", "1.0"))


def get_product(user):
    pid = random.randint(1, SEEDED)
    user.client.get(f"/products/{pid}", name="GET /products/[id]")


def get_missing_product(user):
    pid = random.randint(1_000_000, 2_000_000)
    with user.client.get(f"/products/{pid}", name="GET /products/[id] (expect 404)",
                         catch_response=True) as resp:
        if resp.status_code == 404:
            resp.success()
        else:
            resp.failure(f"expected 404, got {resp.status_code}")


def post_details(user):
    pid = random.randint(1, SEEDED)
    payload = {
        "product_id": pid,
        "sku": f"SKU-{pid:05d}-v{random.randint(1, 999)}",
        "manufacturer": "Acme Corporation",
        "category_id": random.randint(1, 10),
        "weight": random.randint(0, 5000),
        "some_other_id": random.randint(1, 1000),
    }
    user.client.post(f"/products/{pid}/details", json=payload, name="POST /products/[id]/details")


TASKS = {get_product: 80, post_details: 15, get_missing_product: 5}


class ProductHttpUser(HttpUser):
    """Uses python-requests under the hood."""
    wait_time = between(0, WAIT_MAX)
    tasks = TASKS


class ProductFastUser(FastHttpUser):
    """Uses geventhttpclient under the hood (much lower CPU cost per request)."""
    wait_time = between(0, WAIT_MAX)
    tasks = TASKS
