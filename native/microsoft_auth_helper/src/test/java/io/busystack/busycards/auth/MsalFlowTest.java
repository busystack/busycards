package io.busystack.busycards.auth;

import com.microsoft.aad.msal4j.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;

/** Uses the released SDK and synthetic HTTP responses, never provider accounts. */
class MsalFlowTest {
    @TempDir Path directory;
    static final String SUBJECT = "subject.tenant", COMPANION = "companion.tenant";
    static String encoded(Object value) throws Exception {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(Json.encode(value).getBytes(StandardCharsets.UTF_8));
    }
    static String response(String subject) throws Exception {
        String uid = subject.split("\\.")[0];
        String id = encoded(Map.of("alg", "none")) + "." + encoded(Map.of("tid", "tenant", "oid", uid, "sub", uid, "preferred_username", uid + "@example.test", "aud", CacheFixtures.FIRST, "exp", 4000000000L)) + ".";
        return Json.encode(Map.of("token_type", "Bearer", "access_token", "synthetic-access-" + uid,
            "refresh_token", "synthetic-rotated-" + uid, "id_token", id, "expires_in", 3600,
            "scope", "Contacts.ReadWrite", "client_info", encoded(Map.of("uid", uid, "utid", "tenant"))));
    }
    static class Transport implements IHttpClient {
        final String subject; final CompletableFuture<Void> entered = new CompletableFuture<>();
        final CompletableFuture<Void> release = new CompletableFuture<>(); volatile String body; String responseOverride;
        Transport(String subject) { this.subject = subject; }
        public IHttpResponse send(HttpRequest request) throws Exception {
            if (request.url().getPath().endsWith("/token")) {
                body = URLDecoder.decode(request.body(), StandardCharsets.UTF_8);
                entered.complete(null); release.get(10, TimeUnit.SECONDS);
                return new HttpResponse().statusCode(200).body(responseOverride == null ? response(subject) : responseOverride);
            }
            return new HttpResponse().statusCode(200).body(Json.encode(Map.of(
                "tenant_discovery_endpoint", "https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration",
                "metadata", List.of(Map.of("preferred_network", "login.microsoftonline.com", "preferred_cache", "login.microsoftonline.com", "aliases", List.of("login.microsoftonline.com"))))));
        }
    }
    static PublicClientApplication app(SecureCache cache, Transport transport, ExecutorService executor) throws Exception {
        return PublicClientApplication.builder(CacheFixtures.FIRST).authority(Main.AUTHORITY)
            .setTokenCacheAccessAspect(cache).httpClient(transport).executorService(executor).logPii(false).build();
    }
    static CompletableFuture<IAuthenticationResult> refresh(PublicClientApplication app, String subject, String claims) throws Exception {
        IAccount account = app.getAccounts().get(5, TimeUnit.SECONDS).stream().filter(a -> a.homeAccountId().equals(subject)).findFirst().orElseThrow();
        // There is no access token in the seeded fixture, so this necessarily
        // refreshes. Exercise the production claims builder itself.
        return app.acquireTokenSilently(Main.silentParameters(Set.of("Contacts.ReadWrite"), account, claims));
    }
    @Test void actualRefreshMapsHomeIdentityTenantExpiryGrantedScopesAndClaims() throws Exception {
        var memory = new SecureCacheTest.Memory(); var executor = Executors.newCachedThreadPool();
        try (var cache = new SecureCache(directory, SUBJECT, memory, CacheFixtures.FIRST)) {
            cache.seed(CacheFixtures.seed(CacheFixtures.FIRST, SUBJECT, COMPANION));
            var transport = new Transport(SUBJECT); var app = app(cache, transport, executor);
            var pending = refresh(app, SUBJECT, "{\"access_token\":{\"xms_cc\":{\"values\":[\"cp1\"]}}}");
            transport.entered.get(5, TimeUnit.SECONDS); transport.release.complete(null);
            IAuthenticationResult result = pending.get(5, TimeUnit.SECONDS); cache.requireHealthy();
            Map<String, Object> framed = Main.token(result);
            assertEquals(SUBJECT, framed.get("homeAccountId")); assertEquals("tenant", framed.get("tenantId"));
            assertEquals(Set.of("Contacts.ReadWrite"), new HashSet<>((List<String>) framed.get("scopes")));
            assertEquals("synthetic-access-subject", framed.get("accessToken"));
            assertTrue(java.time.Instant.parse((String) framed.get("expiresOn")).isAfter(java.time.Instant.now()));
            assertTrue(transport.body.contains("client_id=" + CacheFixtures.FIRST));
            assertTrue(transport.body.contains("claims={")); assertTrue(transport.body.contains("cp1"));
            assertEquals(2, app.getAccounts().get().size());
        } finally { executor.shutdownNow(); }
    }
    @Test void realRefreshCannotCommitAfterRemovalOrClearButCompanionRemainsUsable() throws Exception {
        for (boolean clear : List.of(false, true)) {
            var memory = new SecureCacheTest.Memory(); var executor = Executors.newCachedThreadPool();
            Path path = directory.resolve(clear ? "clear" : "remove");
            try (var late = new SecureCache(path, SUBJECT, memory, CacheFixtures.FIRST);
                 var cleaner = new SecureCache(path, null, memory, CacheFixtures.FIRST)) {
                cleaner.seed(CacheFixtures.fullSeed(CacheFixtures.FIRST, SUBJECT, COMPANION));
                var transport = new Transport(SUBJECT); var app = app(late, transport, executor);
                var pending = refresh(app, SUBJECT, null); transport.entered.get(5, TimeUnit.SECONDS);
                if (clear) cleaner.clear(); else {
                    cleaner.invalidateSubject(SUBJECT);
                    var removal = Main.application(CacheFixtures.FIRST, cleaner, executor);
                    IAccount account = removal.getAccounts().get().stream().filter(a -> a.homeAccountId().equals(SUBJECT)).findFirst().orElseThrow();
                    removal.removeAccount(account).get(); cleaner.finishSubjectRemoval(SUBJECT);
                }
                byte[] removed = memory.value == null ? null : memory.value.clone();
                transport.release.complete(null); assertThrows(ExecutionException.class, () -> pending.get(5, TimeUnit.SECONDS));
                assertThrows(AuthFailure.class, late::requireHealthy); assertArrayEquals(removed, memory.value);
                try (var fresh = new SecureCache(path, COMPANION, memory, CacheFixtures.FIRST)) {
                    var freshApp = Main.application(CacheFixtures.FIRST, fresh, executor);
                    assertEquals(clear ? 0 : 1, freshApp.getAccounts().get().size());
                }
            } finally { executor.shutdownNow(); }
        }
    }
    @Test void simultaneousCompanionRefreshesMergeInsteadOfLosingCacheEntries() throws Exception {
        var memory = new SecureCacheTest.Memory(); var executor = Executors.newCachedThreadPool();
        try (var first = new SecureCache(directory, SUBJECT, memory, CacheFixtures.FIRST);
             var second = new SecureCache(directory, COMPANION, memory, CacheFixtures.FIRST)) {
            first.seed(CacheFixtures.seed(CacheFixtures.FIRST, SUBJECT, COMPANION));
            var transportA = new Transport(SUBJECT); var transportB = new Transport(COMPANION);
            var pendingA = refresh(app(first, transportA, executor), SUBJECT, null);
            transportA.entered.get(5, TimeUnit.SECONDS);
            var pendingB = refresh(app(second, transportB, executor), COMPANION, null);
            transportB.entered.get(5, TimeUnit.SECONDS);
            transportA.release.complete(null); pendingA.get(5, TimeUnit.SECONDS);
            transportB.release.complete(null); pendingB.get(5, TimeUnit.SECONDS);
            Map<String, Object> model = Json.object(new String(memory.value, StandardCharsets.UTF_8));
            assertEquals(Set.of(SUBJECT, COMPANION), ((Map<?, ?>) model.get("Account")).values().stream()
                .map(entry -> ((Map<?, ?>) entry).get("home_account_id")).collect(java.util.stream.Collectors.toSet()));
            assertEquals(2, ((Map<?, ?>) model.get("AccessToken")).size());
            assertTrue(new String(memory.value, StandardCharsets.UTF_8).contains("synthetic-rotated-subject"));
            assertTrue(new String(memory.value, StandardCharsets.UTF_8).contains("synthetic-rotated-companion"));
        } finally { executor.shutdownNow(); }
    }
    @Test void companionRefreshSurvivesAnotherSubjectsRemovalWithoutRecreatingIt() throws Exception {
        var memory = new SecureCacheTest.Memory(); var executor = Executors.newCachedThreadPool();
        try (var companion = new SecureCache(directory, COMPANION, memory, CacheFixtures.FIRST);
             var cleaner = new SecureCache(directory, null, memory, CacheFixtures.FIRST)) {
            cleaner.seed(CacheFixtures.fullSeed(CacheFixtures.FIRST, SUBJECT, COMPANION));
            var transport = new Transport(COMPANION); var app = app(companion, transport, executor);
            var pending = refresh(app, COMPANION, null); transport.entered.get(5, TimeUnit.SECONDS);
            cleaner.invalidateSubject(SUBJECT);
            var removal = Main.application(CacheFixtures.FIRST, cleaner, executor);
            IAccount removed = removal.getAccounts().get().stream().filter(a -> a.homeAccountId().equals(SUBJECT)).findFirst().orElseThrow();
            removal.removeAccount(removed).get(); cleaner.finishSubjectRemoval(SUBJECT);
            transport.release.complete(null); pending.get(5, TimeUnit.SECONDS); companion.requireHealthy();
            try (var fresh = new SecureCache(directory, null, memory, CacheFixtures.FIRST)) {
                assertEquals(Set.of(COMPANION), Main.application(CacheFixtures.FIRST, fresh, executor).getAccounts().get().stream()
                    .map(IAccount::homeAccountId).collect(java.util.stream.Collectors.toSet()));
            }
        } finally { executor.shutdownNow(); }
    }
    @Test void admittedAfterInvalidationMustNotRepublishRemovedSubject() throws Exception {
        var memory = new SecureCacheTest.Memory(); var executor = Executors.newCachedThreadPool();
        try (var cleaner = new SecureCache(directory, null, memory, CacheFixtures.FIRST)) {
            cleaner.seed(CacheFixtures.fullSeed(CacheFixtures.FIRST, SUBJECT, COMPANION));
            cleaner.invalidateSubject(SUBJECT);
            // Admission occurs in the published-generation / old-cache gap.
            try (var companion = new SecureCache(directory, COMPANION, memory, CacheFixtures.FIRST)) {
                var transport = new Transport(COMPANION);
                var pending = refresh(app(companion, transport, executor), COMPANION, null);
                transport.entered.get(5, TimeUnit.SECONDS);
                var removal = Main.application(CacheFixtures.FIRST, cleaner, executor);
                IAccount removed = removal.getAccounts().get().stream().filter(a -> a.homeAccountId().equals(SUBJECT)).findFirst().orElseThrow();
                removal.removeAccount(removed).get(); cleaner.finishSubjectRemoval(SUBJECT);
                transport.release.complete(null); pending.get(5, TimeUnit.SECONDS);
                Map<String, Object> model = Json.object(new String(memory.value, StandardCharsets.UTF_8));
                for (String collection : List.of("Account", "AccessToken", "RefreshToken", "IdToken")) {
                    assertFalse(((Map<?, ?>)model.getOrDefault(collection, Map.of())).values().stream()
                        .anyMatch(e -> SUBJECT.equals(((Map<?, ?>)e).get("home_account_id"))), collection);
                }
            }
        } finally { executor.shutdownNow(); }
    }
    @Test void pendingCompanionRefreshPreservesFreshAuthorizationAfterRemoval() throws Exception {
        var memory = new SecureCacheTest.Memory(); var independent = new SecureCacheTest.Memory();
        var executor = Executors.newCachedThreadPool();
        try (var companion = new SecureCache(directory, COMPANION, memory, CacheFixtures.FIRST);
             var cleaner = new SecureCache(directory, null, memory, CacheFixtures.FIRST);
             var other = new SecureCache(directory.resolve("independent"), null, independent, CacheFixtures.SECOND)) {
            cleaner.seed(CacheFixtures.fullSeed(CacheFixtures.FIRST, SUBJECT, COMPANION));
            other.seed(CacheFixtures.fullSeed(CacheFixtures.SECOND, SUBJECT));
            byte[] independentBefore = independent.value.clone();
            var transport = new Transport(COMPANION);
            var pending = refresh(app(companion, transport, executor), COMPANION, null);
            transport.entered.get(5, TimeUnit.SECONDS);
            cleaner.invalidateSubject(SUBJECT);
            var removal = Main.application(CacheFixtures.FIRST, cleaner, executor);
            var account = removal.getAccounts().get().stream().filter(a -> a.homeAccountId().equals(SUBJECT)).findFirst().orElseThrow();
            removal.removeAccount(account).get(); cleaner.finishSubjectRemoval(SUBJECT);
            try (var fresh = new SecureCache(directory, SUBJECT, memory, CacheFixtures.FIRST)) {
                var authorization = new Transport(SUBJECT);
                authorization.responseOverride = CacheFixtures.tokenResponse(CacheFixtures.FIRST, SUBJECT);
                authorization.release.complete(null);
                Main.execute(Map.of("method", "authorize", "homeAccountId", SUBJECT), fresh,
                    app(fresh, authorization, executor), CacheWorker.browser(false));
            }
            Map<String, Object> renewed = Json.object(new String(memory.value, StandardCharsets.UTF_8));
            var freshCredentials = CacheFixtures.subjectEntries(memory.value, SUBJECT);
            transport.release.complete(null);
            var result = pending.get(5, TimeUnit.SECONDS);
            companion.requireHealthy(); companion.validateResult(result.account().homeAccountId());
            assertEquals(COMPANION, result.account().homeAccountId());
            Map<String, Object> committed = Json.object(new String(memory.value, StandardCharsets.UTF_8));
            assertTrue(freshCredentials.equals(CacheFixtures.subjectEntries(memory.value, SUBJECT)),
                "all renewed entries survive without stale extras");
            for (String collection : List.of("Account", "AccessToken", "RefreshToken", "IdToken")) {
                var freshEntries = (Map<?, ?>)renewed.getOrDefault(collection, Map.of());
                var finalEntries = (Map<?, ?>)committed.getOrDefault(collection, Map.of());
                assertTrue(freshEntries.values().stream().anyMatch(e ->
                    SUBJECT.equals(((Map<?, ?>)e).get("home_account_id"))), collection);
                assertTrue(freshEntries.entrySet().stream()
                    .filter(e -> SUBJECT.equals(((Map<?, ?>)e.getValue()).get("home_account_id")))
                    .allMatch(e -> Objects.equals(e.getValue(), finalEntries.get(e.getKey()))), collection);
                assertTrue(finalEntries.values().stream().anyMatch(e ->
                    COMPANION.equals(((Map<?, ?>)e).get("home_account_id"))), collection);
            }
            assertTrue(Arrays.equals(independentBefore, independent.value), "other registration unchanged");
            try (var reopened = new SecureCache(directory, null, memory, CacheFixtures.FIRST)) {
                assertEquals(Set.of(SUBJECT, COMPANION), Main.application(CacheFixtures.FIRST, reopened, executor)
                    .getAccounts().get().stream().map(IAccount::homeAccountId).collect(java.util.stream.Collectors.toSet()));
            }
        } finally { executor.shutdownNow(); }
    }
    @Test void authorizationAdmittedDuringRemovalCannotCommitAfterCompletion() throws Exception {
        var memory = new SecureCacheTest.Memory(); var executor = Executors.newCachedThreadPool();
        try (var cleaner = new SecureCache(directory, null, memory, CacheFixtures.FIRST)) {
            cleaner.seed(CacheFixtures.fullSeed(CacheFixtures.FIRST, SUBJECT, COMPANION));
            cleaner.invalidateSubject(SUBJECT);
            // An unknown interactive identity is admitted while A is pending.
            // It must not gain authority when the tombstone is later retired.
            try (var late = new SecureCache(directory, null, memory, CacheFixtures.FIRST)) {
                var transport = new Transport(SUBJECT);
                transport.responseOverride = CacheFixtures.tokenResponse(CacheFixtures.FIRST, SUBJECT);
                var pending = CompletableFuture.supplyAsync(() -> {
                    try { return Main.execute(Map.of("method", "authorize"), late,
                        app(late, transport, executor), CacheWorker.browser(false)); }
                    catch (Exception error) { throw new CompletionException(error); }
                });
                transport.entered.get(5, TimeUnit.SECONDS);
                var removal = Main.application(CacheFixtures.FIRST, cleaner, executor);
                var removed = removal.getAccounts().get().stream().filter(a -> a.homeAccountId().equals(SUBJECT)).findFirst().orElseThrow();
                removal.removeAccount(removed).get(); cleaner.finishSubjectRemoval(SUBJECT);
                byte[] completed = memory.value.clone();
                transport.release.complete(null);
                assertThrows(ExecutionException.class, () -> pending.get(5, TimeUnit.SECONDS));
                assertArrayEquals(completed, memory.value);
                var model = Json.object(new String(memory.value, StandardCharsets.UTF_8));
                for (String collection : List.of("Account", "AccessToken", "RefreshToken", "IdToken")) {
                    assertFalse(((Map<?, ?>)model.getOrDefault(collection, Map.of())).values().stream()
                        .anyMatch(e -> SUBJECT.equals(((Map<?, ?>)e).get("home_account_id"))), collection);
                }
            }
            // A genuinely new operation admitted after completion is allowed.
            try (var fresh = new SecureCache(directory, SUBJECT, memory, CacheFixtures.FIRST)) {
                var transport = new Transport(SUBJECT);
                transport.responseOverride = CacheFixtures.tokenResponse(CacheFixtures.FIRST, SUBJECT);
                transport.release.complete(null);
                var result = (Map<?, ?>)Main.execute(Map.of("method", "authorize", "homeAccountId", SUBJECT),
                    fresh, app(fresh, transport, executor), CacheWorker.browser(false));
                assertEquals(SUBJECT, result.get("homeAccountId"));
                assertEquals(Set.of(SUBJECT, COMPANION), Main.application(CacheFixtures.FIRST, fresh, executor)
                    .getAccounts().get().stream().map(IAccount::homeAccountId).collect(java.util.stream.Collectors.toSet()));
            }
        } finally { executor.shutdownNow(); }
    }
    @Test void unusableCacheRepairStagesInteractiveIdentityAndSurvivesRestart() throws Exception {
        for (String invalid : List.of("not-json", "{}", "{\"Account\":[]}", "{\"Account\":{\"bad\":{\"home_account_id\":[]}}}", "{\"Account\":{},\"AppMetadata\":[]}")) {
            var memory = new SecureCacheTest.Memory(); memory.value = invalid.getBytes(StandardCharsets.UTF_8);
            var executor = Executors.newCachedThreadPool(); Path path = directory.resolve(UUID.randomUUID().toString());
            try (var cache = new SecureCache(path, SUBJECT, memory, CacheFixtures.FIRST)) {
                var transport = new Transport(SUBJECT); transport.responseOverride = CacheFixtures.tokenResponse(CacheFixtures.FIRST, SUBJECT);
                var staged = PublicClientApplication.builder(CacheFixtures.FIRST).authority(Main.AUTHORITY)
                    .httpClient(transport).executorService(executor).logPii(false).build();
                String intent = cache.inspectUnusable();
                var pending = CompletableFuture.supplyAsync(() -> {
                    try { return Main.execute(Map.of("method", "repairCache", "homeAccountId", SUBJECT,
                        "tenantId", "tenant", "recoveryToken", intent), cache, staged, CacheWorker.browser(false)); }
                    catch (Exception error) { throw new CompletionException(error); }
                });
                transport.entered.get(5, TimeUnit.SECONDS);
                assertArrayEquals(invalid.getBytes(StandardCharsets.UTF_8), memory.value, "browser pending preserves old cache");
                transport.release.complete(null); pending.get(5, TimeUnit.SECONDS);
                try (var fresh = new SecureCache(path, SUBJECT, memory, CacheFixtures.FIRST)) {
                    var after = app(fresh, new Transport(SUBJECT), executor);
                    var account = after.getAccounts().get().iterator().next();
                    assertEquals(SUBJECT, account.homeAccountId());
                    var cached = after.acquireTokenSilently(Main.silentParameters(Set.of("Contacts.ReadWrite"), account, null)).get();
                    assertNull(cached.scopes(), "released SDK cache-hit mapping");
                    assertEquals(SUBJECT, Main.token(cached, after.tokenCache(), CacheFixtures.FIRST).get("homeAccountId"));
                    assertTrue(((List<?>)Main.token(cached, after.tokenCache(), CacheFixtures.FIRST).get("scopes")).contains("Contacts.ReadWrite"));
                }
            } finally { executor.shutdownNow(); }
        }
    }
    @Test void repairWrongAccountOrConcurrentReplacementNeverOverwritesOriginal() throws Exception {
        for (String scenario : List.of("wrong", "concurrent", "write", "readback", "rollback", "cancel")) {
            var memory = new SecureCacheTest.Memory(); byte[] original = "not-json".getBytes(StandardCharsets.UTF_8); memory.value = original.clone();
            var executor = Executors.newCachedThreadPool(); Path path = directory.resolve(scenario);
            try (var cache = new SecureCache(path, SUBJECT, memory, CacheFixtures.FIRST)) {
                var transport = new Transport(scenario.equals("wrong") ? COMPANION : SUBJECT);
                transport.responseOverride = CacheFixtures.tokenResponse(CacheFixtures.FIRST, transport.subject);
                var staged = PublicClientApplication.builder(CacheFixtures.FIRST).authority(Main.AUTHORITY)
                    .httpClient(transport).executorService(executor).logPii(false).build();
                String intent = cache.inspectUnusable();
                var pending = CompletableFuture.supplyAsync(() -> {
                    try { return Main.execute(Map.of("method", "repairCache", "homeAccountId", SUBJECT,
                        "tenantId", "tenant", "recoveryToken", intent), cache, staged, CacheWorker.browser(false)); }
                    catch (Exception error) { throw new CompletionException(error); }
                });
                transport.entered.get(5, TimeUnit.SECONDS);
                if (scenario.equals("concurrent")) {
                    try (var other = new SecureCache(path, null, memory, CacheFixtures.FIRST)) { other.seed(CacheFixtures.seed(CacheFixtures.FIRST, COMPANION)); }
                }
                if (scenario.equals("write")) memory.corruptWrite = true;
                if (scenario.equals("readback")) memory.failReadAfterWrite = true;
                if (scenario.equals("rollback")) memory.failWrites = true;
                if (scenario.equals("cancel")) transport.release.completeExceptionally(new CancellationException());
                else transport.release.complete(null);
                Exception error = assertThrows(Exception.class, () -> pending.get(5, TimeUnit.SECONDS));
                String code = Main.classify(error);
                assertEquals(switch (scenario) {
                    case "wrong" -> "wrong-account"; case "concurrent" -> "cache-recovery-conflict";
                    case "write", "readback" -> "secure-storage-failed"; case "rollback" -> "cache-rollback-failed";
                    default -> "identity-error";
                }, code);
                if (scenario.equals("concurrent")) assertTrue(new String(memory.value, StandardCharsets.UTF_8).contains(COMPANION));
                else assertArrayEquals(original, memory.value);
            } finally { executor.shutdownNow(); }
        }
    }
}
