package io.busystack.busycards.auth;

import com.microsoft.aad.msal4j.*;
import com.microsoft.aad.msal4jextensions.persistence.ICacheAccessor;
import com.microsoft.aad.msal4jextensions.persistence.linux.KeyRingAccessor;
import java.io.*;
import java.nio.*;
import java.nio.channels.*;
import java.nio.charset.*;
import java.nio.file.*;
import java.nio.file.attribute.PosixFilePermissions;
import java.util.*;
import java.security.MessageDigest;

/** MSAL's supported access aspect with the official Linux libsecret accessor.
 * Persistent inode locks and verified commits replace extension 1.3.0's aspect,
 * which swallows IO errors and unlinks its lock file after releasing its lock.
 * No cache bytes are stored in the filesystem; only invalidation generations.
 */
final class SecureCache implements ITokenCacheAccessAspect, AutoCloseable {
    final Path directory;
    private final ICacheAccessor accessor;
    private final FileChannel channel;
    private FileLock lock;
    private final String expectedSubject;
    private Authority authority;
    private byte[] before;
    private Map<String, Object> admittedSnapshot;
    private Map<String, Object> persistedSnapshot;
    private AuthFailure failure;
    private boolean deletion;

    record Authority(long generation, Map<String, Long> subjects, Set<String> pending, boolean clearing) {}
    private Recovery recovery;
    private record Recovery(byte[] original, Authority authority, String token) {}

    static Path directory(String client) {
        String xdg = System.getenv("XDG_DATA_HOME");
        Path data = xdg == null || xdg.isBlank()
            ? Path.of(System.getProperty("user.home"), ".local", "share") : Path.of(xdg);
        if (!data.isAbsolute()) throw new AuthFailure("secure-storage-failed");
        Path root = data.resolve("io.busystack.busycards/msal");
        if (client == null || client.isBlank()) throw new AuthFailure("client-id-missing");
        return root.resolve("v2").resolve(client);
    }

    SecureCache(String client, String expectedSubject) throws IOException {
        this(directory(client), expectedSubject, null, client);
    }

    // Injection is test-only; no protocol/environment plaintext-cache option.
    SecureCache(Path directory, String subject, ICacheAccessor injected, String client) throws IOException {
        this.directory = directory;
        this.expectedSubject = subject;
        FileChannel opened = null;
        try {
            Files.createDirectories(directory);
            Files.setPosixFilePermissions(directory, PosixFilePermissions.fromString("rwx------"));
            // Tighten only application-owned parents, never the user's XDG root.
            if (directory.getParent() != null && directory.getParent().getFileName().toString().equals("v2")) {
                Files.setPosixFilePermissions(directory.getParent(), PosixFilePermissions.fromString("rwx------"));
                Files.setPosixFilePermissions(directory.getParent().getParent(), PosixFilePermissions.fromString("rwx------"));
            }
            Path lockPath = directory.resolve(".busycards-lock");
            opened = FileChannel.open(lockPath, StandardOpenOption.CREATE, StandardOpenOption.READ, StandardOpenOption.WRITE);
            channel = opened;
            Files.setPosixFilePermissions(lockPath, PosixFilePermissions.fromString("rw-------"));
            accessor = locked(() -> {
                // CREATE is idempotent. Marker/accessor initialization and clear
                // share the persistent inode lock; cleanup never unlinks it.
                Path marker = directory.resolve("msal.cache");
                try (FileChannel ignored = FileChannel.open(marker, StandardOpenOption.CREATE, StandardOpenOption.WRITE)) { }
                Files.setPosixFilePermissions(marker, PosixFilePermissions.fromString("rw-------"));
                ICacheAccessor value = injected != null ? injected : new KeyRingAccessor(marker.toString(), "default",
                    "io.busystack.busycards.msal", "BusyCards Microsoft credentials",
                    "Application", "BusyCards", "Version", "2:" + client);
                authority = readAuthority();
                if (injected == null) {
                    String probeId = UUID.randomUUID().toString();
                    ICacheAccessor probe = new KeyRingAccessor(marker.toString(), "default",
                        "io.busystack.busycards.msal", "BusyCards secure storage check",
                        "Application", "BusyCards-probe-" + probeId, "Version", probeId);
                    byte[] probeValue = probeId.getBytes(StandardCharsets.UTF_8);
                    Throwable failure = null;
                    try { probe.write(probeValue); if (!Arrays.equals(probeValue, probe.read())) throw storage(); }
                    catch (Throwable error) { failure = error; throw error; }
                    finally { try { probe.delete(); } catch (Throwable error) { if (failure == null) throw error; } }
                    if (probe.read() != null) throw storage();
                }
                return value;
            });
        } catch (Throwable error) {
            if (opened != null) try { opened.close(); } catch (IOException ignored) { }
            throw error instanceof AuthFailure typed ? typed : storage();
        }
    }

