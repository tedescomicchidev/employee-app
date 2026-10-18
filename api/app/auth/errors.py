from fastapi import HTTPException


class ApiError(HTTPException):
    def __init__(self, status_code: int, code: str, message: str) -> None:
        super().__init__(status_code=status_code, detail={"code": code, "message": message})


def unauthenticated(message: str = "Missing or invalid access token") -> ApiError:
    return ApiError(401, "UNAUTHENTICATED", message)


def forbidden(message: str = "Not allowed") -> ApiError:
    return ApiError(403, "FORBIDDEN", message)
