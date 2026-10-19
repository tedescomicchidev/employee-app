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


def empty_audience() -> ApiError:
    return ApiError(422, "EMPTY_AUDIENCE", "The audience has no recipients")


def not_found() -> ApiError:
    """One answer for unknown, withdrawn and not-addressed-to-me (FR-ANN-002.3)."""
    return ApiError(404, "NOT_FOUND", "Not available")


def canton_missing() -> ApiError:
    return ApiError(422, "CANTON_MISSING", "Your work canton is not set; ask HR to set it")


def no_approver() -> ApiError:
    return ApiError(422, "NO_APPROVER", "No approver is assigned to this account")


def self_approval() -> ApiError:
    return ApiError(422, "SELF_APPROVAL", "A request cannot be approved by its own author")


def invalid_state() -> ApiError:
    """R11: the request is no longer in a state this action applies to (FR-VAC-003.2, 004.3)."""
    return ApiError(409, "INVALID_STATE", "The request is no longer pending")


def rule_violation(
    violations: list[dict[str, object]], review: dict[str, object] | None = None
) -> ApiError:
    """One stable code (the first by precedence) plus every failing code (FR-VAC-002.2)."""
    error = ApiError(422, str(violations[0]["code"]), "The request breaks a vacation rule")
    error.detail["codes"] = [v["code"] for v in violations]
    error.detail["violations"] = violations
    if review is not None:
        error.detail["review"] = review
    return error
