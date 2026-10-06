package io.busystack.busycards.auth;
public class InitializationWorker {
 public static void main(String[] args) throws Exception {
  try (var cache = new SecureCache(java.nio.file.Path.of(args[0]), null, new SecureCacheTest.Memory(), CacheFixtures.FIRST)) { }
 }
}
