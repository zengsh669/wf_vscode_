# import time

# class bcolors:
#     HEADER = '\033[95m'
#     OKBLUE = '\033[94m'
#     OKCYAN = '\033[96m'
#     OKGREEN = '\033[92m'
#     WARNING = '\033[93m'
#     FAIL = '\033[91m'
#     ENDC = '\033[0m'
#     BOLD = '\033[1m'
#     UNDERLINE = '\033[4m'
#     RESET = '\033[0m'

# class Logger:
#     def __init__(self):
#         self.logs = []
#         self.warning_detected = False
#         self.error_detected = False

#     def debug(self, msg, header=False):
#         if header:
#             self._write_log('DEBUG', msg, bcolors.HEADER)
#         else:
#             self._write_log('DEBUG', msg)

#     def warning(self, msg):
#         self._write_log('WARN', msg, bcolors.WARNING)
#         self.warning_detected = True

#     def error(self, msg):
#         self._write_log('ERROR', msg, bcolors.FAIL)
#         self.error_detected = True

#     def _write_log(self, level, msg, clr=bcolors.OKGREEN):
#         timestamp = time.strftime('%Y-%m-%dT%H:%M:%SZ')
#         print(f'{clr} {timestamp} {level} {msg} {bcolors.RESET}')

#         self.logs.append({
#             'timestamp': timestamp,
#             'severity': level,
#             'message': msg
#         })


# below will return AU sydney time
import time
from datetime import datetime
from zoneinfo import ZoneInfo  # ✅ 新增：用于时区处理


class bcolors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'
    RESET = '\033[0m'


class Logger:
    def __init__(self):
        self.logs = []
        self.warning_detected = False
        self.error_detected = False

    def debug(self, msg, header=False):
        if header:
            self._write_log('DEBUG', msg, bcolors.HEADER)
        else:
            self._write_log('DEBUG', msg)

    def warning(self, msg):
        self._write_log('WARN', msg, bcolors.WARNING)
        self.warning_detected = True

    def error(self, msg):
        self._write_log('ERROR', msg, bcolors.FAIL)
        self.error_detected = True

    def _write_log(self, level, msg, clr=bcolors.OKGREEN):
        # ✅ 使用澳大利亚悉尼时间
        timestamp = datetime.now(
            ZoneInfo("Australia/Sydney")).strftime('%Y-%m-%d %H:%M:%S')
        print(f'{clr} {timestamp} {level} {msg} {bcolors.RESET}')

        self.logs.append({
            'timestamp': timestamp,
            'severity': level,
            'message': msg
        })
