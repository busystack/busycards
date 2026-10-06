package io.busystack.busycards.auth;

import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;

/** Separate test classes, never included in the runtime distribution. */
public final class CacheFixtures {
    static final String FIRST = "00000000-0000-0000-0000-000000000001", SECOND = "00000000-0000-0000-0000-000000000002";
    static String encoded(Object value) throws Exception {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(Json.encode(value).getBytes(java.nio.charset.StandardCharsets.UTF_8));
    }
    static String tokenResponse(String client, String subject) throws Exception {
        String uid = subject.split("\\.")[0];
        String id = encoded(Map.of("alg", "none")) + "." + encoded(Map.of("tid", "tenant", "oid", uid, "sub", uid, "preferred_username", uid + "@example.test", "aud", client, "exp", 4000000000L)) + ".";
        return Json.encode(Map.of("token_type", "Bearer", "access_token", "synthetic-access-" + uid,
            "refresh_token", "synthetic-rotated-" + uid, "id_token", id, "expires_in", 3600,
            "scope", String.join(" ", Main.SCOPES), "client_info", encoded(Map.of("uid", uid, "utid", "tenant"))));
    }
    static String seed(String client, String... subjects) throws Exception {
        Map<String, Object> accounts = new HashMap<>(), refresh = new HashMap<>();
        for (String subject : subjects) {
            accounts.put(subject + "-login.microsoftonline.com-tenant", Map.of("home_account_id", subject, "environment", "login.microsoftonline.com", "realm", "tenant", "local_account_id", subject.split("\\.")[0], "username", subject + "@example.test", "authority_type", "MSSTS"));
            refresh.put(subject + "-login.microsoftonline.com-refreshtoken-" + client + "--", Map.of("home_account_id", subject, "environment", "login.microsoftonline.com", "credential_type", "RefreshToken", "client_id", client, "secret", "synthetic-refresh"));
        }
        // This is the SDK MSAL serialization shape used by synthetic fixtures.
        return Json.encode(Map.of("Account", accounts, "RefreshToken", refresh));
    }
    static String fullSeed(String client, String... subjects) throws Exception {
        var model = Json.object(seed(client, subjects));
        Map<String, Object> access = new HashMap<>(), id = new HashMap<>();
        for (String subject : subjects) {
            String identity = (String)Json.object(tokenResponse(client, subject)).get("id_token");
            access.put(subject + "-login.microsoftonline.com-accesstoken-" + client + "-tenant-contacts.readwrite", Map.of(
                "home_account_id", subject, "environment", "login.microsoftonline.com", "credential_type", "AccessToken", "client_id", client,
                "realm", "tenant", "target", "Contacts.ReadWrite", "secret", "synthetic-expired-access", "expires_on", "1", "cached_at", "1", "extended_expires_on", "1"));
            id.put(subject + "-login.microsoftonline.com-idtoken-" + client + "-tenant-", Map.of(
                "home_account_id", subject, "environment", "login.microsoftonline.com", "credential_type", "IdToken", "client_id", client,
                "realm", "tenant", "secret", identity));
        }
        model.put("AccessToken", access); model.put("IdToken", id); return Json.encode(model);
    }
    static byte[] protectedBytes(String client) throws Exception {
        var accessor = new com.microsoft.aad.msal4jextensions.persistence.linux.KeyRingAccessor(
            SecureCache.directory(client).resolve("msal.cache").toString(), "default",
            "io.busystack.busycards.msal", "BusyCards Microsoft credentials", "Application", "BusyCards", "Version", "2:" + client);
        return accessor.read();
    }
    static void assertAbsent(String client, String subject) throws Exception {
        byte[] bytes = protectedBytes(client); if (bytes == null) return;
        var model = Json.object(new String(bytes, java.nio.charset.StandardCharsets.UTF_8));
        for (String name : List.of("Account", "AccessToken", "RefreshToken", "IdToken")) {
            check(((Map<?, ?>)model.getOrDefault(name, Map.of())).values().stream()
                .noneMatch(e -> subject.equals(((Map<?, ?>)e).get("home_account_id"))));
        }
    }
    static Map<String, Object> subjectEntries(byte[] bytes, String subject) throws Exception {
        var model = Json.object(new String(bytes, java.nio.charset.StandardCharsets.UTF_8));
        Map<String, Object> snapshot = new HashMap<>();
        for (String name : List.of("Account", "AccessToken", "RefreshToken", "IdToken")) {
            Map<Object, Object> entries = new HashMap<>();
            ((Map<?, ?>)model.getOrDefault(name, Map.of())).forEach((key, value) -> {
                if (subject.equals(((Map<?, ?>)value).get("home_account_id"))) entries.put(key, value);
            });
            check(!entries.isEmpty()); snapshot.put(name, entries);
        }
        return snapshot;
    }
    // Observe the kernel's blocked OS-lock acquisition: a deterministic
    // inter-process barrier, not a timing-dependent race loop.
    static void awaitBlockedLock(Process process) throws Exception {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10);
        while (System.nanoTime() < deadline) {
            String locks = Files.readString(Path.of("/proc/locks"));
            if (locks.lines().anyMatch(line -> line.contains("->") &&
                line.matches(".*\\s" + process.pid() + "\\s.*"))) return;
            if (!process.isAlive()) throw new AssertionError("initialization escaped held lock");
            Thread.onSpinWait();
        }
        throw new AssertionError("OS lock barrier missing");
    }
    static void initializationFixtures(String helper) throws Exception {
        Path directory = SecureCache.directory(FIRST); Files.createDirectories(directory);
        Object inode;
        try (var channel = java.nio.channels.FileChannel.open(directory.resolve(".busycards-lock"),
            StandardOpenOption.CREATE, StandardOpenOption.READ, StandardOpenOption.WRITE)) {
            inode = Files.getAttribute(directory.resolve(".busycards-lock"), "unix:ino");
            Files.deleteIfExists(directory.resolve("msal.cache"));
            try (var lock = channel.lock(); var a = worker(helper, "initialize", "subject.tenant");
                var b = worker(helper, "initialize", "companion.tenant")) {
                check(a.output.readLine().equals("STARTING")); check(b.output.readLine().equals("STARTING"));
                awaitBlockedLock(a.process); awaitBlockedLock(b.process);
                check(!Files.exists(directory.resolve("msal.cache")));
                lock.release();
                check(a.output.readLine().equals("SUCCESS")); check(b.output.readLine().equals("SUCCESS"));
                check(a.process.waitFor(10, TimeUnit.SECONDS) && a.process.exitValue() == 0);
                check(b.process.waitFor(10, TimeUnit.SECONDS) && b.process.exitValue() == 0);
            }
        }
        check(inode.equals(Files.getAttribute(directory.resolve(".busycards-lock"), "unix:ino")));
        resetSeed();
        try (var channel = java.nio.channels.FileChannel.open(directory.resolve(".busycards-lock"), StandardOpenOption.READ, StandardOpenOption.WRITE);
            var lock = channel.lock(); var clearing = worker(helper, "clear", "subject.tenant");
            var initializing = worker(helper, "initialize", "companion.tenant")) {
            check(clearing.output.readLine().equals("STARTING")); check(initializing.output.readLine().equals("STARTING"));
            awaitBlockedLock(clearing.process); awaitBlockedLock(initializing.process); lock.release();
            check(clearing.output.readLine().equals("SUCCESS")); check(initializing.output.readLine().equals("SUCCESS"));
            check(clearing.process.waitFor(10, TimeUnit.SECONDS) && initializing.process.waitFor(10, TimeUnit.SECONDS));
            check(clearing.process.exitValue() == 0 && initializing.process.exitValue() == 0);
        }
        check(inode.equals(Files.getAttribute(directory.resolve(".busycards-lock"), "unix:ino")));
        check(count(helper, FIRST) == 0);
        System.out.println("PASS J3 simultaneous first initialization and initialization/clear use the persistent lock inode");
    }
    static Map<String, Object> command(String helper, String method, String client, String subject) throws Exception {
        Process process = new ProcessBuilder(helper).start();
        Map<String, Object> request = new HashMap<>(Map.of("version", 1, "requestId", "fixture", "method", method, "clientId", client, "scopes", List.of()));
        if (subject != null) request.put("homeAccountId", subject);
        Main.writeFrame(process.getOutputStream(), request); process.getOutputStream().close();
        if (!process.waitFor(20, TimeUnit.SECONDS)) { process.destroyForcibly(); process.waitFor(5, TimeUnit.SECONDS); throw new AssertionError("helper timeout"); }
        DataInputStream input = new DataInputStream(process.getInputStream()); int length = input.readInt();
        if (length <= 0 || length > Main.MAX_RESPONSE) throw new AssertionError("response bound");
        Map<String, Object> response = Json.object(new String(input.readNBytes(length), java.nio.charset.StandardCharsets.UTF_8));
        if (process.exitValue() != 0 || !Boolean.TRUE.equals(response.get("ok"))) throw new AssertionError("fixture command failed: " + method);
        return (Map<String, Object>) response.get("result");
    }
    static int count(String helper, String client) throws Exception { return ((List<?>) command(helper, "listAccounts", client, null).get("accounts")).size(); }
    static void check(boolean condition) { if (!condition) throw new AssertionError("cache fixture invariant"); }
    record Worker(Process process, BufferedReader output) implements AutoCloseable {
        void release(boolean success) throws Exception {
            process.getOutputStream().write(1); process.getOutputStream().flush();
            String line = output.readLine();
            check(success ? line.equals("SUCCESS") : line.equals("BLOCKED interaction-required"));
            check(process.waitFor(15, TimeUnit.SECONDS)); check(process.exitValue() == (success ? 0 : 2));
        }
        public void close() { if (process.isAlive()) process.destroyForcibly(); }
    }
    static Worker worker(String helper, String mode, String subject) throws Exception {
        Path dist = Path.of(helper).getParent();
        Process process = new ProcessBuilder(dist.resolve("microsoft-auth/runtime/bin/java").toString(),
            "--enable-native-access=ALL-UNNAMED", "-cp", System.getProperty("java.class.path"),
            CacheWorker.class.getName(), mode, FIRST, subject).start();
        return new Worker(process, new BufferedReader(new InputStreamReader(process.getInputStream())));
    }
    static void resetSeed() throws Exception {
        try (var cache = new SecureCache(FIRST, null)) { cache.seed(fullSeed(FIRST, "subject.tenant", "companion.tenant")); }
    }
    static void storageFailure(String helper, boolean unavailable) throws Exception {
        var builder = new ProcessBuilder(helper);
        if (unavailable) builder.environment().put("DBUS_SESSION_BUS_ADDRESS", "unix:path=" + System.getenv("XDG_RUNTIME_DIR") + "/absent-bus");
        Process process = builder.start();
        Main.writeFrame(process.getOutputStream(), Map.of("version", 1, "requestId", "storage-failure", "method", "listAccounts", "clientId", FIRST));
        process.getOutputStream().close();
        if (!process.waitFor(20, TimeUnit.SECONDS)) { process.destroyForcibly(); process.waitFor(5, TimeUnit.SECONDS); throw new AssertionError("secure storage did not fail promptly"); }
        var input = new DataInputStream(process.getInputStream()); int size = input.readInt(); check(size > 0 && size < Main.MAX_RESPONSE);
        var response = Json.object(new String(input.readNBytes(size), java.nio.charset.StandardCharsets.UTF_8));
        check(process.exitValue() == 2 && ((Map<?, ?>) response.get("error")).get("code").equals("secure-storage-failed"));
        check(process.getErrorStream().readAllBytes().length == 0);
    }
    public static void main(String[] args) throws Exception {
        if (args.length != 1 || System.getenv("XDG_DATA_HOME") == null) throw new AssertionError("disposable runner required");
        String helper = Path.of(args[0]).toAbsolutePath().toString();
        try (SecureCache a = new SecureCache(FIRST, null); SecureCache b = new SecureCache(SECOND, null)) {
            a.seed(seed(FIRST, "subject.tenant", "companion.tenant")); b.seed(seed(SECOND, "subject.tenant"));
        }
        check(count(helper, FIRST) == 2); check(count(helper, SECOND) == 1);
        // Multiple real one-request JVMs enumerate/remove concurrently against
        // the matching distribution jars and a separate D-Bus/keyring.
        ExecutorService executor = Executors.newFixedThreadPool(3);
        try {
            Future<?> removal = executor.submit(() -> { try { check(Boolean.TRUE.equals(command(helper, "removeAccount", SECOND, "subject.tenant").get("removed"))); } catch (Exception e) { throw new RuntimeException(e); } });
            Future<?> enumeration = executor.submit(() -> { try { check(count(helper, FIRST) == 2); } catch (Exception e) { throw new RuntimeException(e); } });
            removal.get(); enumeration.get();
        } finally { executor.shutdownNow(); }
        check(count(helper, SECOND) == 0); check(count(helper, FIRST) == 2);
        check(Boolean.TRUE.equals(command(helper, "removeAccount", FIRST, "subject.tenant").get("removed")));
        check(count(helper, FIRST) == 1); command(helper, "clearCache", FIRST, null); check(count(helper, FIRST) == 0);
        // Actual MSAL refreshes in separate JVMs share the production keyring.
        resetSeed();
        try (var a = worker(helper, "refresh", "subject.tenant"); var b = worker(helper, "refresh", "companion.tenant")) {
            check(a.output.readLine().equals("TOKEN_PENDING")); check(b.output.readLine().equals("TOKEN_PENDING"));
            a.release(true); b.release(true);
        }
        check(count(helper, FIRST) == 2);
        for (String mode : List.of("refresh", "interactive")) {
            for (boolean clear : List.of(false, true)) {
                command(helper, "clearCache", FIRST, null); resetSeed();
                try (var late = worker(helper, mode, "subject.tenant")) {
                    String signal = late.output.readLine();
                    if (!"TOKEN_PENDING".equals(signal)) throw new AssertionError("network barrier " + mode + ": " + signal);
                    command(helper, clear ? "clearCache" : "removeAccount", FIRST, clear ? null : "subject.tenant");
                    late.release(false);
                }
                check(count(helper, FIRST) == (clear ? 0 : 1));
            }
        }
        command(helper, "clearCache", FIRST, null); resetSeed();
        try (var companion = worker(helper, "refresh", "companion.tenant")) {
            check(companion.output.readLine().equals("TOKEN_PENDING"));
            command(helper, "removeAccount", FIRST, "subject.tenant"); companion.release(true);
        }
        check(count(helper, FIRST) == 1);
        try (var independent = new SecureCache(SECOND, null)) { independent.seed(seed(SECOND, "independent.tenant")); }
        byte[] independentBefore = protectedBytes(SECOND);
        // B's original refresh must succeed even when A is removed and
        // deliberately authorized again before that response is delivered.
        command(helper, "clearCache", FIRST, null); resetSeed();
        try (var companion = worker(helper, "refresh", "companion.tenant")) {
            check(companion.output.readLine().equals("TOKEN_PENDING"));
            command(helper, "removeAccount", FIRST, "subject.tenant"); assertAbsent(FIRST, "subject.tenant");
            try (var fresh = worker(helper, "interactive", "subject.tenant")) {
                check(fresh.output.readLine().equals("TOKEN_PENDING")); fresh.release(true);
            }
            var renewed = subjectEntries(protectedBytes(FIRST), "subject.tenant");
            companion.release(true);
            check(renewed.equals(subjectEntries(protectedBytes(FIRST), "subject.tenant")));
            subjectEntries(protectedBytes(FIRST), "companion.tenant");
        }
        check(count(helper, FIRST) == 2); check(Arrays.equals(independentBefore, protectedBytes(SECOND)));
        System.out.println("Pending companion refresh after removal and fresh authorization: passed");
        // Admit a companion after invalidation, while deletion is held.
        command(helper, "clearCache", FIRST, null); resetSeed();
        try (var removal = worker(helper, "removeGap", "subject.tenant")) {
            check(removal.output.readLine().equals("STARTING")); check(removal.output.readLine().equals("INVALIDATED"));
            try (var companion = worker(helper, "refresh", "companion.tenant")) {
                check(companion.output.readLine().equals("TOKEN_PENDING"));
                removal.release(true); companion.release(true);
            }
        }
        check(count(helper, FIRST) == 1); assertAbsent(FIRST, "subject.tenant"); check(count(helper, SECOND) == 1);
        check(Arrays.equals(independentBefore, protectedBytes(SECOND)));
        // Unknown interactive A is admitted in the same gap. Its late token
        // response must not acquire authority just because removal completed.
        command(helper, "clearCache", FIRST, null); resetSeed();
        try (var removal = worker(helper, "removeGap", "subject.tenant")) {
            check(removal.output.readLine().equals("STARTING")); check(removal.output.readLine().equals("INVALIDATED"));
            try (var late = worker(helper, "interactive", "subject.tenant")) {
                check(late.output.readLine().equals("TOKEN_PENDING"));
                removal.release(true); late.release(false);
            }
        }
        assertAbsent(FIRST, "subject.tenant"); check(count(helper, FIRST) == 1);
        check(Arrays.equals(independentBefore, protectedBytes(SECOND)));
        // A newly admitted interactive request may deliberately authorize the
        // removed identity again after verified removal has completed.
        try (var fresh = worker(helper, "interactive", "subject.tenant")) {
            check(fresh.output.readLine().equals("TOKEN_PENDING")); fresh.release(true);
        }
        check(count(helper, FIRST) == 2);
        check(Arrays.equals(independentBefore, protectedBytes(SECOND)));
        // Interrupt the deleter in that exact window. Durable authority must
        // filter new admissions until a fresh framed retry completes removal.
        command(helper, "clearCache", FIRST, null); resetSeed();
        try (var interrupted = worker(helper, "removeGap", "subject.tenant")) {
            check(interrupted.output.readLine().equals("STARTING")); check(interrupted.output.readLine().equals("INVALIDATED"));
            interrupted.process.destroyForcibly(); check(interrupted.process.waitFor(5, TimeUnit.SECONDS));
        }
        check(count(helper, FIRST) == 1); command(helper, "removeAccount", FIRST, "subject.tenant");
        assertAbsent(FIRST, "subject.tenant"); check(count(helper, FIRST) == 1);
        // Explicit actual command repair bypasses malformed cache only in a
        // staged in-memory SDK application; cancellation preserves old bytes.
        try (var cache = new SecureCache(FIRST, null)) { cache.seed("not-json"); }
        check(((String)command(helper, "inspectCache", FIRST, null).get("recoveryToken")).matches("[0-9a-f]{64}"));
        try (var repair = worker(helper, "repair", "subject.tenant")) {
            String signal = repair.output.readLine();
            if (!"TOKEN_PENDING".equals(signal)) throw new AssertionError("repair barrier: " + signal);
            repair.release(true);
        }
        check(count(helper, FIRST) == 1);
        try (var fresh = worker(helper, "refresh", "subject.tenant")) {
            // This token is still valid, so no network barrier is necessary.
            String signal = fresh.output.readLine();
            if (!"SUCCESS".equals(signal)) throw new AssertionError("fresh silent barrier: " + signal);
            check(fresh.process.waitFor(10, TimeUnit.SECONDS));
            check(fresh.process.exitValue() == 0);
        }
        try (var cache = new SecureCache(FIRST, null)) { cache.seed("not-json"); }
        try (var repair = worker(helper, "repair", "subject.tenant")) {
            String signal = repair.output.readLine();
            if (!"TOKEN_PENDING".equals(signal)) throw new AssertionError("pending repair barrier: " + signal);
            repair.process.destroyForcibly(); check(repair.process.waitFor(5, TimeUnit.SECONDS));
        }
        try (var cache = new SecureCache(FIRST, null)) {
            var executorRepair = Executors.newCachedThreadPool();
            try { check(cache.inspectUnusable().length() == 64); }
            finally { executorRepair.shutdownNow(); }
            cache.clear();
        }
        try (var cache = new SecureCache(FIRST, null)) { cache.seed("not-json"); }
        try (var repair = worker(helper, "repairPending", "subject.tenant")) {
            String signal = repair.output.readLine(); check(signal.startsWith("BROWSER_PENDING "));
            int port = Integer.parseInt(signal.substring("BROWSER_PENDING ".length()));
            repair.process.destroyForcibly(); check(repair.process.waitFor(5, TimeUnit.SECONDS));
            try (var socket = new java.net.Socket("127.0.0.1", port)) { throw new AssertionError("orphan repair listener"); }
            catch (java.net.ConnectException expected) { }
        }
        try (var cache = new SecureCache(FIRST, null)) { check(cache.inspectUnusable().length() == 64); cache.clear(); }
        initializationFixtures(helper);
        System.out.println("PASS J1 post-invalidation admission, all token collections, interrupted removal/retry; J2 confirmed repair/restart/silent and killed repair preservation");
        // Kill a real MSAL interactive JVM while its loopback listener waits.
        try (var pending = worker(helper, "interactivePending", "subject.tenant")) {
            String signal = pending.output.readLine(); check(signal.startsWith("BROWSER_PENDING "));
            int port = Integer.parseInt(signal.substring("BROWSER_PENDING ".length()));
            pending.process.destroyForcibly(); check(pending.process.waitFor(5, TimeUnit.SECONDS));
            try (var socket = new java.net.Socket("127.0.0.1", port)) { throw new AssertionError("orphan callback listener"); }
            catch (java.net.ConnectException expected) { }
        }
        command(helper, "clearCache", FIRST, null);
        storageFailure(helper, true);
        // Lock only this runner's disposable collection. With no display,
        // libsecret cannot silently prompt or use the owner's desktop keyring.
        Process locking = new ProcessBuilder("gdbus", "call", "--session", "--dest", "org.freedesktop.secrets",
            "--object-path", "/org/freedesktop/secrets", "--method", "org.freedesktop.Secret.Service.Lock",
            "['/org/freedesktop/secrets/collection/login']").redirectOutput(ProcessBuilder.Redirect.DISCARD).redirectError(ProcessBuilder.Redirect.DISCARD).start();
        check(locking.waitFor(5, TimeUnit.SECONDS) && locking.exitValue() == 0);
        storageFailure(helper, false);
        System.out.println("PASS actual MSAL4J portable-cache enumeration/removal/isolation/concurrent processes; Secret Service only");
        System.out.println("PASS multi-JVM refresh/interactive removal and clear races, companion merge, and callback cancellation");
        System.out.println("PASS unavailable and locked disposable keyring errors without plaintext fallback");
    }
}
