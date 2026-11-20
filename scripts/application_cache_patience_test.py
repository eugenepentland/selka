#!/usr/bin/env python3
"""The application-cache driver's hang guards stretch with the load and never shrink below what is written (F23)."""
import importlib.util
from pathlib import Path
import unittest
from unittest import mock

DRIVER = Path(__file__).resolve().parents[1] / "tests" / "application_cache.py"
spec = importlib.util.spec_from_file_location("application_cache", DRIVER)
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)


class Patience(unittest.TestCase):
    def setUp(self):
        self.addCleanup(driver._SLOWDOWN.__setitem__, 0, driver._SLOWDOWN[0])
        driver._SLOWDOWN[0] = 1.0

    def clocks(self, wall, cpu):
        """A machine where a 50 ms CPU spin took `wall` seconds of wall time."""
        monotonic = iter([0.0, wall])
        process = iter([0.0, cpu, cpu])  # the start, the spin's last test, the end
        return mock.patch.object(driver.time, "monotonic", lambda: next(monotonic)), mock.patch.object(driver.time, "process_time", lambda: next(process))

    def test_an_idle_machine_keeps_the_limits_as_written(self):
        # A spin that gets its whole core takes its own CPU time in wall time. The test used to time a real spin and asserted a
        # slowdown below 3, which failed whenever the gate it ran in had the machine saturated (a gate that starts its steps
        # together does, on 9 November: 130 s of patience for a 30 s limit): it measured the load, not the rule.
        for _ in range(3):
            wall, cpu = self.clocks(wall=0.05, cpu=0.05)
            with wall, cpu:
                self.assertAlmostEqual(driver.measure_slowdown(), 1.0, delta=0.05)
        self.assertLess(driver.patience(30), 30 * 3)
        self.assertGreaterEqual(driver.patience(30), 30)
        self.assertGreaterEqual(driver.patience(180), 180)

    def test_a_loaded_machine_stretches_every_limit_in_proportion(self):
        wall, cpu = self.clocks(wall=0.5, cpu=0.05)  # the spin got a tenth of a core
        with wall, cpu:
            slowdown = driver.measure_slowdown()
        self.assertAlmostEqual(slowdown, 10.0, delta=1.0)
        self.assertAlmostEqual(driver.patience(30), 30 * slowdown)
        self.assertGreater(driver.patience(30), 240)

    def test_the_stretch_has_a_ceiling_so_a_hang_is_still_found(self):
        wall, cpu = self.clocks(wall=500.0, cpu=0.05)
        with wall, cpu:
            driver.measure_slowdown()
        self.assertEqual(driver._SLOWDOWN[0], driver.SLOWDOWN_CEILING)
        self.assertEqual(driver.patience(10), 10 * driver.SLOWDOWN_CEILING)

    def test_no_driver_limit_is_a_bare_number(self):
        text = DRIVER.read_text()
        bare = [line.strip() for line in text.splitlines() if "timeout=" in line and "patience(" not in line and "def " not in line]
        self.assertEqual([], bare)
        self.assertNotIn("time.monotonic() + 30", text)


if __name__ == "__main__":
    unittest.main()
