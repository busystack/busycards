package io.busystack.busycards.auth;

final class AuthFailure extends RuntimeException {
    final String code;
    AuthFailure(String code) { super(code, null, false, false); this.code = code; }
}