    private static AuthFailure storage() { return new AuthFailure("secure-storage-failed"); }
    private void acquire() throws IOException {
        // OS lock is released on JVM exit/kill. The inode is never unlinked.
        lock = channel.lock();
    }
    private void release() throws IOException {
        if (lock != null) { lock.release(); lock = null; }
    }
    @FunctionalInterface interface Action<T> { T run() throws Exception; }
    synchronized <T> T locked(Action<T> action) {
        Throwable original = null;
        try { acquire(); return action.run(); }
        catch (Throwable error) { original = error; throw error instanceof AuthFailure typed ? typed : storage(); }
        finally { try { release(); } catch (IOException error) { if (original == null) throw storage(); } }
    }
    private Authority readAuthority() throws IOException {
        Path path = directory.resolve(".busycards-authority");
        if (!Files.exists(path)) return new Authority(0, Map.of(), Set.of(), false);
        if (Files.size(path) > 1024 * 1024) throw storage();
        Map<String, Object> state = Json.object(Files.readString(path));
        long generation = ((Number) state.get("generation")).longValue();
        Map<String, Long> subjects = new HashMap<>();
        ((Map<?, ?>) state.get("subjects")).forEach((key, value) -> subjects.put((String) key, ((Number) value).longValue()));
        return new Authority(generation, subjects, new HashSet<>((List<String>)state.getOrDefault("pending", List.of())), Boolean.TRUE.equals(state.get("clearing")));
    }
    private void writeAuthority(Authority value) throws IOException {
        byte[] bytes = Json.encode(Map.of("generation", value.generation(), "subjects", value.subjects(), "pending", new TreeSet<>(value.pending()), "clearing", value.clearing())).getBytes(StandardCharsets.UTF_8);
        Path temporary = Files.createTempFile(directory, ".authority-", ".tmp", PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rw-------")));
        try {
            try (FileChannel file = FileChannel.open(temporary, StandardOpenOption.WRITE)) {
                ByteBuffer buffer = ByteBuffer.wrap(bytes); while (buffer.hasRemaining()) file.write(buffer); file.force(true);
            }
            Files.move(temporary, directory.resolve(".busycards-authority"), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
            try (FileChannel dir = FileChannel.open(directory, StandardOpenOption.READ)) { dir.force(true); }
        } finally { Files.deleteIfExists(temporary); }
    }
    private void check(Authority current, String subject) {
        // Admission during pending removal never gains authority over that
        // identity when completion retires the tombstone. A fresh helper
        // admitted after completion may deliberately authorize it again.
        if (current.clearing() || (!deletion && subject != null && (current.pending().contains(subject) || authority.pending().contains(subject))) || current.generation() != authority.generation() ||
            (subject != null && !Objects.equals(current.subjects().getOrDefault(subject, 0L), authority.subjects().getOrDefault(subject, 0L)))) {
            throw new AuthFailure("interaction-required");
        }
    }
    void validateResult(String subject) { locked(() -> { check(readAuthority(), subject); return null; }); }
    void invalidateSubject(String subject) {
        locked(() -> {
            Authority current = readAuthority(); Map<String, Long> subjects = new HashMap<>(current.subjects());
            subjects.put(subject, subjects.getOrDefault(subject, 0L) + 1);
            var pending = new HashSet<>(current.pending()); pending.add(subject);
            writeAuthority(new Authority(current.generation(), subjects, pending, current.clearing()));
            authority = readAuthority(); deletion = true; return null;
        });
    }
    void clear() {
        locked(() -> {
            Authority current = readAuthority(); writeAuthority(new Authority(current.generation() + 1, current.subjects(), current.pending(), true));
            accessor.delete(); if (accessor.read() != null) throw new AuthFailure("cache-delete-failed");
            Authority cleared = readAuthority();
            writeAuthority(new Authority(cleared.generation(), cleared.subjects(), Set.of(), false));
            return null;
        });
    }

    @Override public synchronized void beforeCacheAccess(ITokenCacheAccessContext context) {
        try {
            acquire(); check(readAuthority(), expectedSubject);
            before = accessor.read();
            Map<String, Object> model = before == null ? new HashMap<>(Map.of("Account", new HashMap<>())) : decode(before);
            // Pending removals are durable tombstones, including for helpers
            // admitted after invalidation but before Secret Service commit.
            if (!deletion) strip(model, readAuthority().pending());
            try {
                // Deserialize merges maps in an existing SDK cache. Normalize a
                // separate empty cache so this snapshot contains only entries
                // read under the current lock, never stale in-memory entries.
                var persisted = new TokenCache();
                persisted.deserialize(Json.encode(model));
                persistedSnapshot = Json.object(persisted.serialize());
                context.tokenCache().deserialize(Json.encode(model));
            }
            catch (Throwable unusable) { throw new AuthFailure("cache-unusable"); }
            if (admittedSnapshot == null) admittedSnapshot = Json.object(context.tokenCache().serialize());
        } catch (Throwable error) {
            try { release(); } catch (IOException ignored) { }
            failure = error instanceof AuthFailure typed ? typed : storage(); throw failure;
        }
    }
    @Override public synchronized void afterCacheAccess(ITokenCacheAccessContext context) {
        try {
            if (context.hasCacheChanged()) {
                byte[] encoded = context.tokenCache().serialize().getBytes(StandardCharsets.UTF_8);
                Authority current = readAuthority(); check(current, expectedSubject);
                if (!deletion) {
                    // Unknown interactive subjects are checked against the authority
                    // captured before browser/network work, never newly granted authority.
                    Map<String, Object> newModel = Json.object(new String(encoded, StandardCharsets.UTF_8));
                    for (String collection : List.of("Account", "AccessToken", "RefreshToken", "IdToken")) {
                        Map<?, ?> oldEntries = (Map<?, ?>) admittedSnapshot.getOrDefault(collection, Map.of());
                        Map<?, ?> persistedEntries = (Map<?, ?>) persistedSnapshot.getOrDefault(collection, Map.of());
                        var entries = ((Map<?, ?>) newModel.getOrDefault(collection, Map.of())).entrySet().iterator();
                        while (entries.hasNext()) {
                            var entry = entries.next();
                            Object subject = ((Map<?, ?>) entry.getValue()).get("home_account_id");
                            if (subject instanceof String id && (current.pending().contains(id) || authority.pending().contains(id) || !Objects.equals(current.subjects().getOrDefault(id, 0L), authority.subjects().getOrDefault(id, 0L)))) {
                                // A companion may reload a deliberate fresh
                                // authorization completed after its admission.
                                // These entries already have persisted authority;
                                // they were not produced by this pending request.
                                if (!current.pending().contains(id) && Objects.equals(persistedEntries.get(entry.getKey()), entry.getValue())) continue;
                                // SDK deserialize merges with its in-memory maps.
                                // Drop unchanged superseded entries carried by a
                                // companion request; reject newly produced tokens.
                                if (!Objects.equals(oldEntries.get(entry.getKey()), entry.getValue())) check(current, id);
                                entries.remove();
                            }
                        }
                        // An unchanged obsolete entry must not displace or omit
                        // a newly authoritative entry in the same collection.
                        Map<String, Object> merged = (Map<String, Object>)newModel.computeIfAbsent(collection, ignored -> new HashMap<>());
                        persistedEntries.forEach((key, value) -> {
                            String id = (String)((Map<?, ?>)value).get("home_account_id");
                            if (!current.pending().contains(id) && (authority.pending().contains(id) || !Objects.equals(current.subjects().getOrDefault(id, 0L), authority.subjects().getOrDefault(id, 0L)))) merged.put((String)key, value);
                        });
                    }
                    encoded = Json.encode(newModel).getBytes(StandardCharsets.UTF_8);
                }
                var filtered = Json.object(new String(encoded, StandardCharsets.UTF_8));
                strip(filtered, current.pending());
                encoded = Json.encode(filtered).getBytes(StandardCharsets.UTF_8);
                verifiedWrite(encoded, before);
            }
        } catch (Throwable error) {
            failure = error instanceof AuthFailure typed ? typed : storage(); throw failure;
        } finally { try { release(); } catch (IOException error) { failure = storage(); throw failure; } }
    }
    // Completion is a separate verified persistence step, not a claim of
    // crash atomicity between filesystem authority and Secret Service. A
    // failure keeps the tombstone so fresh helpers cannot republish old data.
    void finishSubjectRemoval(String subject) {
        locked(() -> {
            Authority current = readAuthority();
            byte[] original = accessor.read();
            Map<String, Object> model = original == null ? new HashMap<>(Map.of("Account", new HashMap<>())) : decode(original);
            strip(model, current.pending());
            verifiedWrite(Json.encode(model).getBytes(StandardCharsets.UTF_8), original);
            Set<String> pending = new HashSet<>(current.pending()); pending.remove(subject);
            writeAuthority(new Authority(current.generation(), current.subjects(), pending, current.clearing()));
            authority = readAuthority(); return null;
        });
    }
    private static Map<String, Object> decode(byte[] bytes) {
        try {
            String text = StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString();
            Map<String, Object> model = Json.object(text);
            if (!(model.get("Account") instanceof Map<?, ?>)) throw new AuthFailure("cache-unusable");
            for (String name : List.of("Account", "AccessToken", "RefreshToken", "IdToken")) {
                Object collection = model.get(name);
                if (collection != null && (!(collection instanceof Map<?, ?> entries) ||
                    entries.values().stream().anyMatch(entry -> !(entry instanceof Map<?, ?> fields) || !(fields.get("home_account_id") instanceof String id) || id.isBlank()))) throw new AuthFailure("cache-unusable");
            }
            return model;
        } catch (Throwable invalid) { throw new AuthFailure("cache-unusable"); }
    }
    private static void strip(Map<String, Object> model, Set<String> subjects) {
        for (String name : List.of("Account", "AccessToken", "RefreshToken", "IdToken")) {
            ((Map<?, ?>)model.getOrDefault(name, Map.of())).values().removeIf(
                entry -> subjects.contains(((Map<?, ?>)entry).get("home_account_id")));
        }
    }
    private void verifiedWrite(byte[] bytes, byte[] original) {
        try { accessor.write(bytes); if (!Arrays.equals(bytes, accessor.read())) throw storage(); }
        catch (Throwable failed) {
            try {
                if (original == null) accessor.delete(); else accessor.write(original);
                if (!Arrays.equals(original, accessor.read())) throw new AuthFailure("cache-rollback-failed");
            } catch (Throwable rollback) { throw new AuthFailure("cache-rollback-failed"); }
            throw storage();
        }
    }
    private String fingerprint(byte[] bytes, Authority state) throws Exception {
        var digest = MessageDigest.getInstance("SHA-256");
        digest.update(bytes == null ? new byte[0] : bytes);
        // Map.of iteration order is randomized between JVMs. Confirmation is
        // inspected and consumed by separate helpers, so hash canonical keys.
        digest.update(Json.encode(new TreeMap<>(Map.of("generation", state.generation(), "subjects", new TreeMap<>(state.subjects()),
            "pending", new TreeSet<>(state.pending()), "clearing", state.clearing()))).getBytes(StandardCharsets.UTF_8));
        return HexFormat.of().formatHex(digest.digest());
    }
    // Inspection cannot convert storage failures or ordinary consent errors
    // into permission to erase credentials. Exercise SDK deserialization too.
    String inspectUnusable() {
        return locked(() -> {
            if (readAuthority().clearing()) throw new AuthFailure("interaction-required");
            byte[] bytes = accessor.read(); boolean unusable = false;
            if (bytes != null) {
                try { new TokenCache().deserialize(Json.encode(decode(bytes))); }
                catch (Throwable error) { unusable = true; }
            }
            if (!unusable) throw new AuthFailure("cache-recovery-conflict");
            return fingerprint(bytes, readAuthority());
        });
    }
    void beginRecovery(String token) {
        locked(() -> {
            if (token == null || !token.matches("[0-9a-f]{64}")) throw new AuthFailure("invalid-request");
            if (!token.equals(inspectUnusableLocked())) throw new AuthFailure("cache-recovery-conflict");
            recovery = new Recovery(accessor.read().clone(), readAuthority(), token);
            return null;
        });
    }
    private String inspectUnusableLocked() throws Exception {
        if (readAuthority().clearing()) throw new AuthFailure("interaction-required");
        byte[] bytes = accessor.read();
        if (bytes == null) throw new AuthFailure("cache-recovery-conflict");
        try { new TokenCache().deserialize(Json.encode(decode(bytes))); }
        catch (Throwable invalid) { return fingerprint(bytes, readAuthority()); }
        throw new AuthFailure("cache-recovery-conflict");
    }
    void commitRecovery(ITokenCache staged, IAuthenticationResult result, String subject, String tenant) {
        if (recovery == null) throw new AuthFailure("invalid-request");
        Map<String, Object> identity = Main.token(result);
        if (!subject.equals(identity.get("homeAccountId")) || !tenant.equals(identity.get("tenantId"))) throw new AuthFailure("wrong-account");
        if (!((List<?>)identity.get("scopes")).stream().anyMatch(scope ->
                "Contacts.Read".equals(scope) || "Contacts.ReadWrite".equals(scope))) throw new AuthFailure("invalid-scope");
        locked(() -> {
            Authority current = readAuthority(); byte[] original = accessor.read();
            if (!recovery.token().equals(fingerprint(original, current))) throw new AuthFailure("cache-recovery-conflict");
            byte[] replacement = staged.serialize().getBytes(StandardCharsets.UTF_8); decode(replacement);
            // Never roll back invalidation, including when a verified write
            // fails. Keep the protected original bytes for an explicit retry.
            writeAuthority(new Authority(current.generation() + 1, current.subjects(), Set.of(), false));
            verifiedWrite(replacement, original);
            authority = readAuthority(); recovery = null; return null;
        });
    }
    void requireHealthy() { if (failure != null) throw failure; }
    // Fixture seeding uses the exact production accessor/lock; never a CLI command.
    void seed(String serialized) { locked(() -> { byte[] bytes = serialized.getBytes(StandardCharsets.UTF_8); accessor.write(bytes); if (!Arrays.equals(bytes, accessor.read())) throw storage(); return null; }); }
    @Override public synchronized void close() throws IOException { release(); channel.close(); }
}
