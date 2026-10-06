package io.busystack.busycards.auth;

import com.microsoft.aad.msal4j.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import java.io.*;
import java.nio.*;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

class ProtocolTest {
    @Test void versionNeedsNoRegistrationOrKeyring() throws Exception {
        assertEquals(Map.of("version", 1), Main.dispatch(Map.of("method", "version")));
    }
    @ParameterizedTest @ValueSource(strings={"", "arbitrary/path", "00000000-0000-0000-0000-000000000000", "bad-client"})
    void invalidClient(String value) { assertEquals("client-id-missing", assertThrows(AuthFailure.class, () -> Main.client(value)).code); }
    @Test void normalizedClientAndScopeAllowlist() {
        assertEquals("abcdefab-cdef-abcd-efab-cdefabcdefab", Main.client("ABCDEFAB-CDEF-ABCD-EFAB-CDEFABCDEFAB"));
        assertEquals(Main.DEFAULT_SCOPES, Main.scopes(Map.of()));
        assertEquals(6, Main.SCOPES.size());
        assertFalse(Main.DEFAULT_SCOPES.contains("Contacts.Read"));
        assertThrows(AuthFailure.class, () -> Main.scopes(Map.of("scopes", List.of("openid"))));
        assertThrows(AuthFailure.class, () -> Main.scopes(Map.of("scopes", List.of("Mail.ReadWrite"))));
        assertThrows(AuthFailure.class, () -> Main.scopes(Map.of("scopes", List.of("Calendars.Read"))));
        assertEquals(Set.of("Contacts.Read"), Main.scopes(Map.of("scopes", List.of("Contacts.Read"))));
    }
    @Test void framingBoundsTruncationTrailingEncoding() throws Exception {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream(); Main.writeFrame(bytes, Map.of("test", "ok"));
        assertEquals(Map.of("test", "ok"), Json.object(Main.readFrame(new ByteArrayInputStream(bytes.toByteArray()))));
        for (byte[] invalid : List.of(new byte[0], new byte[]{0,0,0,0}, ByteBuffer.allocate(4).putInt(Main.MAX_REQUEST+1).array(), new byte[]{0,0,0,2,1}, new byte[]{0,0,0,1,(byte)0xff}, new byte[]{0,0,0,2,123,125,0})) {
            assertThrows(Exception.class, () -> Main.readFrame(new ByteArrayInputStream(invalid)));
        }
        assertThrows(Exception.class, () -> Json.object("{not-json"));
        assertThrows(Exception.class, () -> Json.object("{}{}"));
    }
    @Test void releasedSdkErrorAllowlistAndRedaction() {
        Map<String, String> allowed = Map.of("invalid_client", "invalid-client", "unauthorized_client", "invalid-client", "access_denied", "access-denied", "consent_required", "consent-required", "interaction_required", "interaction-required", AuthenticationErrorCode.DESKTOP_BROWSER_NOT_SUPPORTED, "browser-launch-failed");
        allowed.forEach((code, expected) -> assertEquals(expected, Main.classify(new MsalClientException("secret-description", code))));
        assertEquals("identity-error", Main.classify(new MsalClientException("secret-description", "secret-code")));
        assertEquals("helper-failed", Main.classify(new RuntimeException("secret-stacktrace")));
        assertEquals("secure-storage-failed", Main.classify(new AuthFailure("secure-storage-failed")));
    }
    @Test void repairRequiresExplicitBoundIntentBeforeOpeningStorage() {
        for (Map<String, Object> request : List.<Map<String, Object>>of(
            Map.of("method", "repairCache", "clientId", CacheFixtures.FIRST),
            Map.of("method", "repairCache", "clientId", CacheFixtures.FIRST, "homeAccountId", "subject.tenant", "tenantId", "tenant", "recoveryToken", "arbitrary"))) {
            assertEquals("invalid-request", Main.classify(assertThrows(Exception.class, () -> Main.dispatch(request))));
        }
        assertEquals("helper-failed", Main.classify(new IOException("private-path")));
    }
    @Test void stageConstructionUsesActualSdkDefaultCacheWithoutNullAspect() throws Exception {
        var executor = java.util.concurrent.Executors.newCachedThreadPool();
        try {
            var app = Main.application(CacheFixtures.FIRST, null, executor);
            assertNotNull(app.tokenCache()); assertEquals(0, app.getAccounts().get().size());
            assertTrue(app.clientCapabilities().contains("cp1"));
        } finally { executor.shutdownNow(); }
    }
    @Test void decodedGraphClaimsUseReleasedSdkForcedRefreshWithTheSelectedAccount() throws Exception {
        var executor = java.util.concurrent.Executors.newCachedThreadPool();
        try {
            var app = Main.application(CacheFixtures.FIRST, null, executor);
            app.tokenCache().deserialize(CacheFixtures.seed(CacheFixtures.FIRST, "subject.tenant", "companion.tenant"));
            IAccount account = app.getAccounts().get().stream().filter(value -> value.homeAccountId().equals("subject.tenant")).findFirst().orElseThrow();
            String claims = "{\"access_token\":{\"acrs\":{\"essential\":true,\"value\":\"c1\"}}}";
            var parameters = Main.silentParameters(Set.of("Contacts.ReadWrite"), account, claims);
            assertTrue(parameters.forceRefresh());
            assertSame(account, parameters.account());
            assertEquals(Set.of("Contacts.ReadWrite"), parameters.scopes());
            assertEquals(Json.object(claims), Json.object(parameters.claims().formatAsJSONString()));
            assertEquals(parameters.claims().formatAsJSONString(), parameters.extraQueryParameters().get("claims"));
        } finally { executor.shutdownNow(); }
    }
}
