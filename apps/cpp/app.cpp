#include <crow.h>
#include <nlohmann/json.hpp>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <numeric>
#include <string>
#include <vector>

using json = nlohmann::json;
constexpr const char* kErrorMessage = "numbers must be a non-empty array of at most 10000 integers between -1000000000 and 1000000000.";

crow::response error_response(int status, const std::string& code, const std::string& message) {
  crow::response response(status, json{{"error", {{"code", code}, {"message", message}}}}.dump());
  response.set_header("Content-Type", "application/json; charset=utf-8");
  return response;
}

int main() {
  crow::SimpleApp app;
  CROW_ROUTE(app, "/health").methods(crow::HTTPMethod::GET)([] {
    crow::response response(200, R"({"status":"ok"})");
    response.set_header("Content-Type", "application/json; charset=utf-8");
    return response;
  });
  CROW_ROUTE(app, "/calculate").methods(crow::HTTPMethod::POST)([](const crow::request& req) {
    json body;
    try { body = json::parse(req.body); }
    catch (...) { return error_response(400, "invalid_json", "Request body must be valid JSON."); }
    if (!body.is_object() || !body.contains("numbers") || !body["numbers"].is_array() ||
        body["numbers"].empty() || body["numbers"].size() > 10000) {
      return error_response(400, "invalid_input", kErrorMessage);
    }

    std::vector<long long> values;
    values.reserve(body["numbers"].size());
    for (const auto& value : body["numbers"]) {
      if (!value.is_number_integer()) return error_response(400, "invalid_input", kErrorMessage);
      long long number;
      if (value.is_number_unsigned()) {
        const auto unsigned_number = value.get<std::uint64_t>();
        if (unsigned_number > 1000000000ULL) return error_response(400, "invalid_input", kErrorMessage);
        number = static_cast<long long>(unsigned_number);
      } else {
        number = value.get<long long>();
      }
      if (number < -1000000000LL || number > 1000000000LL) return error_response(400, "invalid_input", kErrorMessage);
      values.push_back(number);
    }

    auto ordered = values;
    std::sort(ordered.begin(), ordered.end());
    const auto count = ordered.size();
    const auto sum = std::accumulate(values.begin(), values.end(), 0LL);
    double median = static_cast<double>(ordered[count / 2]);
    if (count % 2 == 0) median = ordered[count / 2 - 1] / 2.0 + ordered[count / 2] / 2.0;
    json result = {{"count", count}, {"sum", sum}, {"min", ordered.front()}, {"max", ordered.back()},
                   {"mean", static_cast<double>(sum) / count}, {"median", median}};
    crow::response response(200, result.dump());
    response.set_header("Content-Type", "application/json; charset=utf-8");
    return response;
  });

  const char* port_env = std::getenv("PORT");
  const auto port = static_cast<std::uint16_t>(port_env ? std::stoi(port_env) : 10000);
  app.bindaddr("0.0.0.0").port(port).multithreaded().run();
}
