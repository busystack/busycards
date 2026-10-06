package io.busystack.busycards.auth;

import com.azure.json.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

final class Json {
    private Json() {}
    static Map<String, Object> object(String value) throws IOException {
        try (JsonReader reader = JsonProviders.createReader(value)) {
            reader.nextToken();
            Object parsed = reader.readUntyped();
            if (!(parsed instanceof Map<?, ?> map) || reader.nextToken() != JsonToken.END_DOCUMENT) {
                throw new IOException("invalid JSON object");
            }
            Map<String, Object> result = new LinkedHashMap<>();
            for (var entry : map.entrySet()) {
                if (!(entry.getKey() instanceof String key)) throw new IOException("invalid key");
                result.put(key, entry.getValue());
            }
            return result;
        }
    }
    static String encode(Object value) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (JsonWriter writer = JsonProviders.createWriter(bytes)) {
            writer.writeUntyped(value); writer.flush();
        }
        return bytes.toString(StandardCharsets.UTF_8);
    }
}
