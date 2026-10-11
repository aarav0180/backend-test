import json
import os
from typing import Any

from flask import Flask, jsonify, request

app = Flask(__name__)
ERROR_MESSAGE = (
    "numbers must be a non-empty array of at most 10000 integers between "
    "-1000000000 and 1000000000."
)


@app.get("/health")
def health():
    return jsonify(status="ok")


@app.post("/calculate")
def calculate():
    try:
        body: Any = json.loads(request.get_data(cache=False))
    except (ValueError, UnicodeDecodeError):
        return jsonify(error={"code": "invalid_json", "message": "Request body must be valid JSON."}), 400

    values = body.get("numbers") if isinstance(body, dict) else None
    if (
        not isinstance(values, list)
        or not 1 <= len(values) <= 10000
        or any(type(value) is not int or abs(value) > 1_000_000_000 for value in values)
    ):
        return jsonify(error={"code": "invalid_input", "message": ERROR_MESSAGE}), 400

    ordered = sorted(values)
    middle = len(ordered) // 2
    median = (
        float(ordered[middle])
        if len(ordered) % 2
        else ordered[middle - 1] / 2.0 + ordered[middle] / 2.0
    )
    total = sum(values)
    return jsonify(
        count=len(values),
        sum=total,
        min=ordered[0],
        max=ordered[-1],
        mean=total / len(values),
        median=median,
    )


if __name__ == "__main__":
    from waitress import serve

    serve(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8000")))
