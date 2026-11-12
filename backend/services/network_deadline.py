"""Bound caller waits even when DNS/provider libraries stall.

Timed-out threads cannot be killed. Capacity stays occupied until they exit;
this prevents unlimited workers. Callers must invalidate timed-out OTPs.
Never run database work inside these workers.
"""
from concurrent.futures import Future, TimeoutError as FutureTimeout
from threading import BoundedSemaphore, Thread

class ProviderTimeout(RuntimeError):
    pass

class ProviderBusy(RuntimeError):
    pass

_slots = {"captcha": BoundedSemaphore(4), "email": BoundedSemaphore(1)}

def call_with_deadline(kind, seconds, function):
    slot = _slots[kind]
    if not slot.acquire(blocking=False):
        raise ProviderBusy(kind)
    future = Future()
    def run():
        try:
            future.set_result(function())
        except BaseException as error:
            future.set_exception(error)
        finally:
            slot.release()
    try:
        Thread(target=run, daemon=True, name="aidtrack-" + kind).start()
    except BaseException:
        slot.release()
        raise
    try:
        return future.result(timeout=seconds)
    except FutureTimeout:
        raise ProviderTimeout(kind) from None
