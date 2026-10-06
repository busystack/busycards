package io.busystack.busycards.auth;

import com.microsoft.aad.msal4j.*;
import com.microsoft.aad.msal4jextensions.persistence.ICacheAccessor;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;

class SecureCacheTest {
    @TempDir Path root;
    static class Memory implements ICacheAccessor {
        byte[] value; boolean corruptWrite, failRead, failWrites, failReadAfterWrite, failReadOnce;
        public byte[] read() { if (failReadOnce) { failReadOnce = false; throw new RuntimeException("private-readback"); } if (failRead) throw new RuntimeException("private-storage-description"); return value; }
        public void write(byte[] bytes) { if (failReadAfterWrite) { failReadAfterWrite = false; failReadOnce = true; } if (failWrites) throw new RuntimeException("private-write"); value = corruptWrite ? new byte[]{0} : bytes.clone(); corruptWrite = false; }
        public void delete() { value = null; }
    }
    record Context(ITokenCache tokenCache, boolean hasCacheChanged) implements ITokenCacheAccessContext { public String clientId() { return CacheFixtures.FIRST; } public IAccount account() { return null; } }
    static class Token implements ITokenCache {
        String value = "{\"Account\":{}}";
        public String serialize() { return value; }
        public void deserialize(String value) { this.value = value; }
    }
    @Test void verifiedWriteFailureRollsBack() throws Exception {
        Memory memory = new Memory();
        try (SecureCache cache = new SecureCache(root, "subject.tenant", memory, CacheFixtures.FIRST)) {
            cache.seed(CacheFixtures.seed(CacheFixtures.FIRST, "subject.tenant")); byte[] before = memory.value.clone();
            Token token = new Token(); Context context = new Context(token, true);
            cache.beforeCacheAccess(context); token.value = CacheFixtures.seed(CacheFixtures.FIRST, "subject.tenant", "companion.tenant");
            memory.corruptWrite = true;
            assertEquals("secure-storage-failed", assertThrows(AuthFailure.class, () -> cache.afterCacheAccess(context)).code);
            assertArrayEquals(before, memory.value); assertThrows(AuthFailure.class, cache::requireHealthy);
        }
    }
    @Test void readFailureNeverReportsHealthy() throws Exception {
        Memory memory = new Memory();
        try (SecureCache cache = new SecureCache(root, null, memory, CacheFixtures.FIRST)) {
            memory.failRead = true;
            assertThrows(AuthFailure.class, () -> cache.beforeCacheAccess(new Context(new Token(), false)));
            assertThrows(AuthFailure.class, cache::requireHealthy);
        }
    }
    @Test void failedLockAndFailedDeletionNeverReportSuccess() throws Exception {
        Memory memory = new Memory();
        try (SecureCache first = new SecureCache(root, null, memory, CacheFixtures.FIRST);
             SecureCache second = new SecureCache(root, null, memory, CacheFixtures.FIRST)) {
            Context context = new Context(new Token(), false);
            first.beforeCacheAccess(context);
            assertEquals("secure-storage-failed", assertThrows(AuthFailure.class, () -> second.beforeCacheAccess(context)).code);
            first.afterCacheAccess(context);
        }
        Memory undeletable = new Memory() { @Override public void delete() { } };
        try (SecureCache cache = new SecureCache(root.resolve("delete"), null, undeletable, CacheFixtures.FIRST)) {
            cache.seed(CacheFixtures.seed(CacheFixtures.FIRST, "subject.tenant"));
            assertEquals("cache-delete-failed", assertThrows(AuthFailure.class, cache::clear).code);
            assertNotNull(undeletable.value);
        }
    }
    @Test void unsupportedCacheRequiresReauthorizationAndPreservesOriginal() throws Exception {
        for (byte[] value : List.of("{}".getBytes(), new byte[]{(byte) 0xff}, "not-json".getBytes())) {
            Memory memory = new Memory(); memory.value = value.clone();
            try (SecureCache cache = new SecureCache(root.resolve(UUID.randomUUID().toString()), null, memory, CacheFixtures.FIRST)) {
                assertEquals("cache-unusable", assertThrows(AuthFailure.class, () -> cache.beforeCacheAccess(new Context(new Token(), false))).code);
                assertArrayEquals(value, memory.value);
            }
        }
    }
    @Test void explicitCleanupRetainsInvalidationAuthority() throws Exception {
        Memory memory = new Memory();
        try (SecureCache old = new SecureCache(root, null, memory, CacheFixtures.FIRST);
             SecureCache reset = new SecureCache(root, null, memory, CacheFixtures.FIRST)) {
            reset.clear();
            assertNull(memory.value);
            assertTrue(Files.exists(root.resolve(".busycards-authority")));
            assertEquals("interaction-required", assertThrows(AuthFailure.class, () -> old.validateResult("subject.tenant")).code);
        }
    }
    @Test void delayedNetworkCannotWriteAfterSubjectRemovalOrClear() throws Exception {
        for (boolean clear : List.of(false, true)) {
            Memory memory = new Memory(); Path path = root.resolve(clear ? "clear" : "remove");
            try (SecureCache late = new SecureCache(path, null, memory, CacheFixtures.FIRST);
                 SecureCache cleanup = new SecureCache(path, null, memory, CacheFixtures.FIRST)) {
                late.seed(CacheFixtures.seed(CacheFixtures.FIRST, "subject.tenant", "companion.tenant"));
                if (clear) cleanup.clear(); else cleanup.invalidateSubject("subject.tenant");
                Context context = new Context(new Token(), true);
                if (clear) assertThrows(AuthFailure.class, () -> late.beforeCacheAccess(context));
                else {
                    late.beforeCacheAccess(context);
                    ((Token) context.tokenCache()).value = CacheFixtures.seed(CacheFixtures.FIRST, "subject.tenant", "companion.tenant", "new.tenant");
                    // A replaced token for the removed subject is rejected even when
                    // interactive authorization did not know its subject at admission.
                    ((Token) context.tokenCache()).value = context.tokenCache().serialize().replace("synthetic-refresh", "changed-refresh");
                    assertThrows(AuthFailure.class, () -> late.afterCacheAccess(context));
                }
                if (!clear) cleanup.finishSubjectRemoval("subject.tenant");
                try (SecureCache fresh = new SecureCache(path, null, memory, CacheFixtures.FIRST)) {
                    fresh.seed(CacheFixtures.seed(CacheFixtures.FIRST, "subject.tenant"));
                    fresh.validateResult("subject.tenant");
                }
            }
        }
    }
    @Test void oldSubjectAuthorityDoesNotBlockCompanion() throws Exception {
        Memory memory = new Memory();
        try (SecureCache companion = new SecureCache(root, "companion.tenant", memory, CacheFixtures.FIRST);
             SecureCache cleaner = new SecureCache(root, null, memory, CacheFixtures.FIRST)) {
            cleaner.invalidateSubject("subject.tenant"); companion.validateResult("companion.tenant");
            assertThrows(AuthFailure.class, () -> companion.validateResult("subject.tenant"));
        }
    }
    @Test void actualMsalReadsPortableCacheAndRemovesOnlyOneHomeAccount() throws Exception {
        Memory memory = new Memory(); ExecutorService executor = Executors.newCachedThreadPool();
        try (SecureCache cache = new SecureCache(root, null, memory, CacheFixtures.FIRST)) {
            cache.seed(CacheFixtures.seed(CacheFixtures.FIRST, "subject.tenant", "companion.tenant"));
            PublicClientApplication app = Main.application(CacheFixtures.FIRST, cache, executor);
            Set<IAccount> accounts = app.getAccounts().get(5, TimeUnit.SECONDS);
            assertEquals(2, accounts.size());
            app.removeAccount(accounts.stream().filter(a -> a.homeAccountId().equals("subject.tenant")).findFirst().orElseThrow()).get(5, TimeUnit.SECONDS);
            assertEquals(Set.of("companion.tenant"), app.getAccounts().get().stream().map(IAccount::homeAccountId).collect(java.util.stream.Collectors.toSet()));
        } finally { executor.shutdownNow(); }
    }
    @Test void unusableCacheHasDedicatedRecoveryClassification() throws Exception {
        Memory memory = new Memory(); memory.value = "not-json".getBytes();
        try (var cache = new SecureCache(root, null, memory, CacheFixtures.FIRST)) {
            assertEquals("cache-unusable", assertThrows(AuthFailure.class,
                () -> cache.beforeCacheAccess(new Context(new Token(), false))).code);
        }
    }
    @Test void initializationIoIsSecureStorageFailure() throws Exception {
        Path occupied = root.resolve("occupied"); Files.writeString(occupied, "ordinary-file");
        Throwable error = assertThrows(Throwable.class,
            () -> new SecureCache(occupied.resolve("cache"), null, new Memory(), CacheFixtures.FIRST));
        assertEquals("secure-storage-failed", Main.classify(error));
    }
    @Test void interruptedRemovalKeepsAdmissionTombstoneAndRetryCompletes() throws Exception {
        Memory memory = new Memory(); var executor = Executors.newCachedThreadPool();
        try (var interrupted = new SecureCache(root, null, memory, CacheFixtures.FIRST)) {
            interrupted.seed(CacheFixtures.seed(CacheFixtures.FIRST, "subject.tenant", "companion.tenant"));
            interrupted.invalidateSubject("subject.tenant");
            memory.corruptWrite = true;
            assertEquals("secure-storage-failed", assertThrows(AuthFailure.class,
                () -> interrupted.finishSubjectRemoval("subject.tenant")).code);
        }
        try (var companion = new SecureCache(root, "companion.tenant", memory, CacheFixtures.FIRST)) {
            var app = Main.application(CacheFixtures.FIRST, companion, executor);
            assertEquals(Set.of("companion.tenant"), app.getAccounts().get().stream().map(IAccount::homeAccountId).collect(java.util.stream.Collectors.toSet()));
        }
        try (var retry = new SecureCache(root, null, memory, CacheFixtures.FIRST)) {
            retry.invalidateSubject("subject.tenant"); retry.finishSubjectRemoval("subject.tenant");
            assertFalse(new String(memory.value).contains("subject.tenant"));
        } finally { executor.shutdownNow(); }
    }
    @Test void failedClearBlocksFreshAdmissionUntilVerifiedRetry() throws Exception {
        Memory memory = new Memory() { boolean fail = true; public void delete() { if (fail) { fail = false; throw new RuntimeException(); } super.delete(); } };
        try (var first = new SecureCache(root, null, memory, CacheFixtures.FIRST)) {
            first.seed(CacheFixtures.seed(CacheFixtures.FIRST, "subject.tenant"));
            assertThrows(AuthFailure.class, first::clear);
        }
        try (var fresh = new SecureCache(root, "subject.tenant", memory, CacheFixtures.FIRST)) {
            assertThrows(AuthFailure.class, () -> fresh.beforeCacheAccess(new Context(new Token(), false)));
            fresh.clear();
        }
        try (var fresh = new SecureCache(root, "subject.tenant", memory, CacheFixtures.FIRST)) {
            fresh.validateResult("subject.tenant"); assertNull(memory.value);
        }
    }
    @Test void partialInitializationReleasesChannelAndLockForRetry() throws Exception {
        Files.createDirectory(root.resolve("msal.cache"));
        assertEquals("secure-storage-failed", assertThrows(AuthFailure.class,
            () -> new SecureCache(root, null, new Memory(), CacheFixtures.FIRST)).code);
        Files.delete(root.resolve("msal.cache"));
        try (var retry = new SecureCache(root, null, new Memory(), CacheFixtures.FIRST)) {
            retry.validateResult("subject.tenant");
            assertEquals(java.nio.file.attribute.PosixFilePermissions.fromString("rw-------"), Files.getPosixFilePermissions(root.resolve(".busycards-lock")));
            assertEquals(java.nio.file.attribute.PosixFilePermissions.fromString("rw-------"), Files.getPosixFilePermissions(root.resolve("msal.cache")));
        }
    }
}
