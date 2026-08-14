"""Send Ctrl+C (CTRL_C_EVENT) to a child process — Windows-only interrupt test helper.

Usage: python send_ctrl_c.py <delay_ms> <command...>

- Creates the child with CREATE_NEW_PROCESS_GROUP (child is its own group leader),
  so GenerateConsoleCtrlEvent(CTRL_C_EVENT, child_pid) targets only the child.
- Waits delay_ms, injects Ctrl+C, waits up to 20s for exit, prints exit code.
- Prints "INJECT_SKIP" and exits 77 if the platform lacks the required APIs
  (non-Windows or restricted environment) so tests can skip gracefully.
"""
import ctypes
import sys
import time
from ctypes import wintypes

CREATE_NEW_PROCESS_GROUP = 0x00000200
# CTRL_C_EVENT 无法定向到进程组（会广播到整个控制台）；CTRL_BREAK_EVENT 可按
# 进程组定向投递，mp 的 handler 对两者一视同仁（均置取消标志）。
# 注意：不传 CREATE_NEW_CONSOLE（子进程新建独立控制台反而收不到组信号），
# 子进程继承父进程控制台 + 自任进程组长即可。
CTRL_BREAK_EVENT = 1


class STARTUPINFO(ctypes.Structure):
    _fields_ = [
        ("cb", wintypes.DWORD),
        ("lpReserved", wintypes.LPWSTR),
        ("lpDesktop", wintypes.LPWSTR),
        ("lpTitle", wintypes.LPWSTR),
        ("dwX", wintypes.DWORD),
        ("dwY", wintypes.DWORD),
        ("dwXSize", wintypes.DWORD),
        ("dwYSize", wintypes.DWORD),
        ("dwXCountChars", wintypes.DWORD),
        ("dwYCountChars", wintypes.DWORD),
        ("dwFillAttribute", wintypes.DWORD),
        ("dwFlags", wintypes.DWORD),
        ("wShowWindow", wintypes.WORD),
        ("cbReserved2", wintypes.WORD),
        ("lpReserved2", ctypes.c_void_p),
        ("hStdInput", wintypes.HANDLE),
        ("hStdOutput", wintypes.HANDLE),
        ("hStdError", wintypes.HANDLE),
    ]


class PROCESS_INFORMATION(ctypes.Structure):
    _fields_ = [
        ("hProcess", wintypes.HANDLE),
        ("hThread", wintypes.HANDLE),
        ("dwProcessId", wintypes.DWORD),
        ("dwThreadId", wintypes.DWORD),
    ]


def main():
    if sys.platform != "win32":
        print("INJECT_SKIP")
        sys.exit(77)

    delay_ms = int(sys.argv[1])
    cmdline = " ".join(sys.argv[2:])

    kernel32 = ctypes.windll.kernel32
    si = STARTUPINFO()
    si.cb = ctypes.sizeof(STARTUPINFO)
    pi = PROCESS_INFORMATION()

    ok = kernel32.CreateProcessW(
        None,
        cmdline,
        None,
        None,
        True,
        CREATE_NEW_PROCESS_GROUP,
        None,
        None,
        ctypes.byref(si),
        ctypes.byref(pi),
    )
    if not ok:
        print("INJECT_SKIP")
        sys.exit(77)

    time.sleep(delay_ms / 1000.0)
    sent = kernel32.GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, pi.dwProcessId)
    if not sent:
        print("INJECT_SKIP")
        sys.exit(77)

    kernel32.WaitForSingleObject(pi.hProcess, 20000)
    exit_code = wintypes.DWORD(0)
    kernel32.GetExitCodeProcess(pi.hProcess, ctypes.byref(exit_code))
    kernel32.CloseHandle(pi.hProcess)
    kernel32.CloseHandle(pi.hThread)
    print("exit_code=%d" % exit_code.value)
    sys.exit(0)


if __name__ == "__main__":
    main()
