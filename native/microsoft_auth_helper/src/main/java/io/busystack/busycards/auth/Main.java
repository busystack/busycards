package io.busystack.busycards.auth;

import com.microsoft.aad.msal4j.*;
import java.io.*;
import java.net.*;
import java.nio.*;
import java.nio.charset.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;

public final class Main {
    static final int VERSION = 1, MAX_REQUEST = 64 * 1024, MAX_RESPONSE = 1024 * 1024;
    static final Set<String> DEFAULT_SCOPES = Set.of("openid", "profile", "email", "Contacts.ReadWrite", "offline_access");
    static final Set<String> SCOPES = Set.of("openid", "profile", "email", "Contacts.Read", "Contacts.ReadWrite", "offline_access");
    static final String AUTHORITY = "https://login.microsoftonline.com/common/";
    private Main() {}

    public static void main(String[] args) {
        int exit;
        PrintStream protocol = System.out;
        // SDK/JNA diagnostics can contain provider/account data. Only the framed
        // protocol writer retains the original output stream.
        System.setOut(new PrintStream(OutputStream.nullOutputStream()));
        System.setErr(new PrintStream(OutputStream.nullOutputStream()));
        String requestId = "";
        try {
            Map<String, Object> request;
            try { request = Json.object(readFrame(System.in)); }
            catch (IOException malformed) { throw new AuthFailure("invalid-request"); }
            requestId = string(request, "requestId", false);
            if (!(request.get("version") instanceof Number version) || version.doubleValue() != VERSION || requestId.isBlank()) throw new AuthFailure("protocol-mismatch");
            Object result = dispatch(request);
            writeFrame(protocol, Map.of("version", VERSION, "requestId", requestId, "ok", true, "result", result));
            exit = 0;
        } catch (Throwable error) {
            try { writeFrame(protocol, Map.of("version", VERSION, "requestId", requestId, "ok", false, "error", Map.of("code", classify(error)))); }
            catch (Throwable ignored) { }
            exit = 2;
        }
        // MSAL executors/listeners must never keep this one-request process resident.
        System.exit(exit);
    }

