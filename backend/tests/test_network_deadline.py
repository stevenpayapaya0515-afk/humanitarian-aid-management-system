from threading import Event
from time import monotonic
import pytest
from services.network_deadline import call_with_deadline, ProviderTimeout, ProviderBusy


def test_stalled_operation_bounds_wait_and_capacity():
    release, finished = Event(), Event()
    def stalled():
        try:
            release.wait(2)
        finally:
            finished.set()
    started = monotonic()
    try:
        with pytest.raises(ProviderTimeout):
            call_with_deadline('email', 0.03, stalled)
        assert monotonic() - started < 0.5
        with pytest.raises(ProviderBusy):
            call_with_deadline('email', 0.03, lambda: None)
    finally:
        release.set()
        assert finished.wait(1)
