"""Учебная замена настоящего модуля requests.

Приложение работает офлайн, поэтому к сети не обращается: ответы берутся
из заранее подготовленных данных. Структура совпадает с тем, что ожидает
курс.
"""

import json as _json

_DEFAULT = {"status": "ok"}
_CANNED = {
    "generate": {
        "choices": [{"content": "Привет, друг!"}],
        "model": "chat-mini",
    },
    "rates": {
        "base": "USD",
        "date": "2026-01-15",
        "rates": {"RUB": 92.5, "EUR": 0.92, "GBP": 0.79},
    },
    "search": {"results": [{"q": "python"}], "total": 1},
}


class RequestException(Exception):
    pass


class Response:
    def __init__(self, url, payload, status_code=200, reason="OK"):
        self.url = url
        self.status_code = status_code
        self.reason = reason
        self.encoding = "utf-8"
        self.headers = {
            "Content-Type": "application/json; charset=utf-8",
            "Server": "fake-api",
        }
        self._payload = payload

    @property
    def text(self):
        return _json.dumps(self._payload, ensure_ascii=False)

    @property
    def content(self):
        return self.text.encode("utf-8")

    def json(self):
        return self._payload


def _payload_for(url):
    value = str(url).lower()
    if "generate" in value or "chat" in value or "complet" in value:
        return _CANNED["generate"]
    if "rate" in value:
        return _CANNED["rates"]
    if "search" in value:
        return _CANNED["search"]
    return _DEFAULT


def _make(url):
    return Response(url, _payload_for(url))


def get(url, params=None, **kwargs):
    return _make(url)


def post(url, data=None, json=None, headers=None, **kwargs):
    return _make(url)


def put(url, data=None, **kwargs):
    return _make(url)


def head(url, **kwargs):
    return _make(url)


def request(method, url, **kwargs):
    return _make(url)


class _Exceptions:
    RequestException = RequestException


exceptions = _Exceptions()
