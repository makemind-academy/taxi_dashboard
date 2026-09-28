#!/usr/bin/env python3
"""taxi-dashboard: the door frame starts the meter, speed frames become the fare, arriving puts payment due; the passenger pays with one press."""
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "tools"))
from appplayer import AppPlayer  # noqa: E402
from mcpclient import Server  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.join(HERE, "dashboard_server")
CAP = os.path.join(HERE, "captures")

with Server(["dart", "run", "bin/server.dart"], cwd=SERVER) as s:
    for _ in range(60):
        st = s.call("trip.state")
        if st["payDue"]:
            break
        time.sleep(0.5)
    assert st["payDue"], "the trip never arrived"
    arrived = st
    paid = s.call("fare.charge")
    assert paid["status"] == "Paid" and paid["approval"] != "-", paid
    stats = s.call("bus.stats")
    assert stats["framesUsed"] > 0 and stats["framesUsed"] <= stats["framesSeen"], stats
    print(f"   arrival: fare={arrived['fareLabel']} distance={arrived['distanceLabel']} waiting={arrived['waitingLabel']} "
          f"framesUsed={stats['framesUsed']} notice=\"{arrived['notice']}\"")
    print(f"   payment: approval={paid['approval']} status={paid['status']} notice=\"{paid['notice']}\"")
    print(f"   bus: framesSeen={stats['framesSeen']} framesUsed={stats['framesUsed']} "
          f"droppedOutOfOrder={stats['framesDroppedOutOfOrder']} authorizeMs={stats['lastAuthorizeMs']}")
    for line in stats["requestTranscript"]:
        print(f"   {line}")

ap = AppPlayer()
# On screen the vehicle's clock runs at 5x instead of 30x, so each phase of the
# trip lasts long enough to be photographed. The meter is not told; it reads
# the frames' own timestamps, and the fare comes out the same way.
ap.register_server("com.makemind.sample.taxi", "Taxi", cwd=SERVER,
                   args=["run", "bin/server.dart", "--time-scale=5"])
ap.restart()
ap.open_server("com.makemind.sample.taxi")


def readout():
    fare = [t for t, r in ap.texts("$") if r[3] > 40][0]          # the big fare
    km = [t for t, _ in ap.texts(" km") if t.endswith(" km")][0]
    wait = [t for t, _ in ap.texts(" s") if t.endswith(" s")][0]
    frames = [t for t, _ in ap.texts("vehicle frames")][0]
    return fare, km, wait, frames


ap.wait_text("Waiting for fare")
ap.expect_text("no button pressed")
ap.shot(f"{CAP}/01_driver_idle.png")
ap.wait_text("Hired")                      # the door frame started the meter — nobody pressed
ap.expect_text("Meter started by door frame")
ap.shot(f"{CAP}/02_driver_hired.png")
ap.wait_text("Hired — moving")
time.sleep(9)                              # well into the run, before the light
print("   under way:", *readout())
ap.shot(f"{CAP}/03_driver_driving.png")
ap.wait_text("Hired — waiting", timeout=30)  # stopped at a light: distance holds, waiting climbs
time.sleep(2)
print("   at a light:", *readout())
km = [r for t, r in ap.texts(" km") if t.endswith(" km")][0]
sec = [r for t, r in ap.texts(" s") if t.endswith(" s")][0]
assert abs((km[0] + km[2]) - (sec[0] + sec[2])) <= 1, (km, sec)   # the two readouts are right-aligned to the same column
ap.shot(f"{CAP}/04_driver_waiting.png")
ap.tap("Trip")
ap.wait_text("Flagfall")
ap.expect_aligned("$", min_rows=3)          # flagfall · distance · waiting, one column
ap.shot(f"{CAP}/05_passenger_riding.png")
ap.wait_text("by card", timeout=60)         # arrival put the payment in front of the passenger
ap.shot(f"{CAP}/06_passenger_pay_due.png")
pay = [t for t, _ in ap.texts("by card") if t.startswith("Pay ")][0]
ap.tap(pay)
ap.wait_text("Approved $")                 # the terminal answered; the code is on the receipt
ap.wait_text("Approval T")
ap.shot(f"{CAP}/07_passenger_paid.png")
ap.tap("Driver")
ap.wait_text("Paid")                       # and the driver's page says so without a press
print("   arrival on screen:", *readout())
ap.shot(f"{CAP}/08_driver_paid.png")
print("taxi-dashboard: meter started by the door, fare from speed frames, paid from the back seat")
