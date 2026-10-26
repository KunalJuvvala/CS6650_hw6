"""
Spike: 3 quiet minutes at 3 users, sudden jump to 40 users for 8 minutes, back to 3 users for 8 minutes.
Run:  locust -f shape_spike.py --host http://<ALB-DNS-NAME>
"""
from locust import LoadTestShape

from locustfile_search import SearchUser  # noqa: F401


class SpikeShape(LoadTestShape):
    stages = [
        (180, 3, 3),     # until 3 min: 3 users
        (660, 40, 40),   # until 11 min: 40 users, all spawned at once
        (1140, 3, 10),   # until 19 min: 3 users (scale-in)
    ]

    def tick(self):
        t = self.get_run_time()
        for end, users, rate in self.stages:
            if t < end:
                return (users, rate)
        return None
