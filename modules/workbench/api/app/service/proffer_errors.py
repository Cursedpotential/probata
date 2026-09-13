"""Shared error type for the Workbench Proffer boundary."""


class ProfferError(Exception):
    def __init__(self, detail: str, status_code: int = 502):
        self.detail = detail
        self.status_code = status_code
        super().__init__(detail)
