import os
from typing import Any

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

app = FastAPI(title="Backend Comparison API", docs_url=None, redoc_url=None)
ERROR_MESSAGE = (
    "numbers must be a non-empty array of at most 10000 integers between "
    "-1000000000 and 1000000000."
)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/calculate")
async def calculate(request: Request) -> JSONResponse:
    try:
        body: Any = await request.json()
    except Exception:
        return JSONResponse(
            status_code=400,
            content={"error": {"code": "invalid_json", "message": "Request body must be valid JSON."}},
        )

    values = body.get("numbers") if isinstance(body, dict) else None
    if (
        not isinstance(values, list)
        or not 1 <= len(values) <= 10000
        or any(type(value) is not int or abs(value) > 1_000_000_000 for value in values)
    ):
        return JSONResponse(
            status_code=400,
            content={"error": {"code": "invalid_input", "message": ERROR_MESSAGE}},
        )

    ordered = sorted(values)
    middle = len(ordered) // 2
    median = (
        float(ordered[middle])
        if len(ordered) % 2
        else ordered[middle - 1] / 2.0 + ordered[middle] / 2.0
    )
    return JSONResponse(
        content={
            "count": len(values),
            "sum": sum(values),
            "min": ordered[0],
            "max": ordered[-1],
            "mean": sum(values) / len(values),
            "median": median,
        },
    )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8000")))
