from fastapi import HTTPException


class ApiError(HTTPException):
    def __init__(self, status_code: int, code: str, message: str) -> None:
        super().__init__(status_code=status_code, detail={"code": code, "message": message})


def unauthenticated(message: str = "Missing or invalid access token") -> ApiError:
    return ApiError(401, "UNAUTHENTICATED", message)


def forbidden(message: str = "Not allowed") -> ApiError:
    return ApiError(403, "FORBIDDEN", message)


class FieldError(ApiError):
    def __init__(self, field: str, reason: str) -> None:
        super().__init__(422, "VALIDATION_ERROR", f"{field}: {reason}")
        self.detail["field"] = field


def confirmation_required() -> ApiError:
    return ApiError(
        409, "CONFIRMATION_REQUIRED", "This action needs a confirmation from the review screen"
    )


def invalid_confirmation() -> ApiError:
    return ApiError(409, "INVALID_CONFIRMATION", "The confirmation is not valid for this action")


def not_provisioned() -> ApiError:
    return ApiError(403, "NOT_PROVISIONED", "No employee record for this account")
