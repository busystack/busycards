package io.busystack.busycards.auth;
import org.junit.jupiter.api.*; import org.junit.jupiter.api.io.TempDir;
import java.nio.file.*; import java.nio.channels.*; import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;
class InitializationTest {
 @TempDir Path root;
 @Test void markerInitializationIsInsidePersistentOsLock() throws Exception {
  try(var channel=FileChannel.open(root.resolve(".busycards-lock"),StandardOpenOption.CREATE,StandardOpenOption.READ,StandardOpenOption.WRITE); var lock=channel.lock()) {
   var child=new ProcessBuilder(System.getProperty("java.home")+"/bin/java","-cp",System.getProperty("java.class.path"),InitializationWorker.class.getName(),root.toString()).start();
   try {
    long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(10); boolean blocked=false;
    while(System.nanoTime()<end && child.isAlive()) {
     blocked=Files.readString(Path.of("/proc/locks")).lines().anyMatch(l->l.contains("->")&&l.matches(".*\\s"+child.pid()+"\\s.*"));
     if(blocked) break; Thread.onSpinWait();
    }
    assertTrue(blocked,"constructor must await OS lock");
    assertFalse(Files.exists(root.resolve("msal.cache")),"marker must not appear before obtaining initialization authority");
   } finally {child.destroyForcibly();child.waitFor(5,TimeUnit.SECONDS);}
  }
 }
}
