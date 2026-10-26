"""
Gradual ramp: 2 -> 40 users, adding 2 users every 30 s, hold 5 min, then 5 min at 2 users.
Run:  locust -f shape_ramp.py --host http://<ALB-DNS-NAME>
(-u/-t are ignored; this class controls users and stops the test itself.)
"""
from locust import LoadTestShape

from locustfile_search import SearchUser  # noqa: F401  (Locust picks up the user class)


class RampShape(LoadTestShape):
    step_users, step_seconds, peak, hold, cooldown = 2, 30, 40, 300, 300

    def tick(self):
        t = self.get_run_time()
        ramp_time = (self.peak // self.step_users) * self.step_seconds
        if t < ramp_time:
            return (self.step_users * (int(t // self.step_seconds) + 1), self.step_users)
        if t < ramp_time + self.hold:
            return (self.peak, self.step_users)
        if t < ramp_time + self.hold + self.cooldown:
            return (2, 10)  # back to light load: watch scale-IN
        return None  # stop