    static String readFrame(InputStream input) throws IOException {
        DataInputStream stream = new DataInputStream(input);
        int length = stream.readInt();
        if (length <= 0 || length > MAX_REQUEST) throw new AuthFailure("invalid-request");
        byte[] bytes = stream.readNBytes(length);
        if (bytes.length != length || stream.read() != -1) throw new AuthFailure("invalid-request");
        return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString();
    }
    static void writeFrame(OutputStream output, Object value) throws IOException {
        byte[] bytes = Json.encode(value).getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_RESPONSE) throw new AuthFailure("response-too-large");
        DataOutputStream stream = new DataOutputStream(output); stream.writeInt(bytes.length); stream.write(bytes); stream.flush();
    }
    static String string(Map<String, Object> request, String key, boolean optional) {
        Object value = request.get(key);
        if (value == null && optional) return null;
        if (!(value instanceof String text)) throw new AuthFailure("invalid-request");
        return text;
    }
    static String client(String value) {
        if (value == null || !value.matches("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}") || UUID.fromString(value).equals(new UUID(0, 0))) throw new AuthFailure("client-id-missing");
        return UUID.fromString(value).toString();
    }
    static Set<String> scopes(Map<String, Object> request) {
        Object value = request.get("scopes"); if (value == null) return DEFAULT_SCOPES;
        if (!(value instanceof List<?> list)) throw new AuthFailure("invalid-request");
        if (list.isEmpty()) return DEFAULT_SCOPES;
        Set<String> selected = new HashSet<>();
        for (Object item : list) { if (!(item instanceof String scope) || !SCOPES.contains(scope)) throw new AuthFailure("invalid-scope"); selected.add(scope); }
        if (!selected.contains("Contacts.Read") && !selected.contains("Contacts.ReadWrite")) throw new AuthFailure("invalid-scope");
        return selected;
    }
    static Object dispatch(Map<String, Object> request) throws Exception {
        String method = string(request, "method", false);
        if (method.equals("version")) return Map.of("version", VERSION);
        if (!Set.of("authorize", "acquireToken", "listAccounts", "removeAccount", "clearCache", "inspectCache", "repairCache").contains(method)) throw new AuthFailure("unknown-method");
        String clientId = client(string(request, "clientId", true));
        scopes(request);
        String subject = string(request, "homeAccountId", true);
        if ((method.equals("acquireToken") || method.equals("removeAccount") || method.equals("repairCache")) && (subject == null || subject.isBlank())) throw new AuthFailure("invalid-request");
        if (method.equals("repairCache")) {
            String intent = string(request, "recoveryToken", false), tenant = string(request, "tenantId", false);
            if (!intent.matches("[0-9a-f]{64}") || tenant.isBlank()) throw new AuthFailure("invalid-request");
        }
        String claims = string(request, "claims", true);
        if (claims != null && !claims.isBlank()) {
            try { Json.object(claims); } catch (IOException malformed) { throw new AuthFailure("invalid-request"); }
        }
        ExecutorService executor = Executors.newCachedThreadPool();
        try (SecureCache cache = new SecureCache(clientId, subject)) {
            if (method.equals("clearCache")) { cache.clear(); return Map.of("cleared", true); }
            // A confirmed repair stages only in the SDK's in-memory cache. It
            // never deserializes the unusable cache during browser acquisition.
            PublicClientApplication app = application(clientId,
                method.equals("repairCache") || method.equals("inspectCache") ? null : cache, executor);
            return execute(request, cache, app, SystemBrowserOptions.builder().openBrowserAction(Main::openBrowser)
                .htmlMessageSuccess("<html><body>Authentication complete. Return to BusyCards.</body></html>")
                .htmlMessageError("<html><body>Authentication did not complete. Return to BusyCards for recovery instructions.</body></html>")
                .build());
        } finally { executor.shutdownNow(); }
    }
    // The same command implementation is driven by controlled SDK transports
    // in fixtures; no runtime test flags or alternate authentication path.
    static Object execute(Map<String, Object> request, SecureCache cache, PublicClientApplication app, SystemBrowserOptions browser) throws Exception {
        String method = string(request, "method", false);
        String subject = string(request, "homeAccountId", true);
        String claims = string(request, "claims", true);
        Set<String> selectedScopes = scopes(request);
        if (method.equals("inspectCache")) return Map.of("recoveryToken", cache.inspectUnusable());
        boolean repair = method.equals("repairCache");
        if (repair) cache.beginRecovery(string(request, "recoveryToken", false));
        Set<IAccount> accounts;
        if (repair) accounts = Set.of();
        else {
            if (method.equals("removeAccount")) cache.invalidateSubject(subject);
            accounts = healthyAwait(cache, app.getAccounts()); cache.requireHealthy();
        }
        if (method.equals("listAccounts")) return Map.of("accounts", accounts.stream().map(a -> Map.of("homeAccountId", a.homeAccountId(), "username", Objects.requireNonNullElse(a.username(), ""), "environment", a.environment())).toList());
        IAccount account = accounts.stream().filter(a -> a.homeAccountId().equals(subject)).findFirst().orElse(null);
        if (method.equals("removeAccount")) {
            if (account != null) healthyAwait(cache, app.removeAccount(account));
            cache.requireHealthy(); cache.finishSubjectRemoval(subject);
            return Map.of("removed", account != null);
        }
        IAuthenticationResult result;
        if (method.equals("authorize") || repair) {
            var builder = InteractiveRequestParameters.builder(URI.create("http://localhost"))
                .scopes(selectedScopes).prompt(Prompt.SELECT_ACCOUNT).httpPollingTimeoutInSeconds(290).systemBrowserOptions(browser);
            if (claims != null && !claims.isBlank()) builder.claimsChallenge(claims);
            result = healthyAwait(cache, app.acquireToken(builder.build()));
        } else {
            if (account == null) throw new AuthFailure("account-not-found");
            result = healthyAwait(cache, app.acquireTokenSilently(silentParameters(selectedScopes, account, claims)));
        }
        cache.requireHealthy();
        if (subject != null && !result.account().homeAccountId().equals(subject)) throw new AuthFailure("wrong-account");
        if (repair) cache.commitRecovery(app.tokenCache(), result, subject, string(request, "tenantId", false));
        else cache.validateResult(result.account().homeAccountId());
        return token(result, app.tokenCache(), app.clientId());
    }
    static PublicClientApplication application(String client, ITokenCacheAccessAspect cache, ExecutorService executor) throws Exception {
        var builder = PublicClientApplication.builder(client).authority(AUTHORITY).executorService(executor).logPii(false).clientCapabilities(Set.of("cp1"));
        if (cache != null) builder.setTokenCacheAccessAspect(cache);
        return builder.build();
    }
    static SilentParameters silentParameters(Set<String> scopes, IAccount account, String claims) {
        var builder = SilentParameters.builder(scopes, account);
        if (claims != null && !claims.isBlank()) {
            var parsed = ClaimsRequest.formatAsClaimsRequest(claims);
            // 1.26.0's silent supplier drops claims while constructing its
            // refresh parameters. Its supported extra-query API carries the
            // SDK-formatted claims through the original request context.
            builder.claims(parsed).forceRefresh(true).extraQueryParameters(Map.of("claims", parsed.formatAsJSONString()));
        }
        return builder.build();
    }
    static Map<String, Object> token(IAuthenticationResult result) { return token(result, null, null); }
    static Map<String, Object> token(IAuthenticationResult result, ITokenCache cache, String client) {
        // Read the actual SDK result's ID token. In 1.26.0 tenantProfile is
        // initialized before its constructor assigns idToken and can be null.
        // Never substitute the home-account tenant for the issuing tenant.
        Object tenant;
        try { tenant = com.nimbusds.jwt.JWTParser.parse(result.idToken()).getJWTClaimsSet().getStringClaim("tid"); }
        catch (Exception invalid) { throw new AuthFailure("identity-error"); }
        String granted = result.scopes();
        // 1.26.0 leaves scopes null in cache-hit results (TokenCache's
        // AuthenticationResult builder never sets it). Recover the actual
        // granted target from the SDK entry that supplied this exact token,
        // never from the requested scopes or another account/client.
        if (granted == null && cache != null && result.account() != null) {
            try {
                var model = Json.object(cache.serialize());
                for (Object value : ((Map<?, ?>)model.getOrDefault("AccessToken", Map.of())).values()) {
                    var entry = (Map<?, ?>)value;
                    if (Objects.equals(entry.get("secret"), result.accessToken()) &&
                        Objects.equals(entry.get("home_account_id"), result.account().homeAccountId()) &&
                        Objects.equals(entry.get("client_id"), client) &&
                        Objects.equals(entry.get("environment"), result.account().environment()) && entry.get("target") instanceof String target) {
                        if (granted != null && !granted.equals(target)) throw new AuthFailure("identity-error");
                        granted = target;
                    }
                }
            } catch (Exception invalid) { throw new AuthFailure("identity-error"); }
        }
        if (!(tenant instanceof String tenantId) || tenantId.isBlank() || result.account() == null || result.account().homeAccountId() == null || result.expiresOnDate() == null || granted == null || granted.isBlank()) throw new AuthFailure("identity-error");
        return Map.of("accessToken", result.accessToken(), "expiresOn", result.expiresOnDate().toInstant().toString(), "homeAccountId", result.account().homeAccountId(), "tenantId", tenantId, "scopes", List.of(granted.trim().split("\\s+")));
    }
    static <T> T healthyAwait(SecureCache cache, CompletableFuture<T> future) throws Exception {
        try { return await(future); }
        catch (Exception error) { cache.requireHealthy(); throw error; }
    }
    static <T> T await(CompletableFuture<T> future) throws Exception { return future.get(295, TimeUnit.SECONDS); }
    static void openBrowser(URL url) {
        try {
            Process process = new ProcessBuilder("xdg-open", url.toString()).redirectOutput(ProcessBuilder.Redirect.DISCARD).redirectError(ProcessBuilder.Redirect.DISCARD).start();
            // xdg-open may await the external browser. Never kill that browser.
            if (process.waitFor(1, TimeUnit.SECONDS) && process.exitValue() != 0) throw new AuthFailure("browser-launch-failed");
        } catch (AuthFailure error) { throw error; }
        catch (Exception error) { throw new AuthFailure("browser-launch-failed"); }
    }
    static String classify(Throwable error) {
        while ((error instanceof ExecutionException || error instanceof CompletionException) && error.getCause() != null) error = error.getCause();
        if (error instanceof AuthFailure failure) return failure.code;
        if (error instanceof CancellationException || error instanceof InterruptedException) return "authentication-cancelled";
        if (error instanceof TimeoutException) return "helper-timeout";
        if (error instanceof EOFException || error instanceof CharacterCodingException) return "invalid-request";
        if (error instanceof MsalException msal) {
            if (msal.errorCode() == null) return "identity-error";
            String code = switch (msal.errorCode()) {
                case "invalid_client", "unauthorized_client" -> "invalid-client";
                case "invalid_redirect_uri", "loopback_redirect_uri" -> "invalid-client";
                case "access_denied" -> "access-denied";
                case "consent_required" -> "consent-required";
                case "interaction_required", "login_required", "invalid_grant", "cache_miss" -> "interaction-required";
                case "invalid_scope" -> "invalid-scope";
                case "desktop_browser_not_supported", "unable_to_start_http_listener" -> "browser-launch-failed";
                default -> "identity-error";
            };
            return msal instanceof MsalInteractionRequiredException && code.equals("identity-error") ? "interaction-required" : code;
        }
        // All native/keyring failures are converted at the storage boundary.
        return "helper-failed";
    }
}
