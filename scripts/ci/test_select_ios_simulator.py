from __future__ import annotations

import unittest

from scripts.ci import select_ios_simulator as selector


class SelectIOSSimulatorTests(unittest.TestCase):
    def test_selects_preferred_ipad_from_latest_ios_runtime(self) -> None:
        payload = {
            "devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-25-4": [
                    {"name": "iPad (A16)", "udid": "OLD-IPAD", "isAvailable": True}
                ],
                "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
                    {"name": "iPad Pro 13-inch (M5)", "udid": "PRO-IPAD", "isAvailable": True},
                    {"name": "iPad (A16)", "udid": "A16-IPAD", "isAvailable": True},
                ],
            }
        }

        selected = selector.select_ipad(payload)

        self.assertEqual(selected["udid"], "A16-IPAD")
        self.assertEqual(selected["runtime"], "com.apple.CoreSimulator.SimRuntime.iOS-26-5")
        self.assertEqual(selected["destination"], "platform=iOS Simulator,id=A16-IPAD")

    def test_ignores_unavailable_devices_and_non_ios_runtimes(self) -> None:
        payload = {
            "devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
                    {
                        "name": "iPad (A16)",
                        "udid": "UNAVAILABLE",
                        "isAvailable": False,
                    },
                    {"name": "iPhone 17", "udid": "PHONE", "isAvailable": True},
                    {"name": "iPad Air 13-inch (M3)", "udid": "AIR", "isAvailable": True},
                ],
                "com.apple.CoreSimulator.SimRuntime.watchOS-26-5": [
                    {"name": "iPad Watch", "udid": "WATCH", "isAvailable": True}
                ],
            }
        }

        selected = selector.select_ipad(payload)

        self.assertEqual(selected["udid"], "AIR")

    def test_rejects_payload_without_an_available_ipad(self) -> None:
        payload = {
            "devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
                    {"name": "iPhone 17", "udid": "PHONE", "isAvailable": True}
                ]
            }
        }

        with self.assertRaisesRegex(ValueError, "no available iPad simulator"):
            selector.select_ipad(payload)

    def test_rejects_payload_without_devices_object(self) -> None:
        with self.assertRaisesRegex(ValueError, "devices object"):
            selector.select_ipad({})


if __name__ == "__main__":
    unittest.main()
