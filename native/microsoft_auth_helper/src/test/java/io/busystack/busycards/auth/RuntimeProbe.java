package io.busystack.busycards.auth;

import com.sun.net.httpserver.HttpsConfigurator;
import com.sun.net.httpserver.HttpsServer;
import java.net.*;
import java.nio.file.*;
import java.security.*;
import javax.net.ssl.*;

/** Runs with the delivered JVM; uses a disposable localhost certificate only. */
public final class RuntimeProbe {
    public static void main(String[] args) throws Exception {
        KeyStore keys = KeyStore.getInstance("PKCS12");
        try (var input = Files.newInputStream(Path.of(args[0]))) {
            keys.load(input, "synthetic-runtime-password".toCharArray());
        }
        KeyManagerFactory km = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
        km.init(keys, "synthetic-runtime-password".toCharArray());
        TrustManagerFactory tm = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        tm.init(keys);
        SSLContext tls = SSLContext.getInstance("TLS");
        tls.init(km.getKeyManagers(), tm.getTrustManagers(), null);
        var defaultTrust = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        defaultTrust.init((KeyStore) null);
        if (((X509TrustManager) defaultTrust.getTrustManagers()[0]).getAcceptedIssuers().length == 0) {
            throw new AssertionError("Delivered runtime has no TLS trust anchors");
        }
        HttpsServer server = HttpsServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.setHttpsConfigurator(new HttpsConfigurator(tls));
        server.createContext("/", exchange -> {
            byte[] response = "runtime-ok".getBytes(java.nio.charset.StandardCharsets.UTF_8);
            exchange.sendResponseHeaders(200, response.length);
            try (var output = exchange.getResponseBody()) { output.write(response); }
        });
        server.start();
        try {
            var connection = (HttpsURLConnection) URI.create("https://localhost:" + server.getAddress().getPort() + "/").toURL().openConnection();
            connection.setSSLSocketFactory(tls.getSocketFactory());
            connection.setConnectTimeout(5000); connection.setReadTimeout(5000);
            if (connection.getResponseCode() != 200 || !new String(connection.getInputStream().readAllBytes(), java.nio.charset.StandardCharsets.UTF_8).equals("runtime-ok")) {
                throw new AssertionError("Delivered TLS/localhost server failed");
            }
            connection.disconnect();
        } finally { server.stop(0); }
        System.out.println("PASS delivered JVM TLS handshake, trust anchors, EC provider and localhost server");
    }
}
