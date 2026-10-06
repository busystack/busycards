package io.busystack.busycards.auth;

import com.microsoft.aad.msal4j.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;

/** Controlled network/browser for multi-JVM tests; absent from shipped jars. */
public final class CacheWorker {
    static SystemBrowserOptions browser(boolean pending) {
        return SystemBrowserOptions.builder().openBrowserAction(url -> {
                    try {
                        var query = new HashMap<String, String>();
                        for (String pair : url.getQuery().split("&")) {
                            String[] bits = pair.split("=", 2); query.put(bits[0], URLDecoder.decode(bits[1], StandardCharsets.UTF_8));
                        }
                        URI redirect = URI.create(query.get("redirect_uri"));
                        if (pending) {
                            System.out.println("BROWSER_PENDING " + redirect.getPort()); System.out.flush(); return;
                        }
                        // MSAL4J requests response_mode=form_post; replay the
                        // browser's POST, including the SDK-generated state.
                        if (!query.get("response_mode").equals("form_post")) throw new AssertionError("callback mode");
                        var callback = (HttpURLConnection) redirect.toURL().openConnection();
                        callback.setDoOutput(true); callback.setRequestMethod("POST");
                        callback.setRequestProperty("Content-Type", "application/x-www-form-urlencoded");
                        try (var output = callback.getOutputStream()) {
                            output.write(("code=synthetic-code&state=" + URLEncoder.encode(query.get("state"), StandardCharsets.UTF_8)).getBytes(StandardCharsets.UTF_8));
                        }
                        callback.getInputStream().close(); callback.disconnect();
                    } catch (Exception error) { throw new AuthFailure("browser-launch-failed"); }
                        }).build();
    }
    static void framed(String client, String subject, URI barrier) {
        String correlation = ""; int status = 0;
        var executor = Executors.newCachedThreadPool();
        try {
            Map<String, Object> request = Json.object(Main.readFrame(System.in));
            correlation = Main.string(request, "requestId", false);
            Object result;
            String method = Main.string(request, "method", false);
            if (!method.equals("repairCache") && !(barrier != null && Set.of("authorize", "acquireToken").contains(method))) result = Main.dispatch(request);
            else {
                // Only controlled transport/browser are injected; the request,
                // SDK, cache callbacks, repair intent and response are real.
                if (!Main.client(Main.string(request, "clientId", false)).equals(client)) throw new AssertionError("client");
                IHttpClient transport = network -> {
                    if (network.url().getPath().endsWith("/token")) {
                        // Test-only loopback barrier keeps stdout protocol-only
                        // while Dart controls the production SDK/cache interleaving.
                        if (barrier != null) {
                            var signal = (HttpURLConnection)barrier.resolve("/" + subject).toURL().openConnection();
                            signal.setConnectTimeout(5000); signal.setReadTimeout(20000);
                            try { signal.getInputStream().close(); } finally { signal.disconnect(); }
                        }
                        return new HttpResponse().statusCode(200).body(CacheFixtures.tokenResponse(client, subject));
                    }
                    return new HttpResponse().statusCode(200).body(Json.encode(Map.of(
                        "tenant_discovery_endpoint", "https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration",
                        "metadata", List.of(Map.of("preferred_network", "login.microsoftonline.com", "preferred_cache", "login.microsoftonline.com", "aliases", List.of("login.microsoftonline.com"))))));
                };
                try (var cache = new SecureCache(client, method.equals("authorize") ? null : subject)) {
                    var builder = PublicClientApplication.builder(client).authority(Main.AUTHORITY).httpClient(transport)
                        .executorService(executor).logPii(false);
                    if (!method.equals("repairCache")) builder.setTokenCacheAccessAspect(cache);
                    var app = builder.build();
                    result = Main.execute(request, cache, app, browser(false));
                }
            }
            Main.writeFrame(System.out, Map.of("version", 1, "requestId", correlation, "ok", true, "result", result));
        } catch (Throwable error) {
            try { Main.writeFrame(System.out, Map.of("version", 1, "requestId", correlation, "ok", false, "error", Map.of("code", Main.classify(error)))); }
            catch (Exception ignored) { }
            status = 2;
        } finally { executor.shutdownNow(); }
        System.exit(status);
    }
    public static void main(String[] args) throws Exception {
        System.setErr(new java.io.PrintStream(java.io.OutputStream.nullOutputStream()));
        String mode = args[0], client = args[1], subject = args[2];
        if (mode.startsWith("framed")) { framed(client, subject, mode.equals("framedControlled") ? URI.create(args[3]) : null); return; }
        if (mode.equals("seedFull")) {
            try (var cache = new SecureCache(client, null)) { cache.seed(CacheFixtures.fullSeed(client, Arrays.copyOfRange(args, 2, args.length))); }
            System.exit(0);
        }
        if (mode.equals("seedUnusable")) {
            try (var cache = new SecureCache(client, null)) { cache.seed("not-json"); }
            System.exit(0);
        }
        if (mode.equals("initialize") || mode.equals("clear") || mode.equals("removeGap")) {
            System.out.println("STARTING"); System.out.flush();
            try (var cache = new SecureCache(client, null)) {
                if (mode.equals("clear")) cache.clear();
                if (mode.equals("removeGap")) {
                    cache.invalidateSubject(subject);
                    System.out.println("INVALIDATED"); System.out.flush();
                    if (System.in.read() != 1) throw new AssertionError("deletion barrier");
                    var executor = Executors.newCachedThreadPool();
                    try {
                        var app = Main.application(client, cache, executor);
                        var account = app.getAccounts().get().stream().filter(a -> a.homeAccountId().equals(subject)).findFirst().orElse(null);
                        if (account != null) app.removeAccount(account).get();
                        cache.requireHealthy(); cache.finishSubjectRemoval(subject);
                    } finally { executor.shutdownNow(); }
                }
                System.out.println("SUCCESS"); System.out.flush();
            }
            System.exit(0);
        }
        var executor = Executors.newCachedThreadPool();
        int status = 0;
        try (var cache = new SecureCache(client, mode.startsWith("interactive") || mode.startsWith("repair") ? null : subject)) {
            IHttpClient transport = request -> {
                if (request.url().getPath().endsWith("/token")) {
                    System.out.println("TOKEN_PENDING"); System.out.flush();
                    if (System.in.read() != 1) throw new AssertionError("network barrier");
                    return new HttpResponse().statusCode(200).body(CacheFixtures.tokenResponse(client, subject));
                }
                return new HttpResponse().statusCode(200).body(Json.encode(Map.of(
                    "tenant_discovery_endpoint", "https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration",
                    "metadata", List.of(Map.of("preferred_network", "login.microsoftonline.com", "preferred_cache", "login.microsoftonline.com", "aliases", List.of("login.microsoftonline.com"))))));
            };
            var builder = PublicClientApplication.builder(client).authority(Main.AUTHORITY)
                .httpClient(transport).executorService(executor).logPii(false);
            if (!mode.startsWith("repair")) builder.setTokenCacheAccessAspect(cache);
            var app = builder.build();
            IAuthenticationResult result;
            if (mode.startsWith("repair")) {
                String intent = cache.inspectUnusable();
                Map<String, Object> token = (Map<String, Object>)Main.execute(Map.of("method", "repairCache", "homeAccountId", subject,
                    "tenantId", "tenant", "recoveryToken", intent), cache, app, browser(mode.equals("repairPending")));
                if (!subject.equals(token.get("homeAccountId"))) throw new AssertionError("identity");
                System.out.println("SUCCESS"); System.exit(0); return;
            }
            if (mode.startsWith("interactive")) {
                var browser = browser(mode.equals("interactivePending"));
                result = app.acquireToken(InteractiveRequestParameters.builder(URI.create("http://localhost"))
                    .scopes(Main.SCOPES).prompt(Prompt.SELECT_ACCOUNT).httpPollingTimeoutInSeconds(60).systemBrowserOptions(browser).build()).get(65, TimeUnit.SECONDS);
            } else {
                IAccount account = app.getAccounts().get().stream().filter(a -> a.homeAccountId().equals(subject)).findFirst().orElseThrow();
                result = app.acquireTokenSilently(Main.silentParameters(Set.of("Contacts.ReadWrite"), account, null)).get(20, TimeUnit.SECONDS);
            }
            cache.requireHealthy(); cache.validateResult(result.account().homeAccountId());
            if (!Main.token(result, app.tokenCache(), client).get("homeAccountId").equals(subject)) throw new AssertionError("identity");
            System.out.println("SUCCESS");
        } catch (Throwable error) {
            while (error instanceof ExecutionException && error.getCause() != null) error = error.getCause();
            String code = Main.classify(error);
            String detail = code.equals("helper-failed") ? " " + error.getClass().getSimpleName() : "";
            if (code.equals("helper-failed")) {
                for (var frame : error.getStackTrace()) {
                    if (frame.getClassName().startsWith("io.busystack.busycards.auth.")) detail += " " + frame.getMethodName() + ":" + frame.getLineNumber();
                }
            }
            if (code.equals("identity-error") && error instanceof MsalException msal) {
                for (var field : AuthenticationErrorCode.class.getFields()) {
                    if (field.getType() == String.class && Objects.equals(field.get(null), msal.errorCode())) detail = " " + field.getName();
                }
            }
            System.out.println("BLOCKED " + code + detail); status = 2;
        }
        finally { executor.shutdownNow(); }
        System.exit(status);
    }
}
