use axum::{
    body::Bytes,
    extract::State,
    http::{header::CONTENT_TYPE, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use serde::Serialize;
use serde_json::Value;
use std::{env, net::SocketAddr};

const ERROR_MESSAGE: &str = "numbers must be a non-empty array of at most 10000 integers between -1000000000 and 1000000000.";

#[derive(Clone)]
struct AppState;

#[derive(Serialize)]
struct ApiError {
    error: ErrorDetail,
}

#[derive(Serialize)]
struct ErrorDetail {
    code: &'static str,
    message: &'static str,
}

fn error(status: StatusCode, code: &'static str, message: &'static str) -> Response {
    (status, Json(ApiError { error: ErrorDetail { code, message } })).into_response()
}

async fn health() -> Json<serde_json::Value> {
    Json(serde_json::json!({"status":"ok"}))
}

async fn calculate(State(_state): State<AppState>, body: Bytes) -> Response {
    let parsed: Value = match serde_json::from_slice(&body) {
        Ok(value) => value,
        Err(_) => return error(StatusCode::BAD_REQUEST, "invalid_json", "Request body must be valid JSON."),
    };
    let Some(values) = parsed.get("numbers").and_then(Value::as_array) else {
        return error(StatusCode::BAD_REQUEST, "invalid_input", ERROR_MESSAGE);
    };
    if values.is_empty() || values.len() > 10000 {
        return error(StatusCode::BAD_REQUEST, "invalid_input", ERROR_MESSAGE);
    }

    let mut numbers = Vec::with_capacity(values.len());
    for value in values {
        let Some(number) = value.as_i64() else {
            return error(StatusCode::BAD_REQUEST, "invalid_input", ERROR_MESSAGE);
        };
        if !(-1_000_000_000..=1_000_000_000).contains(&number) {
            return error(StatusCode::BAD_REQUEST, "invalid_input", ERROR_MESSAGE);
        }
        numbers.push(number);
    }

    let sum: i64 = numbers.iter().sum();
    numbers.sort_unstable();
    let count = numbers.len();
    let median = if count % 2 == 1 {
        numbers[count / 2] as f64
    } else {
        numbers[count / 2 - 1] as f64 / 2.0 + numbers[count / 2] as f64 / 2.0
    };
    let result = serde_json::json!({
        "count": count,
        "sum": sum,
        "min": numbers[0],
        "max": numbers[count - 1],
        "mean": sum as f64 / count as f64,
        "median": median,
    });
    (StatusCode::OK, [(CONTENT_TYPE, "application/json")], Json(result)).into_response()
}

#[tokio::main]
async fn main() {
    let port = env::var("PORT").unwrap_or_else(|_| "8000".to_string()).parse::<u16>().expect("PORT must be a valid port");
    let address = SocketAddr::from(([0, 0, 0, 0], port));
    let app = Router::new().route("/health", get(health)).route("/calculate", post(calculate)).with_state(AppState);
    let listener = tokio::net::TcpListener::bind(address).await.expect("failed to bind listener");
    axum::serve(listener, app).await.expect("server failed");
}
